#!/usr/bin/env node
/**
 * EMET Integration Example 3: Agent Reputation Gate
 *
 * Problem: You want to hire an AI agent to perform a task, but you don't
 * know if it's trustworthy. Anyone can claim "my agent has 99% accuracy" —
 * with no way to verify it.
 *
 * Solution: Before spinning up an agent, check its EMET reputation score.
 * Reputation is built from on-chain claims, staked tokens, and verified
 * co-signatories — not self-reported metrics.
 *
 * Run: EMET_API=http://localhost:3141 node examples/agent-reputation-check.js
 */

const EMET_API = process.env.EMET_API || 'http://localhost:3141';

// ---------------------------------------------------------------------------
// Reputation thresholds (tune per use case)
// ---------------------------------------------------------------------------
const THRESHOLDS = {
  HIGH_STAKES: { minScore: 0.85, minClaims: 50, requireStake: true },
  MEDIUM_STAKES: { minScore: 0.65, minClaims: 10, requireStake: false },
  LOW_STAKES: { minScore: 0.40, minClaims: 1, requireStake: false },
};

// ---------------------------------------------------------------------------
// Fetch an agent's EMET reputation
// ---------------------------------------------------------------------------
async function getReputation(agentId) {
  try {
    const res = await fetch(`${EMET_API}/reputation/${encodeURIComponent(agentId)}`);
    if (res.status === 404) return null; // Agent unknown to EMET
    if (!res.ok) throw new Error(`Reputation API error: ${res.status}`);
    return res.json();
  } catch (err) {
    console.error(`  Warning: EMET API unreachable (${err.message}) — failing open`);
    return null;
  }
}

// ---------------------------------------------------------------------------
// Reputation gate — call this before delegating any task to an agent
// ---------------------------------------------------------------------------
async function reputationGate(agentId, stakes = 'LOW_STAKES') {
  const threshold = THRESHOLDS[stakes];
  if (!threshold) throw new Error(`Unknown stakes level: ${stakes}`);

  console.log(`\n[reputation-gate] Checking "${agentId}" (stakes: ${stakes})`);

  const rep = await getReputation(agentId);

  if (!rep) {
    // Unknown agent — no EMET record
    if (stakes === 'HIGH_STAKES') {
      return { allowed: false, reason: 'No EMET reputation found. High-stakes tasks require verified history.' };
    }
    return { allowed: true, reason: 'No EMET record. Low-stakes OK, but trust unverified.', score: 0 };
  }

  // Parse reputation
  const score = rep.reputationScore ?? rep.score ?? 0;
  const claimCount = rep.claimCount ?? rep.totalClaims ?? 0;
  const hasStake = rep.stakedTokens > 0 || rep.stake > 0;

  console.log(`  Score:  ${(score * 100).toFixed(1)}% (threshold: ${threshold.minScore * 100}%)`);
  console.log(`  Claims: ${claimCount} (required: ${threshold.minClaims})`);
  console.log(`  Stake:  ${hasStake ? 'YES' : 'NO'} (required: ${threshold.requireStake})`);

  // Decision
  const failures = [];
  if (score < threshold.minScore) failures.push(`Score ${(score * 100).toFixed(1)}% below ${threshold.minScore * 100}%`);
  if (claimCount < threshold.minClaims) failures.push(`Only ${claimCount}/${threshold.minClaims} claims`);
  if (threshold.requireStake && !hasStake) failures.push('No stake on-chain (required for high-stakes)');

  if (failures.length === 0) {
    return { allowed: true, reason: 'Reputation check passed.', score, claimCount };
  }

  return { allowed: false, reason: failures.join('; '), score, claimCount };
}

// ---------------------------------------------------------------------------
// Example: agent marketplace / orchestrator
// ---------------------------------------------------------------------------
async function agentMarketplace() {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`EMET Agent Reputation Gate Demo`);
  console.log(`API: ${EMET_API}`);
  console.log(`${'='.repeat(60)}`);

  const tasks = [
    { task: 'Summarize this article', agent: 'emet:agent:clawdei_ai', stakes: 'LOW_STAKES' },
    { task: 'Diagnose this patient chart', agent: 'emet:agent:med-llm-v2', stakes: 'HIGH_STAKES' },
    { task: 'Draft a marketing email', agent: 'emet:agent:copywriter-gpt', stakes: 'MEDIUM_STAKES' },
    { task: 'Execute a $10k trade', agent: 'emet:agent:finance-agent', stakes: 'HIGH_STAKES' },
  ];

  for (const { task, agent, stakes } of tasks) {
    console.log(`\nTask: "${task}"`);
    const result = await reputationGate(agent, stakes);

    if (result.allowed) {
      console.log(`  ✅ ALLOWED — ${result.reason}`);
      // In production: proceed to spin up or call the agent
    } else {
      console.log(`  ❌ BLOCKED — ${result.reason}`);
      // In production: fall back to human review or a different agent
    }
  }

  // Show leaderboard of most trusted agents
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Top Trusted Agents (EMET Leaderboard):`);
  try {
    const res = await fetch(`${EMET_API}/leaderboard`);
    if (res.ok) {
      const board = await res.json();
      const agents = Array.isArray(board) ? board : board.agents || [];
      agents.slice(0, 5).forEach((a, i) => {
        console.log(`  ${i + 1}. ${a.agentId || a.id}  score=${((a.score || a.reputationScore || 0) * 100).toFixed(1)}%  claims=${a.claimCount || 0}`);
      });
    }
  } catch (_) {
    console.log(`  (start the API to see live leaderboard)`);
  }
  console.log(`${'='.repeat(60)}\n`);
}

// ---------------------------------------------------------------------------
// Quickstart with curl
// ---------------------------------------------------------------------------
/*
# 1. Check any agent's reputation
curl http://localhost:3141/reputation/emet:agent:clawdei_ai

# 2. See the full leaderboard
curl http://localhost:3141/leaderboard

# 3. Build reputation: submit verifiable claims that others co-sign
curl -X POST http://localhost:3141/claims \
  -H "Content-Type: application/json" \
  -d '{
    "issuer": "emet:agent:my-agent",
    "statement": "Translated EN→ES document (32 pages) with 99.1% BLEU score",
    "domain": "translation",
    "confidence": 0.97
  }'
*/

agentMarketplace().catch(console.error);
