# KYA + EMET Trust Routing Pack

*Prepared: 2026-04-29*

This pack is the builder-facing version of the EMET + KYA story.

Use it when explaining how an agent marketplace, workflow runner, or autonomous app should decide whether an agent can receive work, money, credentials, or execution authority.

## One-line thesis

**KYA verifies who the agent is. EMET verifies whether the agent's outputs have earned trust under consequence.**

Identity alone is not enough, because a legitimate agent can still be wrong. Outcome history alone is not enough, because behavior should stay attached to a stable actor. The useful trust stack checks both.

## The trust routing flow

```text
agent candidate
  -> KYA identity / continuity check
  -> task risk classification
  -> EMET policy check
  -> route, reject, or require human approval
  -> log the decision for audit
```

Recommended default policies:

| Task risk | KYA role | EMET role | Route decision |
|---|---|---|---|
| Sandbox or demo | Basic identity anchor | `LENIENT` | Allow with low privileges |
| Internal enrichment | Stable identity | `LENIENT` or `STANDARD` | Allow if bad output stays internal |
| Customer-facing workflow | Stable identity + continuity | `STANDARD` | Allow only with resolved history |
| API access with side effects | Strong identity | `STANDARD` or `STRICT` | Gate before execution |
| Money, publishing, credentials | Strong identity + ownership continuity | `STRICT` | Gate and log every decision |
| Regulated / governance workflow | Custom policy | `CUSTOM` | Encode local thresholds |

## What builders should store

Every routed task should leave an inspectable record:

- agent address / identity anchor
- task ID and task risk label
- KYA identity result or reference
- EMET policy used
- pass/fail result
- reason string or failing threshold
- score snapshot at assignment time
- final task outcome after resolution

This turns delegation from an opaque scheduler choice into an audit trail.

## Integration surfaces

### JavaScript apps

Use the SDK trust layer for read-only previews, assignment checks, batch candidate filtering, and UI explanations.

Start with: [`../sdk/TRUST-COOKBOOK.md`](../sdk/TRUST-COOKBOOK.md)

### Marketplaces and workflow runners

Use task-risk mapping before assignment. Do not use one global score threshold for every task.

Start with: [`AGENT-MARKETPLACE-TRUST-ROUTING.md`](./AGENT-MARKETPLACE-TRUST-ROUTING.md)

### Identity + accountability framing

Use KYA for admission and continuity. Use EMET for outcome accountability, challenge history, stake, and trust gating.

Start with: [`EMET-KYA-STACK.md`](./EMET-KYA-STACK.md)

### KYA-OS policy adapter

Use KYA-OS for agent identity, delegated authority, scope, revocation, and conformance level. Use EMET to decide whether the agent's resolved outcome history has earned the requested risk tier.

Start with: [`KYA-OS-EMET-POLICY-ADAPTER.md`](./KYA-OS-EMET-POLICY-ADAPTER.md)

### On-chain routers

Use `EMETTrustGate` for policy checks and `EMETGatedRouter` when routing should happen directly in Solidity.

Start with: [`BUILDER-TRUST-QUICKSTART.md`](./BUILDER-TRUST-QUICKSTART.md)

## Honest status note

- `EMETReputation` is live on Base.
- `EMETAgentProfile`, `EMETTrustGate`, `EMETScorecard`, and builder routing examples are built and tested locally.
- Local verification: SDK tests/lint pass and `forge test` passes 676/676.
- Public GitHub distribution includes the SDK trust module, builder trust router, KYA + EMET pack, agent economy trust map, and KYA-OS policy adapter.
- Subgraph deployment remains blocked on Goldsky/Envio auth.

## Short announcement copy

```text
KYA tells you who an agent is.

EMET tells you what happened when its outputs were wrong, and whether the cost followed it.

The practical routing pattern is identity check -> task risk -> EMET policy -> auditable delegation.
```

```text
Agent marketplaces need more than profiles and reviews.

Before routing money or authority, check identity plus outcome history: who is this agent, what has it been wrong about, and what did it cost?
```
