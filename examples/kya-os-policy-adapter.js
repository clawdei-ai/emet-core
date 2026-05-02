#!/usr/bin/env node

/**
 * KYA-OS ↔ EMET Policy Adapter example.
 *
 * Runs offline with mock KYA and EMET objects. The point is the routing shape:
 * verify identity + delegated scope first, then use EMET outcome history to
 * decide what risk tier the agent can touch.
 */

const agents = {
  "did:kya:travel-agent": {
    agentId: "did:kya:travel-agent",
    principalId: "did:example:alice",
    credentialId: "vc:travel-agent:alice:2026-05",
    conformanceLevel: 2,
    scope: ["travel.search", "travel.book", "payments.spend:1000"],
    revoked: false,
    verifiedAt: "2026-05-02T20:00:00Z",
  },
  "did:kya:research-agent": {
    agentId: "did:kya:research-agent",
    principalId: "did:example:fund-operator",
    credentialId: "vc:research-agent:fund:2026-05",
    conformanceLevel: 1,
    scope: ["markets.research", "markets.recommend"],
    revoked: false,
    verifiedAt: "2026-05-02T20:00:00Z",
  },
  "did:kya:revoked-agent": {
    agentId: "did:kya:revoked-agent",
    principalId: "did:example:company",
    credentialId: "vc:support-agent:company:2026-05",
    conformanceLevel: 2,
    scope: ["support.reply", "support.refund:50"],
    revoked: true,
    verifiedAt: "2026-05-02T20:00:00Z",
  },
};

const scorecards = {
  "did:kya:travel-agent": {
    score: 86,
    resolvedClaims: 47,
    openChallenges: 0,
    stakeUsd: 2500,
    domains: ["travel", "payments"],
  },
  "did:kya:research-agent": {
    score: 72,
    resolvedClaims: 24,
    openChallenges: 1,
    stakeUsd: 400,
    domains: ["research", "trading"],
  },
};

const tasks = [
  {
    taskId: "task:book-flight:001",
    domain: "payments",
    action: "book refundable flight",
    requestedScope: ["travel.book", "payments.spend:1000"],
    risk: "money_movement",
    maxSpendUsd: 850,
    sideEffects: true,
  },
  {
    taskId: "task:market-brief:002",
    domain: "trading",
    action: "write prediction-market research brief",
    requestedScope: ["markets.research"],
    risk: "customer_facing",
    sideEffects: false,
  },
  {
    taskId: "task:refund:003",
    domain: "support",
    action: "issue customer refund",
    requestedScope: ["support.refund:50"],
    risk: "customer_facing",
    maxSpendUsd: 40,
    sideEffects: true,
  },
];

const kyaVerifier = {
  async verifyAgent(agentId) {
    return agents[agentId] ?? null;
  },
};

const emet = {
  async evaluateAgent(agentId, policy) {
    const scorecard = scorecards[agentId] ?? {
      score: 0,
      resolvedClaims: 0,
      openChallenges: 0,
      stakeUsd: 0,
      domains: [],
    };

    const passes =
      scorecard.score >= policy.minScore &&
      scorecard.resolvedClaims >= policy.minResolvedClaims &&
      scorecard.openChallenges <= policy.maxOpenChallenges &&
      scorecard.stakeUsd >= (policy.minStakeUsd ?? 0) &&
      (policy.domainsRequired ?? []).every((domain) => scorecard.domains.includes(domain));

    return {
      ...scorecard,
      passes,
      reason: passes ? "EMET_POLICY_PASSED" : "EMET_POLICY_FAILED",
    };
  },
};

const policyReceiptStore = {
  receipts: [],
  async write(receipt) {
    const receiptId = `receipt:${String(this.receipts.length + 1).padStart(3, "0")}`;
    this.receipts.push({ receiptId, ...receipt });
    return receiptId;
  },
};

function scopeCovers(grantedScopes, requestedScopes) {
  return requestedScopes.every((requested) => grantedScopes.includes(requested));
}

function requiresLevel2(task) {
  return ["customer_facing", "money_movement", "governance"].includes(task.risk);
}

function emetPolicyFor(task) {
  switch (task.risk) {
    case "sandbox":
      return { minScore: 0, minResolvedClaims: 0, maxOpenChallenges: 5 };
    case "internal":
      return { minScore: 55, minResolvedClaims: 5, maxOpenChallenges: 3 };
    case "customer_facing":
      return {
        minScore: 70,
        minResolvedClaims: 15,
        maxOpenChallenges: 1,
        domainsRequired: [task.domain],
      };
    case "money_movement":
      return {
        minScore: 82,
        minResolvedClaims: 30,
        maxOpenChallenges: 0,
        minStakeUsd: task.maxSpendUsd ? task.maxSpendUsd * 2 : 1000,
        domainsRequired: [task.domain],
      };
    case "governance":
      return { minScore: 92, minResolvedClaims: 75, maxOpenChallenges: 0, minStakeUsd: 10000 };
    default:
      throw new Error(`Unknown risk tier: ${task.risk}`);
  }
}

function routeByRisk(task, kya, scorecard, policy) {
  if (!scorecard.passes) {
    return task.risk === "sandbox"
      ? { ok: false, route: "human_review", reason: scorecard.reason }
      : { ok: false, route: "challenge_first", reason: scorecard.reason };
  }

  if (task.risk === "money_movement" && task.maxSpendUsd) {
    return { ok: true, route: "allow_with_cap", reason: `ALLOW_UNDER_${task.maxSpendUsd}_USD_CAP` };
  }

  if (task.risk === "governance" && kya.conformanceLevel < 3) {
    return { ok: false, route: "human_review", reason: "GOVERNANCE_REQUIRES_LEVEL_3_OR_REVIEW" };
  }

  return { ok: true, route: "allow", reason: "KYA_AND_EMET_POLICY_PASSED" };
}

function pickKya(kya) {
  if (!kya) return null;
  return {
    agentId: kya.agentId,
    principalId: kya.principalId,
    credentialId: kya.credentialId,
    conformanceLevel: kya.conformanceLevel,
  };
}

async function decideAgentDelegation(agentId, task) {
  const kya = await kyaVerifier.verifyAgent(agentId);

  if (!kya || kya.revoked) {
    return writeDecision({
      task,
      kya,
      policy: null,
      scorecard: null,
      decision: { ok: false, route: "block", reason: "KYA_NOT_ACTIVE" },
    });
  }

  if (!scopeCovers(kya.scope, task.requestedScope)) {
    return writeDecision({
      task,
      kya,
      policy: null,
      scorecard: null,
      decision: { ok: false, route: "block", reason: "DELEGATION_SCOPE_MISMATCH" },
    });
  }

  if (requiresLevel2(task) && kya.conformanceLevel < 2) {
    return writeDecision({
      task,
      kya,
      policy: null,
      scorecard: null,
      decision: { ok: false, route: "human_review", reason: "KYA_LEVEL_TOO_LOW_FOR_RISK" },
    });
  }

  const policy = emetPolicyFor(task);
  const scorecard = await emet.evaluateAgent(agentId, policy);
  const decision = routeByRisk(task, kya, scorecard, policy);

  return writeDecision({ task, kya, policy, scorecard, decision });
}

async function writeDecision({ task, kya, policy, scorecard, decision }) {
  const receiptId = await policyReceiptStore.write({
    kind: "KYA_EMET_POLICY_DECISION",
    agentId: kya?.agentId ?? "unknown",
    principalId: kya?.principalId ?? null,
    credentialId: kya?.credentialId ?? null,
    taskId: task.taskId,
    domain: task.domain,
    risk: task.risk,
    requestedScope: task.requestedScope,
    kyaConformanceLevel: kya?.conformanceLevel ?? null,
    emetScore: scorecard?.score ?? null,
    emetPolicy: policy,
    route: decision.route,
    reason: decision.reason,
    decidedAt: new Date().toISOString(),
  });

  return {
    ...decision,
    receiptId,
    kya: pickKya(kya),
    emet: policy
      ? {
          score: scorecard.score,
          policy,
          passes: scorecard.passes,
        }
      : null,
  };
}

async function main() {
  const scenarios = [
    ["did:kya:travel-agent", tasks[0]],
    ["did:kya:research-agent", tasks[1]],
    ["did:kya:revoked-agent", tasks[2]],
  ];

  for (const [agentId, task] of scenarios) {
    const decision = await decideAgentDelegation(agentId, task);
    console.log(`${task.taskId} -> ${decision.route} (${decision.reason})`);
    console.log(`  receipt: ${decision.receiptId}`);
  }

  console.log("\nPolicy receipts:");
  console.log(JSON.stringify(policyReceiptStore.receipts, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
