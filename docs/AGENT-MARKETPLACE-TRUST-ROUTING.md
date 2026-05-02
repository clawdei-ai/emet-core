# Agent Marketplace Trust Routing with EMET

*Written: 2026-04-29*

Agent marketplaces need a routing rule that is stronger than profiles, reviews, or vibes.

The practical question is simple:

> Before this marketplace gives an agent a task, money, credentials, or external authority, what proof says this agent has earned that level of trust?

EMET answers the output-accountability side of that question. Identity systems such as KYA can answer who the agent is. EMET answers what happened when the agent's outputs were wrong, whether there was stake, and whether later routing decisions inherited that evidence.

## The marketplace pattern

Use three gates before assigning work:

1. **Identity gate** — verify the agent is the same actor you think it is.
2. **Risk gate** — classify the task by possible downside.
3. **Outcome gate** — require enough EMET history for that risk tier.

In code, this usually becomes:

```js
const policy = policyFor(task);
const candidates = await marketplace.findCandidates(task);
const evaluations = await trust.evaluateBatch(candidates, policy);
const eligible = evaluations.filter((agent) => agent.passes);
```

Then route only to eligible agents, and log the policy, result, and reason next to the assignment.

## Risk-to-policy mapping

| Task type | Suggested EMET policy | Why |
|---|---|---|
| Sandbox research | `LENIENT` | Low downside; useful for cold-start agents. |
| Internal enrichment | `LENIENT` or `STANDARD` | Depends on whether bad output reaches users. |
| Customer-facing action | `STANDARD` | Needs a non-trivial resolved history. |
| API access with side effects | `STANDARD` | Errors can affect real accounts or workflows. |
| Money movement | `STRICT` | Requires stronger accuracy, depth, and reputation. |
| Governance / permissions | `STRICT` | Bad delegation can compound across systems. |
| Custom regulated workflow | `CUSTOM` | Marketplace should encode its own threshold. |

Do not make one global trust threshold. Task risk should decide the policy.

## Minimal routing checklist

For every assignment, store:

- agent address / identity anchor
- task ID and task risk label
- EMET policy used (`LENIENT`, `STANDARD`, `STRICT`, or `CUSTOM`)
- pass/fail result
- reason string or failing threshold
- score snapshot at assignment time
- final task outcome when it resolves

That turns delegation into an audit trail instead of an opaque scheduler decision.

## Cold-start rule

`UNRATED` should not mean banned.

A new agent may be allowed to:

- run sandbox tasks
- submit low-stake claims
- operate behind human approval
- graduate to production only after enough resolved outcomes

A useful marketplace lets agents climb from `LENIENT` to `STANDARD` to `STRICT` by doing real work under consequence.

## What EMET should not replace

EMET is not a full identity layer. A marketplace should still use KYA-style checks for:

- operator continuity
- wallet tenure
- ownership transfer risk
- sybil resistance
- admission into the marketplace

The clean split is:

> KYA controls admission. EMET controls consequence-aware routing.

For a concrete KYA-OS adapter boundary, see [`KYA-OS-EMET-POLICY-ADAPTER.md`](./KYA-OS-EMET-POLICY-ADAPTER.md).

## Runnable example

See [`examples/builder-trust-router.js`](../examples/builder-trust-router.js).

It runs offline with mock contracts and shows:

- mapping task risk to EMET policy
- calling the SDK's `evaluateBatch()`
- ranking eligible agents by domain fit and trust score
- routing work only after the policy passes

Run it locally:

```bash
node examples/builder-trust-router.js
```

For identity + delegated-scope routing, also see [`examples/kya-os-policy-adapter.js`](../examples/kya-os-policy-adapter.js):

```bash
node examples/kya-os-policy-adapter.js
```

## Integration target

The first useful integration is not a complex marketplace rewrite.

It is one routing hook:

```js
async function canAssign(agent, task) {
  const policy = policyFor(task);
  const result = await trust.check(agent, policy);
  audit.log({ agent, task: task.id, policy, result });
  return result.passes;
}
```

That one hook gives builders a defensible answer when users ask why an autonomous system chose one agent over another.
