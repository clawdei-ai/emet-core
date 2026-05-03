#!/usr/bin/env node

/**
 * ERC-8004 × EMET Routing Receipt example.
 *
 * Runs offline with mock ERC-8004 and EMET objects. The point is the routing
 * shape: discover identity first, classify task risk, evaluate EMET outcome
 * history, then persist a receipt before assignment.
 */

const registry = {
  "agent:research-pro": {
    registry: "erc8004:base:agents",
    agentId: "agent:research-pro",
    uri: "ipfs://agents/research-pro.json",
    active: true,
    owner: "0xResearchOperator",
  },
  "agent:payments-pro": {
    registry: "erc8004:base:agents",
    agentId: "agent:payments-pro",
    uri: "ipfs://agents/payments-pro.json",
    active: true,
    owner: "0xPaymentsOperator",
  },
  "agent:inactive": {
    registry: "erc8004:base:agents",
    agentId: "agent:inactive",
    uri: "ipfs://agents/inactive.json",
    active: false,
    owner: "0xFormerOperator",
  },
};

const trustProfiles = {
  "agent:research-pro": {
    score: 81,
    resolvedClaims: 34,
    openChallenges: 0,
    stakeUsd: 1200,
    domains: ["research", "customer_support"],
    reputationRefs: ["erc8004:rep:research-pro:2026-05"],
    validationRefs: ["erc8004:validation:research-pro:capabilities"],
  },
  "agent:payments-pro": {
    score: 91,
    resolvedClaims: 88,
    openChallenges: 0,
    stakeUsd: 8000,
    domains: ["payments", "commerce"],
    reputationRefs: ["erc8004:rep:payments-pro:2026-05"],
    validationRefs: ["erc8004:validation:payments-pro:spend-limit"],
  },
};

const tasks = [
  {
    id: "task:market-brief",
    domain: "research",
    risk: "customer_facing",
    requiredCapabilities: ["research.write", "citations"],
  },
  {
    id: "task:purchase-order",
    domain: "payments",
    risk: "money_movement",
    requiredCapabilities: ["commerce.purchase", "payments.spend"],
    valueAtRisk: 1500n,
  },
  {
    id: "task:dao-vote",
    domain: "governance",
    risk: "governance",
    requiredCapabilities: ["governance.vote"],
    valueAtRisk: 25_000n,
  },
];

const policies = {
  sandbox: { id: "EMET_SANDBOX", minScore: 20, minClaims: 0, maxOpenChallenges: 3, minStakeUsd: 0 },
  internal: { id: "EMET_INTERNAL", minScore: 55, minClaims: 5, maxOpenChallenges: 2, minStakeUsd: 100 },
  customer_facing: { id: "EMET_CUSTOMER_FACING", minScore: 75, minClaims: 20, maxOpenChallenges: 1, minStakeUsd: 500 },
  money_movement: { id: "EMET_MONEY_MOVEMENT", minScore: 88, minClaims: 50, maxOpenChallenges: 0, minStakeUsd: 5000 },
  governance: { id: "EMET_GOVERNANCE", minScore: 95, minClaims: 100, maxOpenChallenges: 0, minStakeUsd: 25000 },
};

function policyForTaskRisk(risk) {
  return policies[risk] ?? policies.internal;
}

async function getAgent(agentId) {
  return registry[agentId] ?? null;
}

async function evaluateEmet(agentId, task, policy) {
  const profile = trustProfiles[agentId];
  if (!profile) {
    return {
      passes: false,
      score: 0,
      reason: "NO_EMET_HISTORY",
      reputationRefs: [],
      validationRefs: [],
    };
  }

  const failures = [];
  if (profile.score < policy.minScore) failures.push(`score ${profile.score} < ${policy.minScore}`);
  if (profile.resolvedClaims < policy.minClaims) failures.push(`claims ${profile.resolvedClaims} < ${policy.minClaims}`);
  if (profile.openChallenges > policy.maxOpenChallenges) failures.push(`open challenges ${profile.openChallenges} > ${policy.maxOpenChallenges}`);
  if (profile.stakeUsd < policy.minStakeUsd) failures.push(`stake $${profile.stakeUsd} < $${policy.minStakeUsd}`);
  if (!profile.domains.includes(task.domain)) failures.push(`no domain history for ${task.domain}`);

  return {
    passes: failures.length === 0,
    score: profile.score,
    reason: failures.length ? failures.join("; ") : "POLICY_PASSED",
    reputationRefs: profile.reputationRefs,
    validationRefs: profile.validationRefs,
  };
}

function persistReceipt(receipt) {
  return {
    receiptId: `receipt:${receipt.taskId}:${receipt.agentId}`,
    createdAt: new Date().toISOString(),
    ...receipt,
  };
}

async function canAssignAgent(agentId, task) {
  const identity = await getAgent(agentId);
  if (!identity?.active) {
    return persistReceipt({
      agentRegistry: identity?.registry ?? "erc8004:base:agents",
      agentId,
      agentUri: identity?.uri,
      identityActive: false,
      ownerOrOperator: identity?.owner,
      taskId: task.id,
      taskRisk: task.risk,
      requiredCapabilities: task.requiredCapabilities,
      valueAtRisk: task.valueAtRisk?.toString(),
      emetPolicyId: "none",
      emetScore: 0,
      emetDecision: "block",
      decisionReason: "NO_ACTIVE_IDENTITY",
      assigned: false,
    });
  }

  const policy = policyForTaskRisk(task.risk);
  const trust = await evaluateEmet(agentId, task, policy);
  const decision = trust.passes
    ? "allow"
    : task.risk === "sandbox" || task.risk === "internal"
      ? "human_review"
      : task.risk === "governance"
        ? "challenge_first"
        : "block";

  return persistReceipt({
    agentRegistry: identity.registry,
    agentId,
    agentUri: identity.uri,
    identityActive: true,
    ownerOrOperator: identity.owner,
    taskId: task.id,
    taskRisk: task.risk,
    requiredCapabilities: task.requiredCapabilities,
    valueAtRisk: task.valueAtRisk?.toString(),
    reputationRefs: trust.reputationRefs,
    validationRefs: trust.validationRefs,
    emetPolicyId: policy.id,
    emetScore: trust.score,
    emetDecision: decision,
    decisionReason: trust.reason,
    assigned: decision === "allow",
  });
}

async function main() {
  const scenarios = [
    ["agent:research-pro", tasks[0]],
    ["agent:payments-pro", tasks[1]],
    ["agent:research-pro", tasks[1]],
    ["agent:payments-pro", tasks[2]],
    ["agent:inactive", tasks[0]],
    ["agent:unknown", tasks[0]],
  ];

  for (const [agentId, task] of scenarios) {
    const receipt = await canAssignAgent(agentId, task);
    console.log("\n--- Routing receipt ---");
    console.log(JSON.stringify(receipt, null, 2));
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
