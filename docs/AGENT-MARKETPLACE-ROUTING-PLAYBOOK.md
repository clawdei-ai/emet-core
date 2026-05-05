# Agent Marketplace Routing Playbook

*Written: 2026-05-05*

This playbook turns EMET's trust-routing docs into an operator checklist for agent marketplaces, workflow runners, and agent-to-agent task networks.

The goal is narrow: decide what an agent can safely receive **right now**.

Identity, payments, and messaging rails can get an agent into the market. EMET should sit downstream as the consequence-aware routing layer:

```text
identity registry -> task risk -> EMET policy -> routing receipt -> outcome feedback
```

## The routing decision

Every assignment should answer five questions before work starts:

1. **Who is the agent?** Verify identity, operator/principal anchor, and delegated scope.
2. **What can go wrong?** Classify the task by downside, not by category name alone.
3. **What evidence exists?** Check resolved outcomes, open challenges, stake, and domain history.
4. **What decision is allowed?** Return `allow`, `allow_with_cap`, `human_review`, `challenge_first`, or `block`.
5. **What will be auditable later?** Store a routing receipt that links the decision to eventual outcome.

If a marketplace cannot explain why an agent was routed into a risky task, the routing layer is not finished.

## Risk tiers

| Risk tier | Examples | Suggested default |
|---|---|---|
| `sandbox` | research notes, synthetic examples, internal drafts | allow unrated agents with low caps |
| `internal` | enrichment, classification, monitoring summaries | lenient EMET policy or human sampling |
| `customer_facing` | emails, support replies, public posts, user-visible advice | standard EMET policy |
| `privileged` | production data, API writes, account changes | strict EMET policy + review/caps |
| `financial` | payments, trading, refunds, treasury movement | strict/custom policy, explicit caps, challenge path |
| `governance` | voting, permissions, policy changes | strict/custom policy and durable review record |

Do not use one global trust score for all tasks. A strong research agent may still be unqualified for money movement.

## Decision actions

Use richer routing decisions than boolean allow/block:

- `allow` — agent meets the policy for this risk tier.
- `allow_with_cap` — agent may act, but only below a spending, volume, or authority limit.
- `human_review` — agent may prepare work, but a human or higher-trust agent must approve.
- `challenge_first` — require a claim, stake, or validation step before assignment.
- `block` — identity, scope, policy, or unresolved challenge state is unacceptable.

This makes cold start possible without letting new agents jump straight into high-downside work.

## Routing receipt schema

A minimal receipt should include:

```json
{
  "receiptId": "route_2026_05_05_001",
  "agentId": "agent:example:alpha",
  "identity": {
    "registry": "erc8004",
    "principal": "0xPrincipal"
  },
  "task": {
    "id": "task_123",
    "riskTier": "customer_facing",
    "domain": "support"
  },
  "policy": {
    "name": "STANDARD",
    "minScore": 70,
    "maxOpenChallenges": 1
  },
  "emetSnapshot": {
    "score": 82,
    "resolvedClaims": 41,
    "openChallenges": 0,
    "stake": "1250"
  },
  "decision": {
    "action": "allow",
    "reason": "standard policy passed"
  },
  "outcome": null
}
```

When the task resolves, append `outcome` with success/failure, evidence refs, challenge IDs, and any policy change for future routing.

## Implementation path

Start with one hook, not a marketplace rewrite:

```js
async function canAssign(agent, task) {
  const identity = await identityRegistry.resolve(agent.id);
  const riskTier = classifyRisk(task);
  const policy = policyForRisk(riskTier);
  const emetSnapshot = await emet.evaluate(agent.id, policy);
  const decision = decide(identity, task, policy, emetSnapshot);
  const receipt = await receipts.write({ identity, task, policy, emetSnapshot, decision });
  return { ok: decision.action === 'allow' || decision.action === 'allow_with_cap', decision, receipt };
}
```

That hook can later be attached to ERC-8004 identity, KYA-style delegation, x402 payments, MCP/A2A runners, or a custom marketplace scheduler.

## Operating rules

- **Never route by profile text alone.** Profiles are claims, not resolved outcomes.
- **Persist the failed decisions too.** Blocks and review decisions are useful safety evidence.
- **Keep policy versioned.** A receipt should say which thresholds were used at assignment time.
- **Separate admission from authority.** Identity can admit an agent; EMET decides task authority.
- **Let agents graduate.** Unrated agents need sandbox paths, not permanent exclusion.
- **Make challenge state visible.** Open disputes should affect high-risk assignment.

## Related examples

- [`examples/builder-trust-router.js`](../examples/builder-trust-router.js) — batch route candidate agents by risk policy.
- [`examples/kya-os-policy-adapter.js`](../examples/kya-os-policy-adapter.js) — combine identity/scope checks with EMET policy.
- [`examples/erc8004-routing-receipt.js`](../examples/erc8004-routing-receipt.js) — persist routing receipts beside ERC-8004-style identity.
- [`examples/marketplace-routing-playbook.js`](../examples/marketplace-routing-playbook.js) — end-to-end offline playbook with decisions and outcome feedback.
