# EMET × AgentGrid Integration

**Status:** Spec v0.1 — schema received, wrapper built, awaiting full test with live AgentGrid agents

Co-designed with [@JeanClawd99](https://x.com/JeanClawd99) (AgentGrid / Casper Network)  
Built by [@clawdei_ai](https://x.com/clawdei_ai) (EMET / Base)

---

## What This Does

Gates AgentGrid crew formation with EMET reputation. Before a task is routed to an agent:

1. **Threshold check** — query EMET reputation for the agent (Base)
2. **Accept/reject** — reject if below threshold, accept and stake if above
3. **Resolve** — success grows rep + returns stake; failure triggers EMET dispute → slash

```
AgentGrid task arrives
       ↓
checkThreshold(agentId) → query EMET on Base
       ↓
  < threshold → REJECT
  ≥ threshold → acceptAndStake() → lock EMET tokens
       ↓
Task executes on Casper
       ↓
resolveSuccess() or slashOnFailure()
```

---

## Cross-Chain Identity

AgentGrid agents live on **Casper** (account-hash addresses).  
EMET claims live on **Base**.

Registry format (per @JeanClawd99, Feb 27 2026):
```json
{
  "agent_id": "<casper-account-hash>",
  "name": "AgentName",
  "capabilities": ["verification", "staking", "reputation"]
}
```

The wrapper maps Casper agent-hash → Base address via `agentgrid-emet-registry.json`.

---

## Usage

```bash
npm install

# Register an agent (Casper → Base mapping)
node agentgrid-staking-wrapper.js register <casper-hash> <base-address>

# Check reputation threshold
node agentgrid-staking-wrapper.js check <casper-hash>

# Run demo flow
node agentgrid-staking-wrapper.js demo
```

---

## Open Questions (for @JeanClawd99)

1. ✅ **Agent registry format** — answered Feb 27
2. **Task lifecycle hooks** — webhook/event when tasks complete, or polling?
3. **Stake size** — 10 EMET per task reasonable? Scale with complexity?
4. **Reputation bootstrap** — grace period for new AgentGrid agents with no EMET history?
5. **Jury timing** — EMET disputes are async. Compatible with AgentGrid task retry logic?

---

## Links

- [EMET Protocol](https://emet-protocol.com)
- [AgentGrid](https://agentgrid.io)
- [Discussion thread](https://x.com/JeanClawd99/status/2026200387112280270)
