import assert from 'node:assert/strict';
import test from 'node:test';

import { ABIS } from '../src/contracts.js';
import {
  EMETTrust,
  Policy,
  Tier,
  RiskAppetite,
  formatScore,
  normalizePolicy
} from '../src/trust.js';

const AGENT_A = '0x00000000000000000000000000000000000000aA';
const AGENT_B = '0x00000000000000000000000000000000000000bB';

function score(overrides = {}) {
  return {
    passesLenient: true,
    passesStandard: true,
    passesStrict: false,
    accuracyBps: 7500n,
    totalClaims: 10n,
    correctClaims: 8n,
    slashCount: 2n,
    avgStakeWei: 1000000000000000n,
    riskAppetite: RiskAppetite.MEDIUM,
    reputation: 60n,
    tier: Tier.GOLD,
    trustScore: 694n,
    ...overrides
  };
}

function trustResult(overrides = {}) {
  return {
    passes: true,
    accuracyBps: 7500n,
    reputation: 60n,
    totalClaims: 10n,
    reason: 'PASS',
    ...overrides
  };
}

function makeTrust() {
  const calls = [];
  const contracts = {
    scorecard: {
      async score(agent) { calls.push(['score', agent]); return score(); },
      async peek(agent) { calls.push(['peek', agent]); return score(); },
      async check(agent, policy) { calls.push(['scorecard.check', agent, policy]); return [policy !== Policy.STRICT, policy === Policy.STRICT ? 'LOW_ACCURACY' : 'PASS']; },
      async tierOf(agent) { calls.push(['tierOf', agent]); return Tier.GOLD; },
      async trustScoreOf(agent) { calls.push(['trustScoreOf', agent]); return 694n; }
    },
    trustGate: {
      async evaluate(agent, policy) { calls.push(['evaluate', agent, policy]); return trustResult({ passes: policy !== Policy.STRICT }); },
      async evaluateBatch(agents, policy) { calls.push(['evaluateBatch', agents, policy]); return agents.map((agent, i) => trustResult({ passes: i === 0 })); },
      async filter(agents, policy) { calls.push(['filter', agents, policy]); return [agents[0]]; },
      async query(agent, policy) { calls.push(['query', agent, policy]); return [true, 'PASS']; }
    },
    agentProfile: {
      async getProfile(agent) { calls.push(['getProfile', agent]); return { totalClaims: 10n, correctClaims: 8n, slashCount: 2n, totalStakeWei: 10000000000000000n, avgStakeWei: 1000000000000000n, accuracyBps: 7500n, riskAppetite: RiskAppetite.MEDIUM }; }
    },
    reputation: {
      async getReputation(agent) { calls.push(['getReputation', agent]); return 60n; }
    }
  };

  return { trust: new EMETTrust({ contracts, provider: {} }), calls };
}

test('exports expected enums and policy normalization', () => {
  assert.equal(Policy.LENIENT, 0);
  assert.equal(Policy.STANDARD, 1);
  assert.equal(Policy.STRICT, 2);
  assert.equal(Policy.CUSTOM, 3);
  assert.equal(Tier.PLATINUM, 4);
  assert.equal(RiskAppetite.HIGH, 3);
  assert.equal(normalizePolicy('strict'), Policy.STRICT);
  assert.throws(() => normalizePolicy('impossible'), /Unknown EMET policy/);
});

test('builder trust ABIs include primary integration methods', () => {
  const trustGateAbi = ABIS.EMETTrustGate.join('\n');
  const scorecardAbi = ABIS.EMETScorecard.join('\n');
  const profileAbi = ABIS.EMETAgentProfile.join('\n');

  assert.match(trustGateAbi, /function check\(/);
  assert.match(trustGateAbi, /function evaluateBatch\(/);
  assert.match(trustGateAbi, /function filter\(/);
  assert.match(scorecardAbi, /function score\(/);
  assert.match(scorecardAbi, /function peek\(/);
  assert.match(scorecardAbi, /function trustScoreOf\(/);
  assert.match(profileAbi, /function getProfile\(/);
});

test('score and peek normalize Scorecard struct values', async () => {
  const { trust } = makeTrust();
  const s = await trust.score(AGENT_A);
  assert.equal(s.tierName, 'GOLD');
  assert.equal(s.trustScore, 694);
  assert.equal(s.accuracyBps, 7500);
  assert.equal(s.avgStakeWei, '1000000000000000');
  assert.equal(s.riskAppetiteName, 'MEDIUM');

  const p = await trust.peek(AGENT_A);
  assert.equal(p.passesStandard, true);
});

test('check supports string or numeric policies', async () => {
  const { trust } = makeTrust();
  assert.deepEqual(await trust.check(AGENT_A, 'standard'), { agent: AGENT_A, policy: Policy.STANDARD, policyName: 'STANDARD', passes: true, reason: 'PASS' });
  assert.equal((await trust.check(AGENT_A, Policy.STRICT)).passes, false);
});

test('evaluate, evaluateBatch, and filter use TrustGate view APIs', async () => {
  const { trust } = makeTrust();
  const one = await trust.evaluate(AGENT_A, Policy.STANDARD);
  assert.equal(one.reason, 'PASS');
  assert.equal(one.policyName, 'STANDARD');

  const batch = await trust.evaluateBatch([AGENT_A, AGENT_B], 'strict');
  assert.equal(batch.length, 2);
  assert.equal(batch[0].agent, AGENT_A);
  assert.equal(batch[0].policyName, 'STRICT');

  assert.deepEqual(await trust.filter([AGENT_A, AGENT_B], Policy.STANDARD), [AGENT_A]);
});

test('tier/trust-score helpers and profile aggregation are builder-friendly', async () => {
  const { trust } = makeTrust();
  assert.deepEqual(await trust.tierOf(AGENT_A), { tier: Tier.GOLD, tierName: 'GOLD' });
  assert.equal(await trust.trustScoreOf(AGENT_A), 694);

  const profile = await trust.getProfile(AGENT_A);
  assert.equal(profile.totalClaims, 10);
  assert.equal(profile.reputation, 60);
  assert.equal(profile.score.tierName, 'GOLD');
  assert.match(formatScore(profile.score), /GOLD 694\/1000/);
});

test('unrated agents normalize safely', async () => {
  const trust = new EMETTrust({
    provider: {},
    contracts: {
      scorecard: {
        async score() { return score({ passesLenient: false, passesStandard: false, passesStrict: false, totalClaims: 0n, correctClaims: 0n, accuracyBps: 0n, reputation: 0n, tier: Tier.UNRATED, trustScore: 0n }); },
        async peek() { return score({ tier: Tier.UNRATED, trustScore: 0n }); },
        async check() { return [false, 'NO_HISTORY: agent has no resolved claims']; },
        async tierOf() { return Tier.UNRATED; },
        async trustScoreOf() { return 0n; }
      },
      trustGate: {},
      agentProfile: {},
      reputation: {}
    }
  });

  const s = await trust.score(AGENT_A);
  assert.equal(s.tierName, 'UNRATED');
  assert.equal(s.trustScore, 0);
  assert.equal((await trust.check(AGENT_A)).passes, false);
});
