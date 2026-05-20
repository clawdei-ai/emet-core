#!/usr/bin/env node
/*
 * AgentVouch x EMET offline router
 *
 * Converts AgentVouch-style on-chain reputation evidence into task-specific
 * EMET routing decisions and receipts. This is a mock fixture/pilot harness;
 * it does not require AgentVouch API access and does not claim integration.
 */

const agentVouchProfiles = [
  {
    id: 'agentvouch:solana:9xResearchAlpha',
    principal: 'solana:operator_alpha',
    revoked: false,
    scopes: ['research', 'customer_support'],
    stake: 1_250,
    attestations: 18,
    resolvedOutcomes: 42,
    openChallenges: 0,
    domainHistory: { research: { successRate: 0.96 }, customer_support: { successRate: 0.91 } },
  },
  {
    id: 'agentvouch:solana:7kOpsBeta',
    principal: 'solana:operator_beta',
    revoked: false,
    scopes: ['research', 'api_write', 'customer_support'],
    stake: 3_500,
    attestations: 31,
    resolvedOutcomes: 88,
    openChallenges: 1,
    domainHistory: { api_write: { successRate: 0.94 }, customer_support: { successRate: 0.89 } },
  },
  {
    id: 'agentvouch:solana:2cColdStartGamma',
    principal: 'solana:operator_gamma',
    revoked: false,
    scopes: ['research'],
    stake: 75,
    attestations: 2,
    resolvedOutcomes: 0,
    openChallenges: 0,
    domainHistory: {},
  },
  {
    id: 'agentvouch:solana:5dDisputedDelta',
    principal: 'solana:operator_delta',
    revoked: false,
    scopes: ['research', 'customer_support', 'payments'],
    stake: 2_100,
    attestations: 22,
    resolvedOutcomes: 57,
    openChallenges: 3,
    domainHistory: { payments: { successRate: 0.81 }, customer_support: { successRate: 0.83 } },
  },
  {
    id: 'agentvouch:solana:1rRevokedEpsilon',
    principal: 'solana:operator_epsilon',
    revoked: true,
    scopes: ['research', 'api_write'],
    stake: 4_000,
    attestations: 44,
    resolvedOutcomes: 120,
    openChallenges: 0,
    domainHistory: { api_write: { successRate: 0.97 } },
  },
];

const tasks = [
  { id: 'task-research-001', domain: 'research', riskTier: 'sandbox', requiredScope: 'research' },
  { id: 'task-support-002', domain: 'customer_support', riskTier: 'customer_facing', requiredScope: 'customer_support' },
  { id: 'task-api-003', domain: 'api_write', riskTier: 'privileged', requiredScope: 'api_write' },
  { id: 'task-refund-004', domain: 'payments', riskTier: 'financial', requiredScope: 'payments', capUsd: 100 },
];

const policies = {
  sandbox: { name: 'EMET_AGENTVOUCH_SANDBOX', minResolvedOutcomes: 0, minStake: 0, maxOpenChallenges: 5, minDomainSuccessRate: 0 },
  customer_facing: { name: 'EMET_AGENTVOUCH_CUSTOMER_FACING', minResolvedOutcomes: 10, minStake: 250, maxOpenChallenges: 1, minDomainSuccessRate: 0.85 },
  privileged: { name: 'EMET_AGENTVOUCH_PRIVILEGED', minResolvedOutcomes: 50, minStake: 2_000, maxOpenChallenges: 1, minDomainSuccessRate: 0.9 },
  financial: { name: 'EMET_AGENTVOUCH_FINANCIAL_CAPPED', minResolvedOutcomes: 75, minStake: 5_000, maxOpenChallenges: 0, minDomainSuccessRate: 0.95 },
};

function evidenceSnapshot(profile, task) {
  return {
    registry: 'agentvouch',
    chain: 'solana',
    agentId: profile.id,
    principal: profile.principal,
    revoked: profile.revoked,
    scopes: profile.scopes,
    stake: profile.stake,
    attestations: profile.attestations,
    resolvedOutcomes: profile.resolvedOutcomes,
    openChallenges: profile.openChallenges,
    domainSuccessRate: profile.domainHistory[task.domain]?.successRate ?? 0,
  };
}

function evaluate(snapshot, task) {
  const policy = policies[task.riskTier];
  const failures = [];

  if (snapshot.revoked) failures.push('identity revoked');
  if (!snapshot.scopes.includes(task.requiredScope)) failures.push(`missing scope: ${task.requiredScope}`);
  if (snapshot.resolvedOutcomes < policy.minResolvedOutcomes) failures.push(`resolved outcomes ${snapshot.resolvedOutcomes} < ${policy.minResolvedOutcomes}`);
  if (snapshot.stake < policy.minStake) failures.push(`stake ${snapshot.stake} < ${policy.minStake}`);
  if (snapshot.openChallenges > policy.maxOpenChallenges) failures.push(`open challenges ${snapshot.openChallenges} > ${policy.maxOpenChallenges}`);
  if (snapshot.domainSuccessRate < policy.minDomainSuccessRate) failures.push(`domain success ${snapshot.domainSuccessRate} < ${policy.minDomainSuccessRate}`);

  return { policy, failures };
}

function decide(task, snapshot, failures) {
  if (snapshot.revoked) return { action: 'block', reason: 'identity revoked' };
  if (!snapshot.scopes.includes(task.requiredScope)) return { action: 'block', reason: `missing scope: ${task.requiredScope}` };
  if (failures.length === 0 && task.riskTier === 'financial') return { action: 'allow_with_cap', reason: `financial policy passed with $${task.capUsd} cap` };
  if (failures.length === 0) return { action: 'allow', reason: 'policy passed' };
  if (task.riskTier === 'sandbox') return { action: 'human_review', reason: failures.join('; ') };
  if (task.riskTier === 'customer_facing' || task.riskTier === 'privileged') return { action: 'challenge_first', reason: failures.join('; ') };
  return { action: 'block', reason: failures.join('; ') };
}

function makeReceipt(profile, task) {
  const snapshot = evidenceSnapshot(profile, task);
  const { policy, failures } = evaluate(snapshot, task);
  const decision = decide(task, snapshot, failures);

  return {
    receiptId: `route_agentvouch_${task.id}_${profile.id.split(':').pop()}`,
    agentId: profile.id,
    task,
    policy: { ...policy, version: '2026-05-12' },
    evidenceSnapshot: snapshot,
    decision,
    outcome: null,
  };
}

function score(receipt) {
  const e = receipt.evidenceSnapshot;
  return e.domainSuccessRate * 100 + e.resolvedOutcomes / 10 + e.stake / 1000 - e.openChallenges * 10;
}

function routeTask(task) {
  const receipts = agentVouchProfiles.map((profile) => makeReceipt(profile, task));
  const allowed = receipts.filter((receipt) => ['allow', 'allow_with_cap'].includes(receipt.decision.action));
  const reviewable = receipts.filter((receipt) => ['human_review', 'challenge_first'].includes(receipt.decision.action));
  const selected = [...allowed].sort((a, b) => score(b) - score(a))[0] ?? reviewable[0] ?? null;
  return { task, selected, receipts };
}

function runDemo() {
  for (const task of tasks) {
    const { selected, receipts } = routeTask(task);
    console.log(`\n${task.id} (${task.riskTier})`);
    if (!selected) {
      console.log('selected: none');
      continue;
    }
    console.log(`selected: ${selected.agentId}`);
    console.log(`decision: ${selected.decision.action} — ${selected.decision.reason}`);
    console.log(`receipt: ${selected.receiptId}`);
    console.log(`all decisions: ${receipts.map((r) => `${r.agentId.split(':').pop()}=${r.decision.action}`).join(', ')}`);
  }

  console.log('\nPilot rule: persist all receipts, including blocks and challenge_first decisions, then append outcomes after task resolution.');
}

if (require.main === module) {
  runDemo();
}

module.exports = {
  agentVouchProfiles,
  tasks,
  policies,
  evidenceSnapshot,
  evaluate,
  decide,
  makeReceipt,
  routeTask,
  score,
  runDemo,
};
