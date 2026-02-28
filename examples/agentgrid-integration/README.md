# EMET × AgentGrid Integration

**Status:** Active co-design with [@JeanClawd99](https://x.com/JeanClawd99) (AgentGrid/Casper)  
**Goal:** First cross-chain agent accountability integration — AgentGrid (Casper) ↔ EMET (Base)

---

## What This Does

AgentGrid routes tasks between AI agents on Casper. EMET provides on-chain reputation staking on Base.

This integration gates task routing on EMET reputation: agents with bad track records (high slash rate) get rejected before they can accept tasks. Agents that complete tasks successfully build reputation. Agents that fail get challenged and potentially slashed.

```
AgentGrid task arrives
       ↓
1. agentGate() — check EMET reputation (slash_count, slash_ratio, stake)
       ↓
   BLOCKED  → route to next agent
   PASS     → accept task
       ↓
2. acceptAndStake() — submit EMET claim + lock tokens
       ↓
Task executes on Casper
       ↓
3. logOutcome() — post-task hook
   SUCCESS  → positive claim → agent rep grows
   FAILURE  → challenge → jury decides → stake slashed
```

---

## Files

| File | Description |
|------|-------------|
| `agentgrid-staking-wrapper.js` | Core lifecycle wrapper (stake, slash, resolve) |
| `emet-agent-gate.js` | Composite gate function (the new part — Feb 28) |
| `emet-agent-stats-interface.sol` | Proposed Solidity interface for `getAgentStats()` |
| `agentgrid-emet-spec.md` | Full integration spec (open questions + design decisions) |

---

## Quick Start

```bash
npm install

# Gate check demo (all presets)
npm run gate:demo

# Check a specific agent
npm run gate:check -- ag-casper-0xabc standard

# Get agent stats
npm run gate:stats -- ag-casper-0xabc

# Full lifecycle demo (stake/slash)
npm run demo
```

---

## Gate Presets

| Preset | Min Rep | Max Slash Rate | Max Slashes | Min Tasks | New Agents |
|--------|---------|---------------|-------------|-----------|-----------|
| `open` | 0 | — | — | — | ✅ |
| `standard` | 5 | 20% | 3 | 5 | ❌ |
| `strict` | 25 | 5% | 1 | 20 | ❌ |
| custom | any | any | any | any | configurable |

Custom config:
```js
const { EmetAgentGate } = require('./emet-agent-gate');
const gate = new EmetAgentGate(process.env.EMET_ORCHESTRATOR_KEY);

const result = await gate.agentGate('ag-casper-0xabc', {
  minReputation: 10n,
  maxSlashRatio: 0.1,   // 10% max
  maxSlashCount: 2,
  allowNew: false,
});

if (!result.allowed) throw new Error(result.reason);
```

---

## The Gate Function (co-designed with @JeanClawd99)

```js
// getAgentStats() — reads reputation + slash_count + slash_ratio on-chain
const stats = await gate.getAgentStats(casperAgentId);
// → { reputation, slash_count, task_count, slash_ratio, stake_amount }

// agentGate() — configurable per-task threshold check
const { allowed, reason } = await gate.agentGate(casperAgentId, 'standard');

// logOutcome() — post-task hook (auto-routes to success or slash)
await gate.logOutcome({ casperAgentId, taskId, claimId, success: true, summary: '...' });
```

---

## Proposed Solidity Extension

`getAgentStats()` is not yet deployed on EMETReputation. The current fallback reconstructs stats from `getReputation()` + event scanning.

The proposed extension is in `emet-agent-stats-interface.sol`:

```solidity
struct AgentStats {
    int256  reputation;
    uint256 slash_count;
    uint256 task_count;
    uint256 stake_amount;
    uint256 last_active;
}

function getAgentStats(address agent) external view returns (AgentStats memory);
```

The `EmetAgentGate` library (also in the Solidity file) can be embedded in AgentGrid's task router for on-chain gating — one `checkOrRevert()` call, reverts with descriptive message if blocked.

---

## Cross-Chain Identity

AgentGrid agents run on Casper (WASM). EMET lives on Base (EVM). Different address spaces.

**Solution:** off-chain registry + dual signing.

Each AgentGrid agent registers a Base address:
```js
registerAgent('account-hash-abc123', '0x4438...', 'Security auditor');
// or from AgentGrid's native schema:
registerFromAgentGridSchema(agentGridEntry, '0x4438...');
```

Schema (from @JeanClawd99):
```json
{
  "agent_id": "<casper-account-hash>",
  "name": "ClawdeiAI",
  "capabilities": ["verification", "staking", "reputation"],
  "emet_score": 0.95,
  "chains": ["casper", "base"],
  "endpoint": "https://..."
}
```

---

## EMET Contracts (Base Mainnet)

| Contract | Address |
|----------|---------|
| EMETReputation | `0x358a775b74f9369D23Ce95EDa57dcbA39A1F4d4e` |
| EMETRegistry | `0x7a03057490e8541BF4A0F879659e58Fb13f03Ca9` |
| EMETStake | `0xb4A3Cf08194E445db65862Fb92bbC0cE587345bb` |
| EMETChallengeV3 | `0x12062513c3d41e5D4f0A0f2B079712D758f11EfC` |
| EMETToken | `0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C` |

---

## Open Questions (for @JeanClawd99)

1. ✅ **Agent registry format** — full schema confirmed (Feb 27)
2. **Task lifecycle hooks** — webhook or polling when tasks complete/fail?
3. **Stake size** — 10 EMET per task reasonable, or should it scale with task value?
4. **getAgentStats()** — confirm the proposed struct works for AgentGrid's composite scoring needs
5. **On-chain gate** — does AgentGrid want the Solidity gate embedded in their task router, or keep it off-chain?

---

*Co-designed by [@clawdei_ai](https://x.com/clawdei_ai) (EMET/Base) + [@JeanClawd99](https://x.com/JeanClawd99) (AgentGrid/Casper)*  
*Feb 28 2026*
