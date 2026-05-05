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
node examples/kya-os-policy-adapter.js
node examples/erc8004-routing-receipt.js
node examples/marketplace-routing-playbook.js
```

Most examples use Node 18+ native `fetch`. `builder-trust-router.js` imports the local SDK and uses its existing dependencies. `kya-os-policy-adapter.js`, `erc8004-routing-receipt.js`, and `marketplace-routing-playbook.js` are fully offline and use mock identity/EMET objects.

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

### [`kya-os-policy-adapter.js`](./kya-os-policy-adapter.js) — KYA-OS ↔ EMET Policy Adapter

**Problem:** KYA-OS can verify who authorized an agent and what scope it has, but a marketplace still needs to decide what risk tier the agent has earned.  
**Solution:** Verify KYA identity/scope first, map task risk to an EMET policy, then write a routing receipt for the decision.

```bash
node examples/kya-os-policy-adapter.js
```

**What it shows:**
- KYA-style identity, delegation scope, revocation, and conformance checks
- EMET policy mapping for customer-facing and money-movement tasks
- `allow`, `allow_with_cap`, `human_review`, `challenge_first`, and `block` style routes
- Durable policy receipts that can later be connected to task outcomes and challenges

---

### [`marketplace-routing-playbook.js`](./marketplace-routing-playbook.js) — Agent Marketplace Routing Playbook

**Problem:** A marketplace needs an operator-friendly way to route agents into sandbox, customer-facing, privileged, or financial tasks.  
**Solution:** Resolve identity, classify task risk, evaluate EMET-style evidence, return a rich routing decision, and persist a receipt with outcome feedback.

```bash
node examples/marketplace-routing-playbook.js
```

**What it shows:**
- Risk tiers from sandbox through financial workflows
- `allow`, `allow_with_cap`, `human_review`, `challenge_first`, and `block` decisions
- Cold-start handling without letting unrated agents touch production authority
- Routing receipts that later receive outcome feedback

---

### [`erc8004-routing-receipt.js`](./erc8004-routing-receipt.js) — ERC-8004 × EMET Routing Receipts

**Problem:** ERC-8004 can anchor agent identity/reputation/validation, but an app still needs to decide whether a specific agent can receive a specific risky task.  
**Solution:** Resolve identity, map task risk to an EMET policy, evaluate outcome history, and persist a routing receipt before assignment.

```bash
node examples/erc8004-routing-receipt.js
```

**What it shows:**
- Active/inactive ERC-8004-style identity checks
- Risk-tier policy mapping for customer-facing, money-movement, and governance tasks
- `allow`, `human_review`, `challenge_first`, and `block` routing decisions
- Receipts that preserve identity, task risk, trust inputs, decision reason, and assignment state

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
