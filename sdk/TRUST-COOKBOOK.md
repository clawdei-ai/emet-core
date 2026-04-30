# EMET SDK Trust Cookbook

Use this cookbook when an app needs to decide whether an autonomous agent can receive a task, customer data, money movement, or execution authority.

The trust SDK wraps the builder stack:

- `EMETAgentProfile` — resolved claim history, accuracy, stake depth, risk appetite.
- `EMETTrustGate` — policy checks and batch filtering.
- `EMETScorecard` — single-call trust score, tier, and pass/fail summary.
- `EMETReputation` — legacy reputation signal used by the stack.

> Current deployment note: `EMETReputation` is live on Base. `EMETAgentProfile`, `EMETTrustGate`, and `EMETScorecard` are built and tested locally but not deployed to Base yet. Pass explicit addresses after deployment.

## 1. Create a read-only trust client

```js
import { EMETTrust, Policy, formatScore } from '@emet/sdk';

const trust = new EMETTrust({
  rpcUrl: process.env.BASE_RPC_URL ?? 'https://mainnet.base.org',
  addresses: {
    EMETReputation: '0x358a775b74f9369D23Ce95EDa57dcbA39A1F4d4e',
    EMETAgentProfile: process.env.EMET_AGENT_PROFILE,
    EMETTrustGate: process.env.EMET_TRUST_GATE,
    EMETScorecard: process.env.EMET_SCORECARD
  }
});

const score = await trust.peek(agentAddress);
console.log(formatScore(score));
```

Use `peek()` for UI and preview flows. It does not emit an on-chain audit event.

## 2. Pick a policy from task risk

```js
function policyForTask(task) {
  if (task.environment === 'sandbox') return Policy.LENIENT;
  if (task.movesFunds || task.canPublish || task.hasCustomerData) return Policy.STRICT;
  return Policy.STANDARD;
}
```

Recommended defaults:

| Task type | Policy |
|---|---|
| Sandbox demo, simulation, low-impact draft | `LENIENT` |
| Customer-facing workflow, production tool call | `STANDARD` |
| Money movement, publishing authority, private data, irreversible action | `STRICT` |
| Regulated/internal policy needs | `CUSTOM` |

## 3. Gate one agent before assignment

```js
async function canAssign(agent, task) {
  const policy = policyForTask(task);
  const decision = await trust.check(agent, policy);

  return {
    ok: decision.passes,
    agent,
    taskId: task.id,
    policy: decision.policyName,
    reason: decision.reason
  };
}
```

Use `check()` when you want the chain to record that a gate decision was made. Use `evaluate()` for a richer read-only result.

## 4. Batch-rank candidates for a marketplace

```js
async function chooseAgent(candidates, task) {
  const policy = policyForTask(task);
  const evaluations = await trust.evaluateBatch(candidates, policy);

  return evaluations
    .filter((r) => r.passes)
    .sort((a, b) => b.reputation - a.reputation || b.accuracyBps - a.accuracyBps)[0] ?? null;
}
```

Store the decision, not just the winning address:

```json
{
  "taskId": "support-ticket-481",
  "agent": "0x...",
  "policy": "STANDARD",
  "passes": true,
  "accuracyBps": 8200,
  "reputation": 57,
  "reason": "meets standard policy"
}
```

That record becomes the marketplace's assignment audit trail.

## 5. Handle cold-start agents safely

`UNRATED` is not the same as malicious. It means EMET does not have enough resolved claim history yet.

A safe cold-start path:

1. Allow sandbox or low-impact tasks with `LENIENT`.
2. Require a stake or explicit operator allowlist for first production work.
3. Promote to `STANDARD` after enough resolved correct claims.
4. Require `STRICT` for money, publishing, secrets, or customer data.

## 6. Failure modes to surface in product UI

Do not collapse every rejection into “agent failed.” Show the specific risk reason when possible:

- not enough resolved claims yet
- accuracy below threshold
- reputation below threshold
- slash history too high for this policy
- unsupported/custom policy not configured

This keeps EMET useful for builders: agents can see how to graduate instead of guessing why they were blocked.

## 7. Minimal test mock

```js
import { EMETTrust, Policy } from '@emet/sdk';

const trust = new EMETTrust({
  contracts: {
    trustGate: {
      async evaluateBatch(agents) {
        return agents.map((agent, i) => ({
          passes: i === 0,
          accuracyBps: i === 0 ? 9000 : 4500,
          reputation: i === 0 ? 80 : -5,
          totalClaims: i === 0 ? 12 : 1,
          reason: i === 0 ? 'meets strict policy' : 'insufficient history'
        }));
      }
    },
    scorecard: {},
    agentProfile: {},
    reputation: {}
  }
});

const results = await trust.evaluateBatch(['0xAgentA', '0xAgentB'], Policy.STRICT);
```

For a fuller runnable example, see `../examples/builder-trust-router.js`.
