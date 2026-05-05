#!/usr/bin/env node
/*
 * Agent Marketplace Routing Playbook
 *
 * Offline example: route agents into tasks using identity, task risk,
 * EMET-style outcome evidence, and durable routing receipts.
 */

const agents = [
  {
    id: 'agent:researcher-alpha',
    principal: '0xA11CE',
    scopes: ['research', 'support'],
    revoked: false,
    emet: { score: 78, resolvedClaims: 24, openChallenges: 0, stake: 500 },
  },
  {
    id: 'agent:ops-beta',
    principal: '0xB0B',
    scopes: ['research', 'support', 'api_write'],
    revoked: false,
    emet: { score: 91, resolvedClaims: 87, openChallenges: 1, stake: 2_500 },
  },
  {
    id: 'agent:coldstart-gamma',
    principal: '0xC01D',
    scopes: ['research'],
    revoked: false,
    emet: { score: null, resolvedClaims: 0, openChallenges: 0, stake: 25 },
  },
  {
    id: 'agent:disputed-delta',
    principal: '0xD15',
    scopes: ['research', 'support', 'api_write', 'payments'],
    revoked: false,
    emet: { score: 74, resolvedClaims: 52, openChallenges: 4, stake: 1_200 },
  },
];

const tasks = [
  { id: 'task_001', domain: 'research', riskTier: 'sandbox', requiredScope: 'research' },
  { id: 'task_002', domain: 'support', riskTier: 'customer_facing', requiredScope: 'support' },
  { id: 'task_003', domain: 'billing-api', riskTier: 'privileged', requiredScope: 'api_write' },
  { id: 'task_004', domain: 'refund', riskTier: 'financial', requiredScope: 'payments', capUsd: 100 },
];

const policies = {
  sandbox: { name: 'LENIENT', minScore: 0, minResolvedClaims: 0, maxOpenChallenges: 5, minStake: 0 },
  internal: { name: 'LENIENT', minScore: 55, minResolvedClaims: 3, maxOpenChallenges: 3, minStake: 50 },
  customer_facing: { name: 'STANDARD', minScore: 70, minResolvedClaims: 10, maxOpenChallenges: 1, minStake: 250 },
  privileged: { name: 'STRICT', minScore: 85, minResolvedClaims: 25, maxOpenChallenges: 1, minStake: 1_000 },
  financial: { name: 'CUSTOM_FINANCIAL', minScore: 90, minResolvedClaims: 50, maxOpenChallenges: 0, minStake: 2_000 },
};

function resolveIdentity(agent) {
  if (agent.revoked) return { ok: false, reason: 'identity revoked' };
  return { ok: true, registry: 'example-marketplace', agentId: agent.id, principal: agent.principal, scopes: agent.scopes };
}

function evaluateEmet(agent, policy) {
  const score = agent.emet.score ?? 0;
  const failures = [];

  if (score < policy.minScore) failures.push(`score ${score} < ${policy.minScore}`);
  if (agent.emet.resolvedClaims < policy.minResolvedClaims) {
    failures.push(`resolved claims ${agent.emet.resolvedClaims} < ${policy.minResolvedClaims}`);
  }
  if (agent.emet.openChallenges > policy.maxOpenChallenges) {
    failures.push(`open challenges ${agent.emet.openChallenges} > ${policy.maxOpenChallenges}`);
  }
  if (agent.emet.stake < policy.minStake) failures.push(`stake ${agent.emet.stake} < ${policy.minStake}`);

  return { ...agent.emet, passes: failures.length === 0, failures };
}

function decide(identity, task, policy, emetSnapshot) {
  if (!identity.ok) return { action: 'block', reason: identity.reason };
  if (!identity.scopes.includes(task.requiredScope)) {
    return { action: 'block', reason: `missing scope: ${task.requiredScope}` };
  }
  if (task.riskTier === 'sandbox' && emetSnapshot.resolvedClaims === 0) {
    return { action: 'human_review', reason: 'cold-start agent may work only behind review' };
  }
  if (emetSnapshot.passes && task.riskTier === 'financial') {
    return { action: 'allow_with_cap', reason: `financial policy passed with $${task.capUsd} cap` };
  }
  if (emetSnapshot.passes) return { action: 'allow', reason: `${policy.name} policy passed` };
  if (task.riskTier === 'customer_facing' || task.riskTier === 'privileged') {
    return { action: 'challenge_first', reason: emetSnapshot.failures.join('; ') };
  }
  return { action: 'block', reason: emetSnapshot.failures.join('; ') };
}

function makeReceipt(agent, task) {
  const identity = resolveIdentity(agent);
  const policy = policies[task.riskTier];
  const emetSnapshot = evaluateEmet(agent, policy);
  const decision = decide(identity, task, policy, emetSnapshot);

  return {
    receiptId: `route_${task.id}_${agent.id.split(':').pop()}`,
    agentId: agent.id,
    identity,
    task,
    policy,
    emetSnapshot,
    decision,
    outcome: null,
  };
}

function pickBestRoute(task) {
  const receipts = agents.map((agent) => makeReceipt(agent, task));
  const allowed = receipts.filter((receipt) => ['allow', 'allow_with_cap'].includes(receipt.decision.action));
  const reviewable = receipts.filter((receipt) => ['human_review', 'challenge_first'].includes(receipt.decision.action));

  const ranked = [...allowed].sort((a, b) => b.emetSnapshot.score - a.emetSnapshot.score);
  return { task, selected: ranked[0] ?? reviewable[0] ?? null, receipts };
}

function attachOutcome(receipt, status, evidenceRef) {
  return {
    ...receipt,
    outcome: {
      status,
      evidenceRef,
      recordedAt: new Date('2026-05-05T14:00:00.000Z').toISOString(),
      feedback: status === 'success' ? 'eligible for future same-tier routing' : 'downgrade pending review',
    },
  };
}

for (const task of tasks) {
  const route = pickBestRoute(task);

  if (!route.selected) {
    console.log(`\n${task.id} (${task.riskTier}) -> no assignment`);
    console.log('decision: block — no candidate satisfied the policy or review path');
    continue;
  }

  const selected = attachOutcome(route.selected, 'success', `evidence://${task.id}`);
  console.log(`\n${task.id} (${task.riskTier}) -> ${selected.agentId}`);
  console.log(`decision: ${selected.decision.action} — ${selected.decision.reason}`);
  console.log(`receipt: ${selected.receiptId}`);
}

console.log('\nTip: persist every receipt, including blocks and review decisions, then append outcome feedback when the task resolves.');
