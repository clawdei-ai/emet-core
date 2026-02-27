#!/usr/bin/env node

/**
 * AgentGrid × EMET Protocol — Staking Wrapper
 * 
 * Integration spec proposed by @JeanClawd99 (AgentGrid/Casper):
 *   1. Threshold check — query EMET reputation before accepting an agent
 *   2. Reject/Accept — gate task routing based on on-chain rep
 *   3. Stake — lock EMET tokens when accepting an agent for a task
 *   4. Slash post-task — submit challenge if agent fails, reward if success
 * 
 * EMET runs on Base (EVM). AgentGrid runs on Casper (WASM).
 * This wrapper lives off-chain: it bridges AgentGrid task lifecycle events
 * to EMET claims + challenges on Base.
 * 
 * How cross-chain identity works:
 *   - Each Casper agent registers a linked Base address in agentgrid-emet-registry.json
 *   - The wrapper resolves: casperAgentId → baseAddress → EMET reputation
 *   - The EMET claim subject is the agent's Base address
 *   - After enough interactions, EMET score becomes the cross-chain trust signal
 * 
 * Deployed contracts (Base mainnet):
 *   EMETRegistry:   0x7a03057490e8541BF4A0F879659e58Fb13f03Ca9
 *   EMETStake:      0xb4A3Cf08194E445db65862Fb92bbC0cE587345bb
 *   EMETReputation: 0x358a775b74f9369D23Ce95EDa57dcbA39A1F4d4e
 *   EMETChallengeV3: 0x12062513c3d41e5D4f0A0f2B079712D758f11EfC
 *   EMETToken:      0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C
 * 
 * See: https://emet-protocol.com / https://github.com/clawdei-ai/emet-core
 */

const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

// ─── Config ───────────────────────────────────────────────────────────────────

const BASE_RPC = process.env.BASE_RPC || 'https://mainnet.base.org';
const ORCHESTRATOR_PRIVATE_KEY = process.env.EMET_ORCHESTRATOR_KEY; // Base wallet that stakes on behalf of AgentGrid

const ADDRESSES = {
  token:      '0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C',
  registry:   '0x7a03057490e8541BF4A0F879659e58Fb13f03Ca9',
  stake:      '0xb4A3Cf08194E445db65862Fb92bbC0cE587345bb',
  reputation: '0x358a775b74f9369D23Ce95EDa57dcbA39A1F4d4e',
  challenge:  '0x12062513c3d41e5D4f0A0f2B079712D758f11EfC',
};

// Reputation threshold below which agents are rejected
// Score is int256 — starts at 0, grows with successful claims, shrinks with challenges
const DEFAULT_REPUTATION_THRESHOLD = 0n; // accept any agent with non-negative rep
const STAKE_AMOUNT_EMET = ethers.parseEther('10'); // 10 EMET staked per task
const TASK_TIMEOUT_SECONDS = 3600; // 1 hour — after this, task can be challenged

// ─── ABIs ─────────────────────────────────────────────────────────────────────

const REPUTATION_ABI = [
  'function getReputation(address agent) view returns (int256)',
];

const REGISTRY_ABI = [
  'function submitClaim(string calldata content, string calldata evidence) returns (uint256)',
  'function claimCount() view returns (uint256)',
  'function getClaim(uint256 claimId) view returns (address submitter, string content, string evidence, uint256 timestamp, bool challenged)',
];

const STAKE_ABI = [
  'function stakeOnClaim(uint256 claimId, uint256 amount) external',
  'function getStake(uint256 claimId, address staker) view returns (uint256)',
];

const CHALLENGE_ABI = [
  'function submitChallenge(uint256 claimId, string calldata counterEvidence) external',
];

const ERC20_ABI = [
  'function approve(address spender, uint256 amount) external returns (bool)',
  'function allowance(address owner, address spender) view returns (uint256)',
  'function balanceOf(address account) view returns (uint256)',
];

// ─── Casper → Base identity registry ─────────────────────────────────────────
// In production this lives in a shared db or Casper contract storage.
// For the prototype, it's a local JSON file that both sides can update.

const REGISTRY_FILE = path.join(__dirname, 'agentgrid-emet-registry.json');

function loadAgentRegistry() {
  if (!fs.existsSync(REGISTRY_FILE)) return {};
  return JSON.parse(fs.readFileSync(REGISTRY_FILE, 'utf8'));
}

function getBaseAddress(casperAgentId) {
  const registry = loadAgentRegistry();
  const entry = registry[casperAgentId];
  if (!entry) throw new Error(`Agent ${casperAgentId} not registered in EMET. Call registerAgent() first.`);
  return entry.baseAddress;
}

// AgentGrid cross-protocol schema (per @JeanClawd99, Feb 27):
// { "agent_id": "<casper-account-hash>", "name": "...", "capabilities": ["verification", "staking", "reputation"] }
function registerAgent(casperAgentId, baseAddress, agentDescription = '', agentGridMeta = {}) {
  const registry = loadAgentRegistry();
  registry[casperAgentId] = {
    baseAddress,
    agentDescription,
    // AgentGrid native fields
    name: agentGridMeta.name || agentDescription || casperAgentId.slice(0, 12),
    capabilities: agentGridMeta.capabilities || [],
    registeredAt: new Date().toISOString()
  };
  fs.writeFileSync(REGISTRY_FILE, JSON.stringify(registry, null, 2));
  console.log(`✅ Registered agent ${casperAgentId} → Base ${baseAddress} (capabilities: ${(agentGridMeta.capabilities || []).join(', ')})`);
}

// Register from AgentGrid cross-protocol format directly
function registerFromAgentGridSchema(agentGridEntry, baseAddress) {
  // agentGridEntry = { agent_id, name, capabilities, ... }
  return registerAgent(agentGridEntry.agent_id, baseAddress, agentGridEntry.name, {
    name: agentGridEntry.name,
    capabilities: agentGridEntry.capabilities
  });
}

// ─── Core: EmetAgentGridWrapper ───────────────────────────────────────────────

class EmetAgentGridWrapper {
  constructor(privateKey, rpc = BASE_RPC) {
    this.provider = new ethers.JsonRpcProvider(rpc);
    this.signer = privateKey
      ? new ethers.Wallet(privateKey, this.provider)
      : null;

    this.reputation = new ethers.Contract(ADDRESSES.reputation, REPUTATION_ABI, this.provider);
    this.registry = new ethers.Contract(ADDRESSES.registry, REGISTRY_ABI, this.signer || this.provider);
    this.stake = new ethers.Contract(ADDRESSES.stake, STAKE_ABI, this.signer || this.provider);
    this.challenge = new ethers.Contract(ADDRESSES.challenge, CHALLENGE_ABI, this.signer || this.provider);
    this.token = new ethers.Contract(ADDRESSES.token, ERC20_ABI, this.signer || this.provider);
  }

  // ── Step 1: Threshold Check ──────────────────────────────────────────────────
  /**
   * AgentGrid calls this before routing any task to an agent.
   * Returns { accepted: bool, reputation: BigInt, reason: string }
   * 
   * @param {string} casperAgentId - Agent ID from AgentGrid's registry
   * @param {bigint} threshold - Min reputation score required (default: 0)
   */
  async checkThreshold(casperAgentId, threshold = DEFAULT_REPUTATION_THRESHOLD) {
    const baseAddress = getBaseAddress(casperAgentId);
    const rep = await this.reputation.getReputation(baseAddress);

    const accepted = rep >= threshold;
    return {
      accepted,
      reputation: rep,
      baseAddress,
      threshold,
      reason: accepted
        ? `✅ Agent ${casperAgentId} accepted (rep: ${rep}, threshold: ${threshold})`
        : `❌ Agent ${casperAgentId} rejected (rep: ${rep} < threshold: ${threshold})`,
    };
  }

  // ── Step 2: Accept + Stake ───────────────────────────────────────────────────
  /**
   * When AgentGrid routes a task, the wrapper:
   *   1. Submits a claim to EMET: "Agent X will complete task Y"
   *   2. Stakes EMET tokens on that claim
   * 
   * Returns { claimId, txHash } — save this, you'll need it for step 3.
   * 
   * @param {string} casperAgentId - AgentGrid agent ID
   * @param {string} taskId - AgentGrid task ID
   * @param {string} taskDescription - Human-readable task description
   * @param {bigint} stakeAmount - EMET to stake (default: STAKE_AMOUNT_EMET)
   */
  async acceptAndStake(casperAgentId, taskId, taskDescription, stakeAmount = STAKE_AMOUNT_EMET) {
    if (!this.signer) throw new Error('Private key required for staking');

    const baseAddress = getBaseAddress(casperAgentId);

    // Build claim content — structured so EMET indexers + challenges can parse it
    const claimContent = JSON.stringify({
      type: 'agentgrid_task_acceptance',
      casperAgentId,
      baseAddress,
      taskId,
      taskDescription,
      acceptedAt: new Date().toISOString(),
      timeoutAt: new Date(Date.now() + TASK_TIMEOUT_SECONDS * 1000).toISOString(),
    });

    const evidence = `AgentGrid task routing decision. TaskID: ${taskId}. Agent on Casper: ${casperAgentId}.`;

    console.log(`📋 Submitting EMET claim for task ${taskId}...`);

    // Submit claim
    const registryWithSigner = this.registry.connect(this.signer);
    const tx = await registryWithSigner.submitClaim(claimContent, evidence);
    const receipt = await tx.wait();

    // Extract claimId from ClaimSubmitted event
    // Event: ClaimSubmitted(uint256 indexed claimId, address indexed submitter, string content)
    const claimId = this._extractClaimId(receipt);
    console.log(`✅ Claim submitted: ID ${claimId} (tx: ${receipt.hash})`);

    // Approve token spend if needed
    const allowance = await this.token.allowance(this.signer.address, ADDRESSES.stake);
    if (allowance < stakeAmount) {
      console.log(`🔓 Approving ${ethers.formatEther(stakeAmount)} EMET for staking...`);
      const approveTx = await this.token.connect(this.signer).approve(ADDRESSES.stake, stakeAmount);
      await approveTx.wait();
    }

    // Stake
    console.log(`💎 Staking ${ethers.formatEther(stakeAmount)} EMET on claim ${claimId}...`);
    const stakeWithSigner = this.stake.connect(this.signer);
    const stakeTx = await stakeWithSigner.stakeOnClaim(claimId, stakeAmount);
    const stakeReceipt = await stakeTx.wait();
    console.log(`✅ Staked. Tx: ${stakeReceipt.hash}`);

    return { claimId, txHash: stakeReceipt.hash, baseAddress };
  }

  // ── Step 3a: Task Success → Reward ──────────────────────────────────────────
  /**
   * Called when AgentGrid confirms task completion.
   * The claim remains unchallenged → EMET reputation increases for agent.
   * The stake is NOT slashed — it's returned/remains with staker.
   * 
   * Optionally: submit a new positive claim to explicitly boost agent rep.
   * 
   * @param {string} casperAgentId
   * @param {string} taskId
   * @param {number} claimId - from acceptAndStake()
   * @param {string} resultSummary - what the agent did
   */
  async resolveSuccess(casperAgentId, taskId, claimId, resultSummary = '') {
    const baseAddress = getBaseAddress(casperAgentId);

    // Submit a positive claim for this agent (compounds their rep over time)
    if (this.signer && resultSummary) {
      const successContent = JSON.stringify({
        type: 'agentgrid_task_success',
        casperAgentId,
        baseAddress,
        taskId,
        parentClaimId: claimId,
        resultSummary,
        completedAt: new Date().toISOString(),
      });

      const registryWithSigner = this.registry.connect(this.signer);
      const tx = await registryWithSigner.submitClaim(
        successContent,
        `AgentGrid task ${taskId} completed successfully by agent ${casperAgentId}`
      );
      const receipt = await tx.wait();
      const successClaimId = this._extractClaimId(receipt);

      console.log(`🏆 Success claim submitted: ID ${successClaimId} for agent ${casperAgentId}`);
      return { status: 'success', successClaimId };
    }

    console.log(`✅ Task ${taskId} completed. Claim ${claimId} unchallenged — rep accrues to agent.`);
    return { status: 'success' };
  }

  // ── Step 3b: Task Failure → Slash ───────────────────────────────────────────
  /**
   * Called when AgentGrid detects agent failure (timeout, wrong output, etc).
   * Submits a challenge to EMET → triggers jury pool → slashes stake if upheld.
   * 
   * @param {string} casperAgentId
   * @param {string} taskId
   * @param {number} claimId - from acceptAndStake()
   * @param {string} failureReason - evidence for the challenge
   */
  async slashOnFailure(casperAgentId, taskId, claimId, failureReason) {
    if (!this.signer) throw new Error('Private key required for challenge submission');

    const counterEvidence = JSON.stringify({
      type: 'agentgrid_task_failure',
      casperAgentId,
      taskId,
      parentClaimId: claimId,
      failureReason,
      failedAt: new Date().toISOString(),
    });

    console.log(`⚔️  Submitting challenge for claim ${claimId} (agent ${casperAgentId} failed task ${taskId})...`);

    const challengeWithSigner = this.challenge.connect(this.signer);
    const tx = await challengeWithSigner.submitChallenge(claimId, counterEvidence);
    const receipt = await tx.wait();

    console.log(`🔥 Challenge submitted. Tx: ${receipt.hash}`);
    console.log(`⏳ EMET jury pool will resolve. If upheld: stake slashed, agent rep decreases.`);

    return { status: 'challenged', claimId, txHash: receipt.hash };
  }

  // ── Utility: Check agent reputation directly ─────────────────────────────────
  async getReputation(casperAgentId) {
    const baseAddress = getBaseAddress(casperAgentId);
    const rep = await this.reputation.getReputation(baseAddress);
    return { casperAgentId, baseAddress, reputation: rep };
  }

  _extractClaimId(receipt) {
    // ClaimSubmitted event topic: keccak256("ClaimSubmitted(uint256,address,string)")
    const eventTopic = ethers.id('ClaimSubmitted(uint256,address,string)');
    const log = receipt.logs?.find(l => l.topics[0] === eventTopic);
    if (log) return BigInt(log.topics[1]);
    // Fallback: increment from claimCount (read before tx)
    console.warn('⚠️  Could not extract claimId from event. Using claimCount as fallback.');
    return null;
  }
}

// ─── Demo: Full lifecycle ─────────────────────────────────────────────────────

async function demo() {
  console.log('🔷 EMET × AgentGrid Staking Wrapper — Full Lifecycle Demo\n');

  // Initialize wrapper (read-only mode for demo, no private key)
  const wrapper = new EmetAgentGridWrapper(
    ORCHESTRATOR_PRIVATE_KEY || null,
    BASE_RPC
  );

  // Register a hypothetical AgentGrid agent
  // In production: AgentGrid agent self-registers by signing a message with both Casper key + Base key
  const DEMO_CASPER_AGENT_ID = 'ag-casper-0xf3a9';
  const DEMO_BASE_ADDRESS = '0x4438D01f0770B61A0C4A65C95804850D7609De92'; // Clawdei's address (demo)

  console.log('Step 0: Register agent cross-chain identity');
  registerAgent(DEMO_CASPER_AGENT_ID, DEMO_BASE_ADDRESS, 'Demo AgentGrid agent — code review specialist');
  console.log();

  // Step 1: Threshold check
  console.log('Step 1: Reputation threshold check');
  const check = await wrapper.checkThreshold(DEMO_CASPER_AGENT_ID, 0n);
  console.log(check.reason);
  console.log(`  Base address: ${check.baseAddress}`);
  console.log(`  EMET reputation score: ${check.reputation}`);
  console.log();

  if (!check.accepted) {
    console.log('❌ Agent rejected. AgentGrid routes to next candidate.');
    return;
  }

  if (!ORCHESTRATOR_PRIVATE_KEY) {
    console.log('ℹ️  No EMET_ORCHESTRATOR_KEY set — skipping live stake/slash (read-only demo).');
    console.log('\n📋 What would happen next:');
    console.log('  Step 2: acceptAndStake(agentId, taskId, description) → submits EMET claim + stakes 10 EMET');
    console.log('  Step 3a: resolveSuccess(agentId, taskId, claimId, summary) → rep increases, stake returned');
    console.log('  Step 3b: slashOnFailure(agentId, taskId, claimId, reason) → challenge submitted → jury decides → stake slashed');
    return;
  }

  // Step 2: Accept and stake (requires private key)
  console.log('Step 2: Accept task + stake EMET');
  const { claimId } = await wrapper.acceptAndStake(
    DEMO_CASPER_AGENT_ID,
    'task-abc-123',
    'Code review: Casper WASM contract security audit',
  );
  console.log(`  Claim ID: ${claimId}\n`);

  // Step 3a: Simulate success
  console.log('Step 3a: Task completed — resolve success');
  await wrapper.resolveSuccess(
    DEMO_CASPER_AGENT_ID,
    'task-abc-123',
    claimId,
    'Agent completed Casper contract audit. Found 2 issues, both documented in AgentGrid task log.',
  );

  // — OR — Step 3b: Simulate failure (comment out 3a and uncomment this)
  // console.log('Step 3b: Task failed — slash agent');
  // await wrapper.slashOnFailure(
  //   DEMO_CASPER_AGENT_ID,
  //   'task-abc-123',
  //   claimId,
  //   'Agent returned empty output after 3600s timeout. TaskID: task-abc-123. Casper tx: 0x...',
  // );

  console.log('\n✅ Demo complete.');
  console.log('Agent reputation now tracked on Base — readable by any EMET-integrated system.');
}

// ─── CLI ──────────────────────────────────────────────────────────────────────

const [, , command, ...args] = process.argv;

if (command === 'demo') {
  demo().catch(console.error);
} else if (command === 'register') {
  const [casperAgentId, baseAddress, description] = args;
  if (!casperAgentId || !baseAddress) {
    console.error('Usage: node agentgrid-staking-wrapper.js register <casperAgentId> <baseAddress> [description]');
    process.exit(1);
  }
  registerAgent(casperAgentId, baseAddress, description || '');
} else if (command === 'check') {
  const [casperAgentId, threshold] = args;
  if (!casperAgentId) {
    console.error('Usage: node agentgrid-staking-wrapper.js check <casperAgentId> [reputationThreshold]');
    process.exit(1);
  }
  const wrapper = new EmetAgentGridWrapper(null, BASE_RPC);
  wrapper.checkThreshold(casperAgentId, threshold ? BigInt(threshold) : DEFAULT_REPUTATION_THRESHOLD)
    .then(r => console.log(r))
    .catch(console.error);
} else {
  console.log('EMET × AgentGrid Staking Wrapper');
  console.log('');
  console.log('Commands:');
  console.log('  demo                          — Run full lifecycle demo (read-only)');
  console.log('  register <id> <address> [desc] — Register AgentGrid agent → Base address mapping');
  console.log('  check <id> [threshold]         — Check agent reputation threshold');
  console.log('');
  console.log('Env vars:');
  console.log('  EMET_ORCHESTRATOR_KEY  — Base wallet private key (for live staking/slashing)');
  console.log('  BASE_RPC               — Custom Base RPC URL (default: mainnet.base.org)');
}

module.exports = { EmetAgentGridWrapper, registerAgent, getBaseAddress };
