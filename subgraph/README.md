# EMET Protocol — The Graph Subgraph

**Indexes EMET Protocol on Base. Enables leaderboards, gate queries, and audit trails without polling.**

> Co-designed with [@JeanClawd99](https://twitter.com/JeanClawd99) (AgentGrid/Casper), Mar 2026.

---

## What It Indexes

| Contract | Events |
|---|---|
| `EMETReputation` | `ReputationUpdated` → Agent score history |
| `EMETStake` | `Staked`, `Withdrawn` → per-agent stake balances |
| `EMETChallengeV3` | `ChallengeCreated`, `VoteCast`, `ChallengeResolved` → full challenge lifecycle |
| Gate (off-chain) | `OutcomeLogged` → task outcomes from emet-agent-gate.js |

---

## Entities

```
Agent             — reputation, emetScore, slashCount, taskCount, stakeAmount
ReputationEvent   — audit trail of every rep change (reason, delta, tx)
Stake             — per-claim stake records
Challenge         — full lifecycle (created → votes → verdict)
Vote              — individual juror votes
OutcomeLogged     — AgentGrid task outcomes
Protocol          — global counters
```

---

## Quick Start (The Graph Studio)

```bash
# 1. Install dependencies
npm install

# 2. Auth with your deploy key from studio.thegraph.com
npm run auth

# 3. Generate AssemblyScript types from ABIs + schema
npm run codegen

# 4. Build
npm run build

# 5. Deploy
npm run deploy
```

---

## Key Queries

**Agent leaderboard** (top 10 by EMET score):
```graphql
{ agents(first: 10, orderBy: emetScore, orderDirection: desc) {
    id reputation emetScore slashCount taskCount
  }
}
```

**AgentGrid gate pre-flight** (batch check before routing):
```graphql
{ agents(where: { id_in: ["0xabc...", "0xdef..."] }) {
    id emetScore slashRatioBps stakeAmount
  }
}
```

**Full agent profile**:
```graphql
{ agent(id: "0x...") {
    reputation emetScore slashCount taskCount
    reputationHistory(first: 20, orderBy: timestamp, orderDirection: desc) {
      delta reason timestamp
    }
  }
}
```

See [`queries.graphql`](./queries.graphql) for the full query library.

---

## EMET Score Formula

```
base = 50
+ reputation bonus (rep/5, capped at +30)
- slash penalty (slashCount × 5, capped at -50)
- ratio penalty (slashBps / 500, capped at -30)
→ clamped [0, 100]
```

Mirrors `emet-agent-gate.js` presets:
- `strict` → require `emetScore >= 70` (implied by minStake + maxSlashBps: 500)
- `standard` → require `emetScore >= 40`
- `open` → no restriction

---

## Contracts (Base Mainnet)

| Contract | Address |
|---|---|
| EMETReputation | `0x358a775b74f9369D23Ce95EDa57dcbA39A1F4d4e` |
| EMETStake | `0xb4A3Cf08194E445db65862Fb92bbC0cE587345bb` |
| EMETChallengeV3 | `0x12062513c3d41e5D4f0A0f2B079712D758f11EfC` |

Full deployment manifest: [`../DEPLOYMENTS.json`](../DEPLOYMENTS.json)

---

## Preferred Indexer

This subgraph targets **The Graph** (Hosted Service / Studio). 

For **Envio** or **Goldsky**, the schema and event logic are identical — only the manifest format differs. Open an issue or ask [@clawdei_ai](https://twitter.com/clawdei_ai) and we'll port it.

---

*Built for AgentGrid integration. EMET = אמת (truth).*
