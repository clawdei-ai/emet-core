#!/usr/bin/env node

/**
 * EMET Agent Gate — Composite Threshold Guard
 * 
 * Extends the AgentGrid × EMET staking wrapper with a configurable gate function.
 * 
 * Core insight from @JeanClawd99 (Feb 28 2026):
 *   "EMET slash history IS the dispute rate. pulling slash_count + slash_ratio
 *    directly from EMET contract state for composite scoring."
 * 
 * This module implements:
 *   1. getAgentStats()  — reads reputation + slash_count + slash_ratio on-chain
 *   2. agentGate()      — configurable per-task composite threshold check
 *   3. logOutcome()     — post-task hook: auto-resolves success or triggers slash
 * 
 * Design principle: every parameter is task-configurable.
 * A data-retrieval task tolerates higher slash rate than a fund-transfer task.
 * 
 * On-chain interface assumed (EMETReputation extended):
 *   function getAgentStats(address agent) view returns (AgentStats)
 * 
 *   struct AgentStats {
 *     int256  reputation;     // cumulative score (+1 per success, -5 per upheld slash)
 *     uint256 slash_count;    // total upheld challenges against this agent
 *     uint256 task_count;     // total completed tasks (for ratio computation)
 *     uint256 stake_amount;   // current EMET staked by/for this agent
 *     uint256 last_active;    // unix timestamp of most recent claim
 *   }
 * 
 * If the deployed contract doesn't yet expose getAgentStats(), this module
 * reconstructs the stats from individual getters + event scanning (see fallback).
 * 
 * See: https://emet-protocol.com / https://github.com/clawdei-ai/emet-core
 */

const { ethers } = require('ethers');
const { EmetAgentGridWrapper, getBaseAddress } = require('./agentgrid-staking-wrapper');

// ─── Extended ABIs ────────────────────────────────────────────────────────────

// Proposed new getter on EMETReputation (v2 — not yet deployed)
const REPUTATION_STATS_ABI = [
  'function getReputation(address agent) view returns (int256)',
  // Proposed composite getter (draft for @JeanClawd99 co-design):
  'function getAgentStats(address agent) view returns (int256 reputation, uint256 slash_count, uint256 task_count, uint256 stake_amount, uint256 last_active)',
];

// EMETChallengeV3 — for fallback slash_count reconstruction from events
const CHALLENGE_EVENTS_ABI = [
  'event ChallengeSubmitted(uint256 indexed claimId, address indexed challenger, address indexed claimant)',
  'event ChallengeResolved(uint256 indexed claimId, bool challengeUpheld, address indexed claimant)',
  'function submitChallenge(uint256 claimId, string calldata counterEvidence) external',
];

// EMETStake — to read current stake balance per agent
const STAKE_READ_ABI = [
  'function getStake(uint256 claimId, address staker) view returns (uint256)',
  // Proposed: agent-level aggregate (draft for v2 contract)
  'function getTotalStake(address agent) view returns (uint256)',
];

const ADDRESSES = {
  token:      '0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C',
  registry:   '0x7a03057490e8541BF4A0F879659e58Fb13f03Ca9',
  stake:      '0xb4A3Cf08194E445db65862Fb92bbC0cE587345bb',
  reputation: '0x358a775b74f9369D23Ce95EDa57dcbA39A1F4d4e',
  challenge:  '0x12062513c3d41e5D4f0A0f2B079712D758f11EfC',
};

// ─── Default gate configs (per task risk level) ───────────────────────────────

/**
 * GateConfig — tune per task type.
 * All fields optional; omit to skip that check.
 * 
 * @typedef {Object} GateConfig
 * @property {bigint|null}  minReputation   - Minimum reputation score (absolute)
 * @property {number|null}  maxSlashRatio   - Max allowed (slash_count / task_count), e.g. 0.1 = 10%
 * @property {number|null}  maxSlashCount   - Hard ceiling on slash count regardless of ratio
 * @property {bigint|null}  minStake        - Minimum EMET staked (requires stake to be meaningful)
 * @property {number|null}  minTaskCount    - Require proven track record (ignore new agents if set)
 * @property {boolean}      allowNew        - Allow agents with task_count == 0 (unproven but clean)
 * @property {number|null}  maxAgeDays      - Reject agents inactive for N days (stale reputation)
 */

const GATE_PRESETS = {
  // Minimal guard — accept anything clean (new agents OK)
  open: {
    minReputation: 0n,
    maxSlashRatio: null,
    maxSlashCount: null,
    minStake: null,
    minTaskCount: null,
    allowNew: true,
    maxAgeDays: null,
  },

  // Standard — positive rep, max 20% slash rate, min 5 tasks
  standard: {
    minReputation: 5n,
    maxSlashRatio: 0.2,
    maxSlashCount: 3,
    minStake: null,
    minTaskCount: 5,
    allowNew: false,
    maxAgeDays: 90,
  },

  // Strict — for high-value or sensitive tasks (fund transfers, auth decisions)
  strict: {
    minReputation: 25n,
    maxSlashRatio: 0.05,
    maxSlashCount: 1,
    minStake: ethers.parseEther('50'),   // 50 EMET minimum skin in game
    minTaskCount: 20,
    allowNew: false,
    maxAgeDays: 30,
  },

  // Custom — pass any GateConfig object to agentGate()
};

// ─── EmetAgentGate ────────────────────────────────────────────────────────────

class EmetAgentGate {
  constructor(privateKey = null, rpc = 'https://mainnet.base.org') {
    this.provider = new ethers.JsonRpcProvider(rpc);
    this.signer = privateKey ? new ethers.Wallet(privateKey, this.provider) : null;

    // Use extended ABI (graceful fallback if getAgentStats not deployed yet)
    this.reputation = new ethers.Contract(ADDRESSES.reputation, REPUTATION_STATS_ABI, this.provider);
    this.challengeContract = new ethers.Contract(ADDRESSES.challenge, CHALLENGE_EVENTS_ABI, this.provider);
    this.stakeContract = new ethers.Contract(ADDRESSES.stake, STAKE_READ_ABI, this.provider);

    // Compose with the full lifecycle wrapper for stake/slash operations
    this.wrapper = new EmetAgentGridWrapper(privateKey, rpc);
  }

  // ── 1. getAgentStats ──────────────────────────────────────────────────────────
  /**
   * Read composite reputation stats for an agent.
   * 
   * Tries the proposed getAgentStats() getter first.
   * Falls back to reconstructing from events if the contract doesn't have it yet.
   * 
   * @param {string} casperAgentId
   * @returns {Promise<AgentStats>}
   */
  async getAgentStats(casperAgentId) {
    const baseAddress = getBaseAddress(casperAgentId);

    // Try composite getter (v2 contract proposal)
    try {
      const stats = await this.reputation.getAgentStats(baseAddress);
      return {
        baseAddress,
        reputation: stats.reputation,
        slash_count: Number(stats.slash_count),
        task_count:  Number(stats.task_count),
        stake_amount: stats.stake_amount,
        last_active: Number(stats.last_active),
        slash_ratio: stats.task_count > 0n
          ? Number(stats.slash_count) / Number(stats.task_count)
          : 0,
        source: 'on-chain-v2',
      };
    } catch {
      // Fallback: reconstruct from individual getters + event scan
      return this._reconstructStats(baseAddress, casperAgentId);
    }
  }

  /**
   * Fallback: reconstruct slash stats from ChallengeResolved events.
   * Less efficient but works with current deployed contracts.
   * 
   * @param {string} baseAddress
   * @param {string} casperAgentId
   * @private
   */
  async _reconstructStats(baseAddress, casperAgentId) {
    // Reputation from current contract — fully defensive (RPC may be flaky)
    let reputation = 0n;
    try {
      reputation = await this.reputation.getReputation(baseAddress);
    } catch {
      // Fallback: treat as zero rep (safe — new/unknown agent handled by allowNew config)
    }

    // Scan ChallengeResolved events to count upheld slashes for this agent
    // Event: ChallengeResolved(uint256 claimId, bool challengeUpheld, address claimant)
    let slash_count = 0;
    try {
      const filter = this.challengeContract.filters.ChallengeResolved(null, null, baseAddress);
      const events = await this.challengeContract.queryFilter(filter, -500000); // last ~500k blocks
      slash_count = events.filter(e => e.args.challengeUpheld).length;
    } catch {
      // Event scanning may fail on some RPCs — proceed with best-effort stats
    }

    // Estimate task count: reputation = task_count - (slash_count * 6)
    // (Each success: +1, each upheld slash: -5, net per slash = 6)
    // task_count ≈ reputation + slash_count * 6
    const task_count = Math.max(0, Number(reputation) + slash_count * 6);
    const slash_ratio = task_count > 0 ? slash_count / task_count : 0;

    return {
      baseAddress,
      reputation,
      slash_count,
      task_count,
      stake_amount: 0n, // Can't aggregate per-agent without v2 getter
      last_active: 0,   // Not available without v2 getter
      slash_ratio,
      source: 'reconstructed-from-events',
    };
  }

  // ── 2. agentGate ─────────────────────────────────────────────────────────────
  /**
   * Composite gate function. Evaluate agent against task-specific config.
   * 
   * Design: configurable per-task. A data lookup task uses 'open'.
   * A fund transfer uses 'strict'. Custom configs allowed.
   * 
   * @param {string} casperAgentId
   * @param {GateConfig|'open'|'standard'|'strict'} config - preset name or custom config
   * @returns {Promise<GateResult>}
   * 
   * @example
   * // Standard gate check
   * const result = await gate.agentGate('ag-casper-0xabc', 'standard');
   * if (!result.allowed) throw new Error(result.reason);
   * 
   * // Custom gate for high-value task
   * const result = await gate.agentGate('ag-casper-0xabc', {
   *   minReputation: 50n,
   *   maxSlashRatio: 0.05,
   *   maxSlashCount: 1,
   *   minStake: ethers.parseEther('100'),
   *   allowNew: false,
   * });
   */
  async agentGate(casperAgentId, config = 'standard') {
    // Resolve preset or use custom config
    const cfg = typeof config === 'string'
      ? GATE_PRESETS[config] ?? GATE_PRESETS.standard
      : { ...GATE_PRESETS.open, ...config }; // merge with defaults

    const stats = await this.getAgentStats(casperAgentId);
    const failures = [];

    // ── Check: new/unproven agent ───────────────────────────────────────────
    if (stats.task_count === 0) {
      if (!cfg.allowNew) {
        failures.push(`unproven: task_count=0 (allowNew=false for this task type)`);
      }
      // New agents pass all ratio/count checks (no history to judge)
      return this._gateResult(stats, failures, cfg, 'new-agent');
    }

    // ── Check: minimum reputation ───────────────────────────────────────────
    if (cfg.minReputation !== null && stats.reputation < cfg.minReputation) {
      failures.push(
        `reputation ${stats.reputation} < required ${cfg.minReputation}`
      );
    }

    // ── Check: slash ratio ──────────────────────────────────────────────────
    if (cfg.maxSlashRatio !== null && stats.slash_ratio > cfg.maxSlashRatio) {
      failures.push(
        `slash_ratio ${(stats.slash_ratio * 100).toFixed(1)}% > max ${(cfg.maxSlashRatio * 100).toFixed(1)}%`
        + ` (${stats.slash_count} slashes / ${stats.task_count} tasks)`
      );
    }

    // ── Check: absolute slash count ─────────────────────────────────────────
    if (cfg.maxSlashCount !== null && stats.slash_count > cfg.maxSlashCount) {
      failures.push(
        `slash_count ${stats.slash_count} > hard limit ${cfg.maxSlashCount}`
      );
    }

    // ── Check: minimum stake ────────────────────────────────────────────────
    if (cfg.minStake !== null && stats.stake_amount < cfg.minStake) {
      failures.push(
        `stake ${ethers.formatEther(stats.stake_amount)} EMET < required ${ethers.formatEther(cfg.minStake)} EMET`
      );
    }

    // ── Check: minimum task track record ───────────────────────────────────
    if (cfg.minTaskCount !== null && stats.task_count < cfg.minTaskCount) {
      failures.push(
        `task_count ${stats.task_count} < required ${cfg.minTaskCount}`
      );
    }

    // ── Check: activity recency ─────────────────────────────────────────────
    if (cfg.maxAgeDays !== null && stats.last_active > 0) {
      const ageDays = (Date.now() / 1000 - stats.last_active) / 86400;
      if (ageDays > cfg.maxAgeDays) {
        failures.push(
          `inactive: last active ${ageDays.toFixed(0)} days ago (max ${cfg.maxAgeDays} days)`
        );
      }
    }

    return this._gateResult(stats, failures, cfg);
  }

  _gateResult(stats, failures, cfg, tag = '') {
    const allowed = failures.length === 0;
    return {
      allowed,
      stats,
      reason: allowed
        ? `✅ PASS${tag ? ` (${tag})` : ''} — rep:${stats.reputation} slash:${stats.slash_count}/${stats.task_count} (${(stats.slash_ratio * 100).toFixed(1)}%)`
        : `❌ BLOCKED — ${failures.join('; ')}`,
      failures,
      config: cfg,
    };
  }

  // ── 3. logOutcome ─────────────────────────────────────────────────────────────
  /**
   * Post-task lifecycle hook. Call this when AgentGrid reports task outcome.
   * Automatically routes to resolveSuccess() or slashOnFailure().
   * 
   * This is the "logOutcome() triggers slash evaluation" pattern proposed for 
   * per-task configuration — the gate sets up the rules, logOutcome enforces them.
   * 
   * @param {Object} outcome
   * @param {string}  outcome.casperAgentId
   * @param {string}  outcome.taskId
   * @param {number}  outcome.claimId      - from acceptAndStake()
   * @param {boolean} outcome.success      - AgentGrid's verdict
   * @param {string}  outcome.summary      - result summary or failure reason
   * @param {Object}  outcome.taskMeta     - optional: task config, timestamps, etc.
   * @returns {Promise<OutcomeResult>}
   * 
   * @example
   * await gate.logOutcome({
   *   casperAgentId: 'ag-casper-0xabc',
   *   taskId: 'task-42',
   *   claimId: 7n,
   *   success: true,
   *   summary: 'Contract audit completed. 2 issues found and documented.',
   * });
   */
  async logOutcome({ casperAgentId, taskId, claimId, success, summary, taskMeta = {} }) {
    const timestamp = new Date().toISOString();
    const unixTimestamp = Math.floor(Date.now() / 1000);

    if (success) {
      console.log(`📋 [logOutcome] Task ${taskId} SUCCESS — submitting positive claim...`);
      const result = await this.wrapper.resolveSuccess(
        casperAgentId,
        taskId,
        claimId,
        summary || `AgentGrid task ${taskId} completed successfully`,
      );

      // Emit OutcomeLogged event (mirrors on-chain event for indexers)
      // On-chain: event OutcomeLogged(address indexed agent, bytes32 indexed taskId, bool passed, uint256 slashAmount, uint256 timestamp)
      const outcomeEvent = {
        event: 'OutcomeLogged',
        agent: result?.baseAddress || casperAgentId,
        taskId,
        passed: true,
        slashAmount: 0n,
        timestamp: unixTimestamp,
      };
      console.log(`📡 [OutcomeLogged] ${JSON.stringify(outcomeEvent)}`);

      console.log(`✅ [logOutcome] Outcome logged. Agent rep increases on Base.`);
      return {
        action: 'success',
        claimId,
        taskId,
        casperAgentId,
        timestamp,
        outcomeEvent,
        ...result,
      };
    } else {
      console.log(`⚔️  [logOutcome] Task ${taskId} FAILED — submitting slash challenge...`);
      const failureReason = summary || `Task ${taskId} failed without explanation`;
      const challengeEvidence = JSON.stringify({
        type: 'agentgrid_task_failure',
        casperAgentId,
        taskId,
        parentClaimId: claimId,
        failureReason,
        failedAt: timestamp,
        taskMeta,
      });
      const result = await this.wrapper.slashOnFailure(
        casperAgentId,
        taskId,
        claimId,
        challengeEvidence,
      );

      // Emit OutcomeLogged event for indexers.
      // slashAmount reflects the stake forfeited on a successful slash challenge.
      // In this off-chain layer, use result.slashAmount if populated; downstream
      // the on-chain EMETReputation.logOutcome() will emit the authoritative value.
      const slashAmount = BigInt(result?.slashAmount ?? 0);
      const outcomeEvent = {
        event: 'OutcomeLogged',
        agent: result?.baseAddress || casperAgentId,
        taskId,
        passed: false,
        slashAmount,
        timestamp: unixTimestamp,
      };
      console.log(`📡 [OutcomeLogged] ${JSON.stringify(outcomeEvent, (_, v) => typeof v === 'bigint' ? v.toString() : v)}`);

      console.log(`🔥 [logOutcome] Challenge submitted. EMET jury will resolve.`);
      return {
        action: 'slash_challenge',
        claimId,
        taskId,
        casperAgentId,
        timestamp,
        outcomeEvent,
        ...result,
      };
    }
  }

  // ── Helper: full gate + stake flow ───────────────────────────────────────────
  /**
   * Convenience: gate check + stake in one call.
   * Throws if agent fails gate. Stakes if accepted.
   * 
   * Returns { gateResult, claimId, txHash } on success.
   * Throws GateError on rejection.
   * 
   * @param {string} casperAgentId
   * @param {string} taskId
   * @param {string} taskDescription
   * @param {GateConfig|'open'|'standard'|'strict'} gateConfig
   */
  async gateAndStake(casperAgentId, taskId, taskDescription, gateConfig = 'standard') {
    const gateResult = await this.agentGate(casperAgentId, gateConfig);

    if (!gateResult.allowed) {
      const err = new Error(`[EMET Gate] Agent ${casperAgentId} blocked for task ${taskId}: ${gateResult.reason}`);
      err.code = 'EMET_GATE_BLOCKED';
      err.gateResult = gateResult;
      throw err;
    }

    console.log(gateResult.reason);

    if (!this.signer) {
      console.log('ℹ️  Read-only mode — gate check passed, staking skipped (no private key).');
      return { gateResult, claimId: null, txHash: null };
    }

    const { claimId, txHash } = await this.wrapper.acceptAndStake(
      casperAgentId,
      taskId,
      taskDescription,
    );

    return { gateResult, claimId, txHash };
  }
}

// ─── Demo ─────────────────────────────────────────────────────────────────────

async function demo() {
  console.log('🔷 EMET Agent Gate — Composite Threshold Demo\n');
  console.log('This implements the gate function co-designed with @JeanClawd99:\n');
  console.log('  1. getAgentStats() — pulls reputation + slash_count + slash_ratio on-chain');
  console.log('  2. agentGate()     — per-task configurable threshold check');
  console.log('  3. logOutcome()    — post-task hook: auto-resolves or triggers slash\n');

  const gate = new EmetAgentGate(process.env.EMET_ORCHESTRATOR_KEY || null);

  // Demo agent — Clawdei's EMET address (has live on-chain reputation)
  const DEMO_CASPER_AGENT_ID = 'ag-casper-0xf3a9';

  // ── getAgentStats ────────────────────────────────────────────────────────────
  console.log('─── Step 1: getAgentStats ───────────────────────────────────────────\n');
  try {
    const stats = await gate.getAgentStats(DEMO_CASPER_AGENT_ID);
    console.log('Agent stats (on-chain):');
    console.log(`  reputation:   ${stats.reputation}`);
    console.log(`  slash_count:  ${stats.slash_count}`);
    console.log(`  task_count:   ${stats.task_count}`);
    console.log(`  slash_ratio:  ${(stats.slash_ratio * 100).toFixed(1)}%`);
    console.log(`  stake_amount: ${ethers.formatEther(stats.stake_amount || 0n)} EMET`);
    console.log(`  source:       ${stats.source}`);
    console.log(`  base_address: ${stats.baseAddress}\n`);
  } catch (err) {
    console.log(`⚠️  getAgentStats: ${err.message}\n`);
  }

  // ── agentGate — open preset ──────────────────────────────────────────────────
  console.log('─── Step 2a: agentGate (open preset) ───────────────────────────────\n');
  try {
    const result = await gate.agentGate(DEMO_CASPER_AGENT_ID, 'open');
    console.log(result.reason);
    console.log(`  allowed: ${result.allowed}\n`);
  } catch (err) {
    console.log(`Error: ${err.message}\n`);
  }

  // ── agentGate — standard preset ──────────────────────────────────────────────
  console.log('─── Step 2b: agentGate (standard preset) ───────────────────────────\n');
  try {
    const result = await gate.agentGate(DEMO_CASPER_AGENT_ID, 'standard');
    console.log(result.reason);
    if (!result.allowed) {
      result.failures.forEach(f => console.log(`  ✗ ${f}`));
    }
    console.log();
  } catch (err) {
    console.log(`Error: ${err.message}\n`);
  }

  // ── agentGate — custom config ────────────────────────────────────────────────
  console.log('─── Step 2c: agentGate (custom — fund transfer profile) ────────────\n');
  try {
    const result = await gate.agentGate(DEMO_CASPER_AGENT_ID, {
      minReputation: 50n,
      maxSlashRatio: 0.03,      // max 3% slash rate
      maxSlashCount: 1,
      minStake: ethers.parseEther('50'),
      minTaskCount: 20,
      allowNew: false,
      maxAgeDays: 30,
    });
    console.log(result.reason);
    if (!result.allowed) {
      result.failures.forEach(f => console.log(`  ✗ ${f}`));
    }
    console.log();
  } catch (err) {
    console.log(`Error: ${err.message}\n`);
  }

  // ── gateAndStake (read-only) ─────────────────────────────────────────────────
  console.log('─── Step 3: gateAndStake (combined, read-only) ─────────────────────\n');
  try {
    const { gateResult } = await gate.gateAndStake(
      DEMO_CASPER_AGENT_ID,
      'demo-task-001',
      'Demo: data retrieval task — low risk',
      'open',
    );
    console.log(`Gate: ${gateResult.allowed ? 'PASS' : 'BLOCKED'}`);
  } catch (err) {
    if (err.code === 'EMET_GATE_BLOCKED') {
      console.log(`Blocked: ${err.gateResult.reason}`);
    } else {
      console.log(`Error: ${err.message}`);
    }
  }

  console.log('\n─── Preset summary ──────────────────────────────────────────────────\n');
  console.log('Available gate presets:');
  for (const [name, cfg] of Object.entries(GATE_PRESETS)) {
    const parts = [];
    if (cfg.minReputation !== null) parts.push(`rep≥${cfg.minReputation}`);
    if (cfg.maxSlashRatio !== null) parts.push(`slash_ratio≤${(cfg.maxSlashRatio * 100).toFixed(0)}%`);
    if (cfg.maxSlashCount !== null) parts.push(`slashes≤${cfg.maxSlashCount}`);
    if (cfg.minTaskCount  !== null) parts.push(`tasks≥${cfg.minTaskCount}`);
    if (cfg.allowNew) parts.push('new_OK');
    console.log(`  ${name.padEnd(10)} — ${parts.join(', ') || 'no constraints'}`);
  }

  console.log('\n✅ Demo complete.');
  console.log('');
  console.log('Co-designed with @JeanClawd99 (AgentGrid/Casper) — Feb 28 2026');
  console.log('See agentgrid-emet-spec.md for full integration spec.');
}

// ─── CLI ──────────────────────────────────────────────────────────────────────

const [, , command, ...args] = process.argv;

if (command === 'demo' || !command) {
  demo().catch(console.error);
} else if (command === 'stats') {
  const [casperAgentId] = args;
  if (!casperAgentId) {
    console.error('Usage: node emet-agent-gate.js stats <casperAgentId>');
    process.exit(1);
  }
  const gate = new EmetAgentGate();
  gate.getAgentStats(casperAgentId).then(s => {
    console.log(JSON.stringify(s, (_, v) => typeof v === 'bigint' ? v.toString() : v, 2));
  }).catch(console.error);
} else if (command === 'check') {
  const [casperAgentId, preset] = args;
  if (!casperAgentId) {
    console.error('Usage: node emet-agent-gate.js check <casperAgentId> [open|standard|strict]');
    process.exit(1);
  }
  const gate = new EmetAgentGate();
  gate.agentGate(casperAgentId, preset || 'standard').then(r => {
    console.log(r.reason);
    if (!r.allowed) r.failures.forEach(f => console.log(`  ✗ ${f}`));
    process.exit(r.allowed ? 0 : 1);
  }).catch(console.error);
} else {
  console.log('EMET Agent Gate — Composite Threshold Guard');
  console.log('');
  console.log('Commands:');
  console.log('  demo                      — Run full demo (presets + custom config)');
  console.log('  stats <casperAgentId>     — Print on-chain stats for agent');
  console.log('  check <casperAgentId> [preset] — Gate check (open|standard|strict)');
  console.log('');
  console.log('Presets:');
  console.log('  open     — no constraints, new agents OK');
  console.log('  standard — rep≥5, slash_ratio≤20%, slashes≤3, tasks≥5');
  console.log('  strict   — rep≥25, slash_ratio≤5%, slashes≤1, stake≥50 EMET, tasks≥20');
  console.log('');
  console.log('Env vars:');
  console.log('  EMET_ORCHESTRATOR_KEY — Base wallet key (for live staking/slashing)');
  console.log('  BASE_RPC              — Custom Base RPC (default: mainnet.base.org)');
}

module.exports = { EmetAgentGate, GATE_PRESETS };
