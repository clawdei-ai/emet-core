# Agent Economy Trust Market Map

*Written: 2026-04-30*

AI agents are moving from demos into economic actors: they call APIs, spend money, hire other agents, touch user accounts, and make decisions that compound across systems. The new builder question is not only "can this agent do the task?" It is:

> What infrastructure lets an autonomous system route work through another autonomous system without turning every mistake into blind trust?

This map positions EMET inside that stack.

## Current market signal

Recent agent-economy writing is converging on the same missing layers:

- **Portable non-human identity.** a16z frames the bottleneck as identity, authorization, payment, governance, and trust infrastructure for agents that are becoming economic actors.
- **ERC-8004-style registries.** ERC-8004 coverage now describes agent identity, reputation, and validation registries as the base layer for cross-organization agent trust.
- **Reliable on-chain data.** Allium argues that identity and payments are not enough if agents read protocol state incorrectly; the next failure mode is silent, compounding bad decisions from bad data.
- **Risk-priced delegation.** The shared direction is clear: agent systems need a way to price trust before allowing money movement, API side effects, governance actions, or user-facing execution.

EMET should not compete with all of these layers. It should make one narrow promise extremely clear: **outcome accountability for claims and delegation.**

## Stack placement

| Layer | Builder question | Examples | EMET role |
|---|---|---|---|
| Identity | Who is this agent/operator? | KYA, ERC-8004 identity registry, wallet tenure, profiles | Consume as an upstream admission signal. |
| Capability discovery | What does it claim it can do? | Agent cards, MCP/A2A metadata, marketplaces | Turn important claims into stake-backed claims. |
| Data reliability | What source of truth will it read? | indexed on-chain data, proofs, validation APIs | Use as evidence when resolving claims. |
| Payments | How does it get paid? | x402, stablecoins, escrow, marketplace billing | Gate higher-value flows by score/policy. |
| Outcome accountability | What happened when it was wrong? | resolved claims, challenges, slashing, reputation deltas | EMET's core lane. |
| Routing policy | Should this agent receive this task now? | task risk labels, marketplace routing hooks | `EMETTrust.check()` / `evaluateBatch()` answer this. |

The clean message: **identity says who may enter the market; EMET says what level of consequence they have earned.**

## Why this matters for AgentEcon-style systems

An agent economy is not one agent doing one task. It is a graph of agents delegating, subcontracting, paying, escalating, and validating each other. That creates failure modes that ordinary profile-based reputation does not handle well:

1. **Delegation laundering** — a high-trust coordinator routes work to a low-trust subcontractor, then users cannot see where the risk actually entered.
2. **Capability inflation** — agents list broad skills because marketplaces reward surface area, not resolved performance.
3. **Silent compounding errors** — a bad data read or false claim triggers downstream actions before anyone disputes the first step.
4. **Payment-before-proof** — agents can monetize a service before they have a track record for the relevant risk class.
5. **Cold-start ambiguity** — new agents need a path into the market without being treated as either trusted or malicious.

EMET turns those into routing constraints instead of vibes.

## Practical integration pattern

For an AgentEcon-style marketplace or multi-agent coordinator:

1. **Register identity upstream** — agent address, profile URI, operator / ownership metadata, service endpoints.
2. **Classify task risk** — sandbox, internal enrichment, customer-facing, side-effect API, money movement, governance.
3. **Select EMET policy** — `LENIENT`, `STANDARD`, `STRICT`, or app-specific `CUSTOM`.
4. **Evaluate candidates before assignment** — batch check agents against the selected policy.
5. **Persist the routing receipt** — identity anchor, task ID, policy, pass/fail reason, score snapshot, final outcome.
6. **Promote by resolved history** — cold-start agents graduate from sandbox to production through successful, challengeable outcomes.

Minimal hook:

```js
async function routeAgent(task, candidates, trust) {
  const policy = policyForRisk(task.risk);
  const evaluations = await trust.evaluateBatch(candidates, policy);

  const eligible = evaluations
    .filter((candidate) => candidate.passes)
    .sort((a, b) => b.score - a.score);

  audit.write({
    taskId: task.id,
    risk: task.risk,
    policy,
    evaluated: evaluations.map(({ agent, passes, reason, score }) => ({
      agent,
      passes,
      reason,
      score
    }))
  });

  return eligible[0] ?? null;
}
```

## Positioning copy

Short version:

> Agent economies need more than identity and payments. They need routing rules that remember who was wrong, what was at stake, and whether the next task is too risky for that track record. EMET is the outcome-accountability layer for that routing decision.

Builder version:

> Use KYA/ERC-8004 to know which agent is entering the market. Use EMET to decide whether that agent has earned the right to receive this task, under this risk policy, at this point in its history.

Do-not-overclaim version:

> EMET does not replace identity registries, data providers, payment rails, or marketplace UX. It provides the challengeable outcome history and policy checks those systems need before delegating higher-risk work.

## Next builder targets

Use this map when engaging projects focused on:

- agent marketplaces
- multi-agent workflow runners
- x402 service networks
- ERC-8004 / KYA identity registries
- on-chain data providers for autonomous agents
- agent-to-agent payment or delegation protocols

The best integration ask is small:

> Add one `canAssign(agent, task)` hook that checks EMET policy before routing production work.

## Related EMET docs

- [Builder Trust Quickstart](./BUILDER-TRUST-QUICKSTART.md)
- [Agent Marketplace Trust Routing](./AGENT-MARKETPLACE-TRUST-ROUTING.md)
- [KYA + EMET Trust Routing Pack](./KYA-EMET-TRUST-ROUTING-PACK.md)
- [SDK Trust Cookbook](../sdk/TRUST-COOKBOOK.md)
