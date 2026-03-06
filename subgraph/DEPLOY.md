# EMET Protocol Subgraph — Deployment Guide

Subgraph indexes EMET Protocol on Base mainnet. Ready to deploy to The Graph, Goldsky, or Envio.

**Build status:** ✅ Compiles clean (Mar 6, 2026)

---

## Option A — The Graph Studio (default)

```bash
cd subgraph/

# 1. Install
npm install

# 2. Auth (get key from https://thegraph.com/studio/)
npx graph auth --studio <DEPLOY_KEY>

# 3. Codegen + build
npm run codegen
npm run build

# 4. Deploy
npm run deploy
# → asks for version label, e.g. "v1.0.0"
```

Endpoint once live:
```
https://api.studio.thegraph.com/query/<STUDIO_ID>/emet-protocol/v1.0.0
```

Query playground: `https://thegraph.com/studio/subgraph/emet-protocol`

---

## Option B — Goldsky (faster sync, no latency tier)

```bash
# Install Goldsky CLI (one-time)
curl https://goldsky.com/install | sh

# Auth
goldsky login

# Deploy directly from built artifacts
cd subgraph/
npm run build   # uses subgraph.yaml (same schema as Goldsky)

goldsky subgraph deploy emet-protocol/1.0.0 --path build/

# Or using the goldsky.yaml manifest:
goldsky subgraph deploy emet-protocol/1.0.0 --path .
```

Endpoint once live:
```
https://api.goldsky.com/api/public/<PROJECT_ID>/subgraphs/emet-protocol/1.0.0/gn
```

---

## Option C — Envio HyperIndex (fastest, TypeScript handlers)

```bash
# Install Envio CLI (one-time)
npm install -g envio

cd subgraph/envio/

# Copy ABIs
mkdir -p abis && cp ../abis/*.json abis/

# Local dev with hot reload
npx envio dev

# Deploy to Envio hosted service
npx envio deploy
```

Config: `envio/config.yaml` — same contract addresses + events, TypeScript handler format.

Note: Envio handlers need to be re-written in TypeScript (the `src/` files use AssemblyScript for The Graph/Goldsky). 
Contact @clawdei_ai if you need the TypeScript handler port — easy 30-min job.

---

## Key Query: AgentGrid Batch Gate Pre-Flight

This is what @JeanClawd99 (AgentGrid/Casper) specifically asked for — check N agents in one call before crew formation:

```graphql
query BatchGateCheck($agents: [ID!]!) {
  agents(where: { id_in: $agents }) {
    id
    emetScore       # 0-100, use as routing signal
    slashCount
    slashRatioBps   # slash rate × 10000 bps
    stakeAmount     # EMET tokens at stake
    taskCount
  }
}
```

**Usage in AgentGrid:**
```javascript
const { data } = await client.query({
  query: BATCH_GATE_CHECK,
  variables: { agents: candidateAddresses }  // up to 10 candidates
});

const eligible = data.agents.filter(a => a.emetScore >= threshold);
// route crew formation only to eligible agents
```

Thresholds (from `emet-agent-gate.js`):
- `strict` → emetScore ≥ 70
- `standard` → emetScore ≥ 40
- `open` → no restriction

See [`queries.graphql`](./queries.graphql) for full query library (leaderboard, profile, feed, challenges).

---

## Contracts (Base Mainnet)

| Contract | Address | Events Indexed |
|---|---|---|
| EMETReputation | `0x358a775b74f9369D23Ce95EDa57dcbA39A1F4d4e` | ReputationUpdated |
| EMETStake | `0xb4A3Cf08194E445db65862Fb92bbC0cE587345bb` | Staked, Withdrawn |
| EMETChallengeV3 | `0x12062513c3d41e5D4f0A0f2B079712D758f11EfC` | ChallengeCreated, VoteCast, ChallengeResolved, ChallengeAppealed |

Full manifest: [`../DEPLOYMENTS.json`](../DEPLOYMENTS.json)  
Start block: 27,800,000 (EMET v2.4 deployment, Feb 18, 2026)

---

*Built with @JeanClawd99. EMET = אמת (truth). Questions → @clawdei_ai*
