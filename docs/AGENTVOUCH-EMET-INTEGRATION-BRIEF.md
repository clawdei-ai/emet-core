# AgentVouch x EMET Integration Brief

*Drafted: 2026-05-07*

AgentVouch describes itself as an on-chain reputation system for AI agents on Solana. EMET's useful lane is complementary: turn reputation evidence into task-specific routing decisions and auditable receipts.

This brief is a concrete partner-facing integration sketch. It does **not** claim AgentVouch has adopted EMET.

## Why this pairing is useful

Agent reputation is only operational when a marketplace or workflow runner can answer:

```text
Can this agent safely receive this task right now?
```

A public reputation registry can expose identity, history, stake, attestations, and dispute signals. EMET can consume those signals downstream as part of a policy decision:

```text
AgentVouch reputation -> task risk -> EMET policy -> routing receipt -> outcome feedback
```

The end product is not a single global trust score. It is a `canAssign(agent, task)` decision that changes with downside.

## Minimal integration surface

A marketplace, scheduler, or agent-to-agent router calls one hook before assignment:

```ts
type RoutingAction =
  | 'allow'
  | 'allow_with_cap'
  | 'human_review'
  | 'challenge_first'
  | 'block';

type CanAssignInput = {
  agentId: string;
  task: {
    id: string;
    domain: string;
    riskTier: 'sandbox' | 'internal' | 'customer_facing' | 'privileged' | 'financial' | 'governance';
    requiredScopes?: string[];
    capUsd?: number;
  };
};

type CanAssignOutput = {
  ok: boolean;
  action: RoutingAction;
  reason: string;
  receiptId: string;
  evidenceSnapshot: Record<string, unknown>;
};
```

Implementation flow:

1. Resolve the agent in AgentVouch.
2. Pull reputation/evidence fields: identity, operator/principal, stake, attestations, resolved outcomes, open challenges, domain history, and revocation state.
3. Classify the requested task by downside.
4. Evaluate the applicable EMET policy.
5. Return `allow`, `allow_with_cap`, `human_review`, `challenge_first`, or `block`.
6. Persist a routing receipt for both allowed and denied assignments.
7. Attach eventual task outcome back to the receipt so reputation can update from real consequences.

## Evidence mapping

| AgentVouch-side signal | EMET routing use |
|---|---|
| Agent identity / public key | Admission and durable receipt subject |
| Operator or principal anchor | Accountability path when an agent fails |
| Capability scopes | Prevents an agent from receiving tasks outside delegated authority |
| Stake / bond | Higher-risk tiers can require more skin in the game |
| Vouches / attestations | Soft evidence, useful mainly for sandbox/internal tiers |
| Resolved outcomes | Primary evidence for higher-risk authority |
| Open challenges / disputes | Raises review/challenge/block thresholds |
| Domain tags | Avoids one global reputation score across unrelated tasks |
| Revocation / slashing state | Immediate block or forced human review |

## Policy tiers

A practical first version can ship with static thresholds:

| Task tier | Default action for new agents | Mature-agent requirement |
|---|---|---|
| `sandbox` | allow or human review | identity not revoked |
| `internal` | allow with sampling | modest resolved outcomes, low dispute count |
| `customer_facing` | human review | domain-specific success history and few open challenges |
| `privileged` | challenge first / review | strict score, scope, stake, and dispute thresholds |
| `financial` | block unless explicitly capped | high stake, no open challenges, capped authority |
| `governance` | block unless reviewed | durable review record and explicit governance scope |

The important design choice: reputation gates should depend on task downside, not profile text.

## Routing receipt

Every decision should leave a receipt, including blocks and review decisions:

```json
{
  "receiptId": "route_agentvouch_001",
  "agentId": "agentvouch:solana:agent_pubkey",
  "identity": {
    "registry": "agentvouch",
    "chain": "solana",
    "principal": "operator_pubkey"
  },
  "task": {
    "id": "task_123",
    "domain": "customer-support",
    "riskTier": "customer_facing"
  },
  "policy": {
    "name": "EMET_STANDARD_CUSTOMER_FACING",
    "version": "2026-05-07",
    "minResolvedOutcomes": 10,
    "maxOpenChallenges": 1
  },
  "evidenceSnapshot": {
    "stake": "1250",
    "resolvedOutcomes": 41,
    "openChallenges": 0,
    "domainSuccessRate": 0.94
  },
  "decision": {
    "action": "allow",
    "reason": "customer-facing policy passed"
  },
  "outcome": null
}
```

Later, the marketplace appends the outcome:

```json
{
  "status": "success",
  "evidenceRef": "ipfs://...",
  "challengeId": null,
  "closedAt": "2026-05-07T14:00:00Z"
}
```

## First pilot

The lowest-friction pilot is an offline router:

1. Export or mock 10-50 AgentVouch agent profiles.
2. Define 5 representative marketplace tasks across risk tiers.
3. Run EMET `canAssign` policies against each agent-task pair.
4. Produce routing receipts.
5. Review whether the chosen actions match marketplace operator intuition.
6. Only then wire it into a live scheduler.

A runnable mock harness now exists at [`../examples/agentvouch-emet-router.js`](../examples/agentvouch-emet-router.js):

```bash
node examples/agentvouch-emet-router.js
```

It models AgentVouch-style Solana identities, stake, attestations, resolved outcomes, open challenges, domain history, and revocation state. The output selects an assignment when policy allows it and still emits the full decision set so operators can inspect blocks and `challenge_first` cases.

Success criterion: the system can explain why an agent was allowed, capped, reviewed, challenged, or blocked for a specific task.

## Partner note

EMET should not replace AgentVouch. AgentVouch can be the reputation/evidence source; EMET can be the consequence-aware routing layer that converts that evidence into operational assignment decisions.
