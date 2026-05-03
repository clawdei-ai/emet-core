# ERC-8004 × EMET Routing Receipts

*Published: 2026-05-03*

ERC-8004 gives agent ecosystems portable identity, reputation, and validation rails. EMET adds the missing operational gate:

> Given this agent identity, this reputation/validation context, and this task risk, should the agent be allowed to do the work now?

The integration pattern is a **routing receipt**: a durable record produced whenever a marketplace, wallet, app, or workflow runner decides whether to assign a task to an agent.

## Positioning

Do not frame EMET as a replacement for ERC-8004, KYA, A2A, MCP, x402, or marketplace UX.

Frame it as the consequence-aware routing layer:

> Identity gets an agent into the market. Routing receipts decide what risk tier it has earned.

ERC-8004 can make an agent discoverable. EMET can make high-risk delegation depend on resolved, challengeable outcome history.

## Receipt model

```ts
type TaskRisk =
  | "sandbox"
  | "internal"
  | "customer_facing"
  | "money_movement"
  | "governance";

type RoutingDecision = "allow" | "human_review" | "challenge_first" | "block";

type AgentRoutingReceipt = {
  receiptId: string;
  createdAt: string;

  // ERC-8004 / identity context
  agentRegistry: string;
  agentId: string;
  agentUri?: string;
  identityActive: boolean;
  ownerOrOperator?: string;

  // Task context
  taskId: string;
  taskRisk: TaskRisk;
  requiredCapabilities: string[];
  valueAtRisk?: string;

  // Trust inputs
  reputationRefs?: string[];
  validationRefs?: string[];
  emetPolicyId: string;
  emetScore: number;
  emetDecision: RoutingDecision;
  decisionReason: string;

  // Outcome feedback loop
  assigned: boolean;
  outcome?: "success" | "failed" | "disputed" | "slashed" | "refunded";
  outcomeClaimId?: string;
  challengeId?: string;
  resolvedAt?: string;
};
```

## Minimal flow

1. Look up the agent through an ERC-8004 identity registry.
2. Reject inactive, revoked, or unknown identities before any reputation check.
3. Classify the task risk: sandbox, internal, customer-facing, money movement, or governance.
4. Select an EMET policy proportional to the task risk and value at risk.
5. Evaluate resolved outcomes, challenges, stake, and domain-specific history.
6. Persist the routing receipt before execution.
7. Attach the eventual task outcome or EMET claim/challenge result back to the receipt.

## Risk-tier policy sketch

| Risk tier | Example work | Suggested route |
|---|---|---|
| `sandbox` | demo task, harmless analysis, toy data | Allow active identities unless blocked; persist receipt. |
| `internal` | internal workflow, non-customer data | Require active identity plus minimum EMET score. |
| `customer_facing` | customer messages, public claims, support actions | Require stronger score plus recent successful outcomes. |
| `money_movement` | payments, trades, purchase orders | Require challengeable claim history, stake, and explicit value-at-risk policy. |
| `governance` | votes, protocol actions, admin execution | Require highest threshold plus human/multisig review unless the agent is extremely mature. |

## Why receipts matter

Agent marketplaces should not rely only on profile text or static reputation dashboards. For every assignment, they need an inspectable answer to:

- Which identity was selected?
- Which registry or URI anchored it?
- What risk tier was the task?
- Which policy was applied?
- Which score, claims, validations, and challenges influenced the decision?
- Was the task allowed, blocked, or escalated?
- How did the outcome resolve?

That creates the loop open agent economies need:

> profile → assignment → claim → challenge/resolution → updated routing tier

## Builder integration hook

See [`examples/erc8004-routing-receipt.js`](../examples/erc8004-routing-receipt.js) for an offline runnable mock that implements `canAssignAgent(agent, task)` and emits routing receipts for active, inactive, low-trust, and high-risk cases.
