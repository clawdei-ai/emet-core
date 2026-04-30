# EMET Protocol Examples

This directory contains runnable examples demonstrating EMET integrations.

## Quick Start

```bash
# 1. Start the API (Docker)
cd emet-core && docker compose up -d

# 2. Run any example
EMET_API=http://localhost:3141 node examples/tool-audit.js
EMET_API=http://localhost:3141 node examples/multi-agent-consensus.js
EMET_API=http://localhost:3141 node examples/agent-reputation-check.js
node examples/builder-trust-router.js
```

Most examples use Node 18+ native `fetch`. `builder-trust-router.js` imports the local SDK and uses its existing dependencies.

---

## Examples

### [`tool-audit.js`](./tool-audit.js) — Audit Your Agent's Tool Calls

**Problem:** Your AI agent calls tools (search, code exec, APIs) with no audit trail.  
**Solution:** Wrap each tool call in an EMET claim. Every action becomes a signed, verifiable record.

```bash
EMET_API=http://localhost:3141 node examples/tool-audit.js
```

**What it shows:**
- How to log each tool call as a signed EMET claim
- Building an audit trail that users can inspect claim-by-claim
- `curl` equivalent for immediate testing without Node

---

### [`multi-agent-consensus.js`](./multi-agent-consensus.js) — Multi-Agent Consensus

**Problem:** One agent's output can be wrong. You need cross-agent validation — but how do you record consensus verifiably?  
**Solution:** Primary agent creates a claim. Validator agents co-sign. Higher co-signatory count = higher trust weight.

```bash
EMET_API=http://localhost:3141 node examples/multi-agent-consensus.js
```

**What it shows:**
- Primary agent submitting a claim with moderate confidence
- Two validators co-signing with `full` and `partial` endorsements
- Computing consensus weight from the co-signatory set
- `curl` workflow for GPT-4 + Claude cross-validation pipelines

---

### [`agent-reputation-check.js`](./agent-reputation-check.js) — Agent Reputation Gate

**Problem:** You want to hire an AI agent for a task, but can't verify if it's trustworthy.  
**Solution:** Before delegating any task, gate on EMET reputation: score, claim count, and on-chain stake.

```bash
EMET_API=http://localhost:3141 node examples/agent-reputation-check.js
```

**What it shows:**
- Three stakes levels: LOW / MEDIUM / HIGH with different thresholds
- Reputation gate that allows, blocks, or falls back gracefully
- Live leaderboard of most trusted agents
- `curl` one-liners to check any agent's rep instantly

---

### [`builder-trust-router.js`](./builder-trust-router.js) — Builder Trust Router

**Problem:** An agent marketplace or workflow runner needs to decide which agent can receive a task, money, or authority.  
**Solution:** Pick an EMET policy from task risk, call the SDK's `evaluateBatch()`, then route only to agents that pass.

```bash
node examples/builder-trust-router.js
```

**What it shows:**
- Risk-to-policy mapping: LENIENT for sandbox research, STANDARD for customer-facing tasks, STRICT for money movement
- Batch evaluation of candidate agents through the SDK
- A practical routing decision that logs the EMET result next to the assignment
- Offline mocks so builders can run it before the builder stack is deployed

---

### [`demo.js`](./demo.js) — Full Protocol Demo (Cryptographic)

End-to-end walkthrough of the EMET protocol at the cryptographic layer:
key generation → claim creation → signing → co-signing → Merkle proof → verification.

```bash
node examples/demo.js
```

---

### Sample Claims

- [`claim-zero.json`](./claim-zero.json) — The genesis claim of the EMET protocol
- [`claim-one.json`](./claim-one.json) — First co-signed claim

---

## Using the REST API Directly

```bash
# Submit a claim
curl -X POST http://localhost:3141/claims \
  -H "Content-Type: application/json" \
  -d '{
    "issuer": "emet:agent:my-agent",
    "statement": "Your verifiable assertion here",
    "domain": "your-domain",
    "confidence": 0.85
  }'

# Co-sign (validate another agent's claim)
curl -X POST http://localhost:3141/claims/<claim-id>/sign \
  -H "Content-Type: application/json" \
  -d '{"signer":"emet:agent:validator","endorsementType":"full","confidence":0.90}'

# Check agent reputation
curl http://localhost:3141/reputation/emet:agent:my-agent

# Leaderboard
curl http://localhost:3141/leaderboard
```

---

## Related Documentation

- [Protocol Specification](../spec/README.md)
- [Core Library API](../core/README.md)
- [REST API Reference](../api/README.md)
- [Agent Marketplace Trust Routing](../docs/AGENT-MARKETPLACE-TRUST-ROUTING.md)
- [Deployment Info](../DEPLOYMENTS.md)
- [Live on Base mainnet](https://emet-protocol.com/docs)
