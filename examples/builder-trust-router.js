#!/usr/bin/env node
/**
 * EMET Builder Trust Router
 *
 * Shows how an agent marketplace, workflow runner, or MCP host can route work
 * through EMET's builder trust stack before handing an agent real authority.
 *
 * This example is intentionally offline: it injects mock TrustGate and
 * Scorecard contracts into the SDK so builders can run it before the builder
 * stack is deployed on Base mainnet.
 *
 * Run:
 *   node examples/builder-trust-router.js
 *
 * Swap the mock contracts for real Base addresses when EMETAgentProfile,
 * EMETTrustGate, and EMETScorecard are deployed.
 */

import { EMETTrust, Policy, formatScore } from '../sdk/src/index.js';

const agents = [
  {
    address: '0x1111111111111111111111111111111111111111',
    name: 'CalendarOps',
    specialty: 'low-risk scheduling',
    domains: ['calendar', 'customer-ops'],
    score: {
      passesLenient: true,
      passesStandard: true,
      passesStrict: false,
      accuracyBps: 7200,
      totalClaims: 9,
      correctClaims: 7,
      slashCount: 0,
      avgStakeWei: '25000000000000000000',
      riskAppetite: 2,
      reputation: 18,
      tier: 2,
      trustScore: 646
    }
  },
  {
    address: '0x2222222222222222222222222222222222222222',
    name: 'TreasuryPilot',
    specialty: 'money movement',
    domains: ['treasury', 'money'],
    score: {
      passesLenient: true,
      passesStandard: true,
      passesStrict: true,
      accuracyBps: 9100,
      totalClaims: 28,
      correctClaims: 26,
      slashCount: 0,
      avgStakeWei: '180000000000000000000',
      riskAppetite: 1,
      reputation: 132,
      tier: 4,
      trustScore: 932
    }
  },
  {
    address: '0x3333333333333333333333333333333333333333',
    name: 'NewResearchBot',
    specialty: 'fresh research',
    domains: ['research', 'market-intel'],
    score: {
      passesLenient: true,
      passesStandard: false,
      passesStrict: false,
      accuracyBps: 0,
      totalClaims: 1,
      correctClaims: 0,
      slashCount: 0,
      avgStakeWei: '1000000000000000000',
      riskAppetite: 3,
      reputation: 0,
      tier: 0,
      trustScore: 80
    }
  }
];

const byAddress = new Map(agents.map((agent) => [agent.address.toLowerCase(), agent]));

function requiredPolicy(task) {
  if (task.authority === 'money' || task.maxLossUsd >= 100) return Policy.STRICT;
  if (task.customerFacing || task.maxLossUsd >= 10) return Policy.STANDARD;
  return Policy.LENIENT;
}

function passesPolicy(score, policy) {
  if (policy === Policy.STRICT) return score.passesStrict;
  if (policy === Policy.STANDARD) return score.passesStandard;
  return score.passesLenient;
}

function reasonFor(score, policy) {
  if (passesPolicy(score, policy)) return 'passes';
  if (policy === Policy.STRICT) return 'needs >=80% accuracy, >=50 reputation, and >=10 resolved claims';
  if (policy === Policy.STANDARD) return 'needs >=60% accuracy, non-negative reputation, and >=3 resolved claims';
  return 'needs at least one recorded claim';
}

const mockScorecard = {
  async peek(address) {
    const agent = byAddress.get(address.toLowerCase());
    if (!agent) throw new Error(`Unknown agent ${address}`);
    return agent.score;
  },
  async check(address, policy) {
    const agent = byAddress.get(address.toLowerCase());
    if (!agent) throw new Error(`Unknown agent ${address}`);
    const passes = passesPolicy(agent.score, policy);
    return [passes, reasonFor(agent.score, policy)];
  }
};

const mockTrustGate = {
  async evaluate(address, policy) {
    const agent = byAddress.get(address.toLowerCase());
    if (!agent) throw new Error(`Unknown agent ${address}`);
    const passes = passesPolicy(agent.score, policy);
    return {
      passes,
      accuracyBps: agent.score.accuracyBps,
      reputation: agent.score.reputation,
      totalClaims: agent.score.totalClaims,
      reason: reasonFor(agent.score, policy)
    };
  },
  async evaluateBatch(addresses, policy) {
    return Promise.all(addresses.map((address) => this.evaluate(address, policy)));
  },
  async filter(addresses, policy) {
    return addresses.filter((address) => {
      const agent = byAddress.get(address.toLowerCase());
      return agent && passesPolicy(agent.score, policy);
    });
  }
};

const trust = new EMETTrust({ contracts: { scorecard: mockScorecard, trustGate: mockTrustGate } });

const tasks = [
  {
    id: 'task-001',
    title: 'book a dental cleaning',
    customerFacing: true,
    authority: 'calendar',
    maxLossUsd: 0,
    domain: 'calendar'
  },
  {
    id: 'task-002',
    title: 'rebalance a $500 agent treasury',
    customerFacing: false,
    authority: 'money',
    maxLossUsd: 500,
    domain: 'money'
  },
  {
    id: 'task-003',
    title: 'summarize three competitor launch posts',
    customerFacing: false,
    authority: 'research',
    maxLossUsd: 0,
    domain: 'research'
  }
];

async function routeTask(task) {
  const policy = requiredPolicy(task);
  const addresses = agents.map((agent) => agent.address);
  const eligible = await trust.evaluateBatch(addresses, policy);

  const ranked = eligible
    .filter((result) => result.passes)
    .map((result) => {
      const agent = byAddress.get(result.agent.toLowerCase());
      return { ...agent, evaluation: result };
    })
    .sort((a, b) => {
      const aDomainMatch = a.domains.includes(task.domain) ? 1 : 0;
      const bDomainMatch = b.domains.includes(task.domain) ? 1 : 0;
      if (aDomainMatch !== bDomainMatch) return bDomainMatch - aDomainMatch;
      return b.score.trustScore - a.score.trustScore;
    });

  if (ranked.length === 0) {
    return { task, policy, decision: 'manual-review', reason: 'no agent passed the required EMET policy' };
  }

  return { task, policy, decision: 'route', agent: ranked[0] };
}

console.log('\nEMET builder trust router\n');

for (const agent of agents) {
  const score = await trust.peek(agent.address);
  console.log(`${agent.name.padEnd(15)} ${formatScore(score)} · ${agent.specialty}`);
}

console.log('\nRouting decisions:\n');

for (const task of tasks) {
  const routed = await routeTask(task);
  const policyName = ['LENIENT', 'STANDARD', 'STRICT'][routed.policy] ?? 'CUSTOM';

  if (routed.decision === 'route') {
    console.log(`✓ ${task.id} (${policyName}) ${task.title}`);
    console.log(`  → ${routed.agent.name}: ${formatScore(routed.agent.score)}\n`);
  } else {
    console.log(`! ${task.id} (${policyName}) ${task.title}`);
    console.log(`  → ${routed.decision}: ${routed.reason}\n`);
  }
}

console.log('Integration pattern: choose policy from task risk, call evaluateBatch(), route only to agents that pass, and log the EMET result beside the assignment.');
