#!/usr/bin/env node
/*
 * Invariant checks for the AgentVouch x EMET offline router.
 * These keep the example honest: no silent production authority for revoked,
 * out-of-scope, disputed, or under-evidenced agents.
 */

const assert = require('node:assert/strict');
const {
  agentVouchProfiles,
  tasks,
  makeReceipt,
  routeTask,
} = require('./agentvouch-emet-router');

const actions = new Set(['allow', 'allow_with_cap', 'human_review', 'challenge_first', 'block']);

function byId(id) {
  return agentVouchProfiles.find((profile) => profile.id.endsWith(id));
}

function taskById(id) {
  return tasks.find((task) => task.id === id);
}

for (const task of tasks) {
  const routed = routeTask(task);
  assert.equal(routed.receipts.length, agentVouchProfiles.length, `${task.id} should persist one receipt per profile`);
  if (task.riskTier === 'financial') {
    assert.equal(routed.selected, null, `${task.id} should fail closed when no profile clears the financial policy`);
  } else {
    assert.ok(routed.selected, `${task.id} should produce a selected decision`);
  }

  for (const receipt of routed.receipts) {
    assert.ok(actions.has(receipt.decision.action), `${receipt.receiptId} has valid decision action`);
    assert.equal(receipt.task.id, task.id, `${receipt.receiptId} preserves task id`);
    assert.equal(receipt.evidenceSnapshot.agentId, receipt.agentId, `${receipt.receiptId} preserves evidence agent id`);
    assert.equal(receipt.outcome, null, `${receipt.receiptId} starts without post-task outcome`);
  }
}

const revokedApi = makeReceipt(byId('1rRevokedEpsilon'), taskById('task-api-003'));
assert.equal(revokedApi.decision.action, 'block', 'revoked profile is always blocked');
assert.match(revokedApi.decision.reason, /revoked/);

const outOfScopeApi = makeReceipt(byId('9xResearchAlpha'), taskById('task-api-003'));
assert.equal(outOfScopeApi.decision.action, 'block', 'missing required scope blocks privileged API work');
assert.match(outOfScopeApi.decision.reason, /missing scope: api_write/);

const coldStartResearch = makeReceipt(byId('2cColdStartGamma'), taskById('task-research-001'));
assert.equal(coldStartResearch.decision.action, 'allow', 'cold-start research can enter sandbox when sandbox policy passes');

const customerFacing = routeTask(taskById('task-support-002'));
assert.equal(customerFacing.selected.agentId, 'agentvouch:solana:9xResearchAlpha', 'customer-facing work picks the highest-scored allowed support profile');
assert.equal(customerFacing.selected.decision.action, 'allow');

const privileged = routeTask(taskById('task-api-003'));
assert.equal(privileged.selected.agentId, 'agentvouch:solana:7kOpsBeta', 'privileged API work requires API scope plus sufficient evidence');
assert.equal(privileged.selected.decision.action, 'allow');

const financial = routeTask(taskById('task-refund-004'));
assert.equal(financial.selected, null, 'financial work should fail closed when no profile clears the capped policy');
assert.ok(
  financial.receipts.every((receipt) => receipt.decision.action === 'block'),
  'all current financial fixture receipts are blocked rather than silently capped',
);

console.log('AgentVouch x EMET router invariants passed.');
