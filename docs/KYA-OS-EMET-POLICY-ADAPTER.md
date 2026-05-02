# KYA-OS ↔ EMET Policy Adapter

*Published: 2026-05-02*

KYA-OS can answer the admission question for agent systems:

> Is this agent known, authorized by the right principal, and acting within a delegated scope?

EMET answers the graduation question:

> Given this agent's challengeable outcome history, what risk tier should the system allow next?

The clean integration is not to replace KYA-OS with EMET. KYA-OS verifies identity, delegation, scope, and revocation. EMET supplies consequence-aware trust evidence after the agent acts.

## Adapter boundary

A KYA-OS ↔ EMET adapter should sit between five steps:

1. **KYA verification** — identity, principal, credential scope, revocation, conformance level.
2. **Task classification** — sandbox, internal, customer-facing, money movement, or governance.
3. **EMET policy check** — resolved claims, challenges, slashing/rewards, stale history, minimum stake, and domain-specific trust.
4. **Routing decision** — allow, allow with cap, require human review, challenge first, or block.
5. **Policy receipt** — a durable record that future agents, users, marketplaces, or auditors can inspect.

## Minimal data model

```ts
type KyaVerification = {
  agentId: string;              // DID, KYA agent identifier, or equivalent stable ID
  principalId: string;          // human, organization, or system delegator
  credentialId: string;
  conformanceLevel: 1 | 2 | 3;
  scope: string[];
  expiresAt?: string;
  revoked: boolean;
  verifiedAt: string;
};

type DelegatedTask = {
  taskId: string;
  domain: "research" | "trading" | "support" | "payments" | "governance" | "code";
  action: string;
  requestedScope: string[];
  risk: "sandbox" | "internal" | "customer_facing" | "money_movement" | "governance";
  maxSpendUsd?: number;
  sideEffects: boolean;
};

type EmetTrustPolicy = {
  minScore: number;
  minResolvedClaims: number;
  maxOpenChallenges: number;
  minStakeUsd?: number;
  domainsRequired?: string[];
  requireRecentOutcomeDays?: number;
};

type AgentPolicyDecision = {
  ok: boolean;
  route: "allow" | "allow_with_cap" | "human_review" | "challenge_first" | "block";
  reason: string;
  kya: Pick<KyaVerification, "agentId" | "principalId" | "credentialId" | "conformanceLevel">;
  emet: {
    score: number;
    policy: EmetTrustPolicy;
    passes: boolean;
  };
  receiptId: string;
};
```

## Policy table

| Task risk | KYA requirement | EMET requirement | Default route |
|---|---|---|---|
| Sandbox | Active identity; scope includes task family | None or low minimum score | Allow |
| Internal | Active identity; unexpired delegation; Level 1+ acceptable | Basic score + no severe unresolved challenges | Allow / human review |
| Customer-facing | Active identity; explicit scope; revocation checked; Level 2 preferred | Domain outcome history + recent resolved claims | Allow with cap / review |
| Money movement | Explicit spend scope; principal bound; revocation checked; Level 2+ | Higher score, stake-backed claims, no relevant unresolved challenge | Allow with cap or challenge first |
| Governance | Explicit governance scope; strong principal binding; Level 3 preferred | High score, domain-specific history, public/challengeable evidence | Human review unless exceptional |

## Adapter pseudocode

```ts
async function decideAgentDelegation(agentId: string, task: DelegatedTask): Promise<AgentPolicyDecision> {
  const kya = await kyaVerifier.verifyAgent(agentId);

  if (!kya || kya.revoked) {
    return block("KYA_NOT_ACTIVE", kya, task);
  }

  if (!scopeCovers(kya.scope, task.requestedScope)) {
    return block("DELEGATION_SCOPE_MISMATCH", kya, task);
  }

  if (requiresLevel2(task) && kya.conformanceLevel < 2) {
    return review("KYA_LEVEL_TOO_LOW_FOR_RISK", kya, task);
  }

  const policy = emetPolicyFor(task);
  const scorecard = await emet.evaluateAgent(agentId, policy);
  const decision = routeByRisk(task, kya, scorecard, policy);

  const receiptId = await policyReceiptStore.write({
    kind: "KYA_EMET_POLICY_DECISION",
    agentId,
    principalId: kya.principalId,
    credentialId: kya.credentialId,
    taskId: task.taskId,
    domain: task.domain,
    risk: task.risk,
    requestedScope: task.requestedScope,
    kyaConformanceLevel: kya.conformanceLevel,
    emetScore: scorecard.score,
    emetPolicy: policy,
    route: decision.route,
    reason: decision.reason,
    decidedAt: new Date().toISOString()
  });

  return { ...decision, receiptId };
}
```

## Receipt lifecycle

A policy receipt is useful only if it later connects to the task outcome.

1. **Before task:** KYA-OS verifies identity/scope; EMET evaluates outcome history; adapter writes a routing receipt.
2. **During task:** the system enforces spend/action caps from the route.
3. **After task:** outcome is attached to the receipt: success/failure, evidence URI, human override, customer impact, spend, and dispute window.
4. **If challenged:** EMET claim/challenge/resolution updates the agent's future scorecard.
5. **Next task:** the adapter reads the updated history and changes the route.

This bridges identity to consequences:

> KYA proves the agent was allowed to try. EMET records whether the agent earned more trust after trying.

## Product examples

### Travel or commerce agent

KYA-OS verifies that the agent is delegated by Alice, can search and book travel up to $1,000, and has not had its credential revoked. EMET checks prior booking outcomes, refund/dispute history, and resolved claim record. The adapter allows booking under cap and requires human approval above cap.

### Prediction-market research agent

KYA-OS verifies that the agent is authorized by a fund/operator and that the scope allows research and recommendations but not trading. EMET checks calibration history, resolved market calls, and challenge history. The adapter allows recommendations and blocks execution unless trading delegation exists.

### Customer-support agent

KYA-OS verifies that the agent is authorized by the company and that scope allows refunds up to a threshold. EMET checks support-case outcome history and unresolved customer-impact disputes. The adapter allows low-risk responses and reviews refunds if recent outcomes degraded.

## Runnable example

See [`examples/kya-os-policy-adapter.js`](../examples/kya-os-policy-adapter.js).

It runs offline with mock KYA and EMET objects and demonstrates:

- KYA identity/scope/revocation checks
- task-risk to EMET-policy mapping
- consequence-aware routing decisions
- durable policy receipts that can later be linked to task outcomes

Run it locally:

```bash
node examples/kya-os-policy-adapter.js
```

## Related docs

- [`KYA-EMET-TRUST-ROUTING-PACK.md`](./KYA-EMET-TRUST-ROUTING-PACK.md)
- [`AGENT-MARKETPLACE-TRUST-ROUTING.md`](./AGENT-MARKETPLACE-TRUST-ROUTING.md)
- [`EMET-KYA-STACK.md`](./EMET-KYA-STACK.md)
