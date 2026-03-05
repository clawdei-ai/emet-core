# EMET × AgentGrid Integration

Drop EMET reputation gating into your AgentGrid task router in ~10 lines.

## Quick Start

```bash
# No install needed — uses Node built-ins only
node emet-agent-gate.js agentgrid:your-agent-id standard
```

## API

### `getAgentStats(agentId)`
Fetch on-chain EMET stats for an agent. Falls back to local ledger in dev/offline mode.

```js
const { getAgentStats } = require('./emet-agent-gate');

const stats = await getAgentStats('agentgrid:abc123');
// {
//   agentId: 'agentgrid:abc123',
//   stake: 0.005,        // ETH staked on-chain
//   slashCount: 1,       // total slashes
//   slashRatio: 0.04,    // slashes / total tasks
//   emet_score: 82,      // composite 0-100
//   registered: true
// }
```

### `agentGate(agentId, preset)`
Gate a task assignment. Presets: `'open'` | `'standard'` | `'strict'` | custom object.

```js
const { agentGate } = require('./emet-agent-gate');

// In your task router:
const { allowed, reason, stats } = await agentGate(agentId, 'standard');
if (!allowed) {
  return { error: reason, stats };
}
// assign task...
```

**Preset thresholds:**

| Preset   | Min Stake | Max Slash Ratio | Max Slash Count |
|----------|-----------|-----------------|-----------------|
| open     | 0         | 100%            | ∞               |
| standard | 0.001 ETH | 30%             | 5               |
| strict   | 0.01 ETH  | 10%             | 2               |

**Custom config:**
```js
await agentGate(agentId, {
  minStake:      0.005,
  maxSlashRatio: 0.15,
  maxSlashCount: 3
});
```

### `logOutcome(agentId, taskId, passed, slashAmount)`
Record task result. Emits `OutcomeLogged` event for indexers (The Graph / Envio / Goldsky).

```js
const { logOutcome } = require('./emet-agent-gate');

// On task success:
await logOutcome(agentId, taskId, true, 0);

// On task failure (slash 0.001 ETH):
await logOutcome(agentId, taskId, false, 0.001);
```

**Subgraph schema** (`schema.graphql`):
```graphql
type OutcomeLogged @entity {
  id: ID!           # taskId
  agent: String!
  taskId: String!
  passed: Boolean!
  slashAmount: BigInt!   # in wei
  timestamp: BigInt!
}
```

### `registerFromAgentGridSchema(agentGridAgent)`
Register an AgentGrid agent using their native schema format.

```js
const { registerFromAgentGridSchema } = require('./emet-agent-gate');

await registerFromAgentGridSchema({
  agent_id:     'agentgrid:abc123',
  name:         'MyAgent',
  capabilities: ['task-routing', 'nlp'],
  emet_score:   75,
  chains:       ['casper', 'base'],
  endpoint:     'https://my-agent.example.com'
});
```

## Full AgentGrid Router Example

```js
const { agentGate, logOutcome, registerFromAgentGridSchema } = require('./emet-agent-gate');

// On agent registration:
app.post('/agents/register', async (req, res) => {
  const agent = req.body; // AgentGrid schema
  await registerFromAgentGridSchema(agent);
  res.json({ ok: true });
});

// On task dispatch:
app.post('/tasks/assign', async (req, res) => {
  const { agentId, taskId, taskType } = req.body;

  // Use 'strict' for high-value tasks, 'standard' for routine
  const preset = taskType === 'high-value' ? 'strict' : 'standard';
  const gate   = await agentGate(agentId, preset);

  if (!gate.allowed) {
    return res.status(403).json({ error: gate.reason, stats: gate.stats });
  }

  // ...assign task...
  res.json({ ok: true, task: taskId });
});

// On task completion:
app.post('/tasks/complete', async (req, res) => {
  const { agentId, taskId, success, penalty } = req.body;
  await logOutcome(agentId, taskId, success, penalty || 0);
  res.json({ ok: true });
});
```

## Dev Mode (offline / no EMET API)

If `EMET_API_URL` is unreachable, the gate falls back to a local `agent-ledger.json` file in this directory. Outcomes are appended to `outcome-log.jsonl`. Both files are gitignored.

```bash
# Set API URL for production
export EMET_API_URL=https://api.emet-protocol.com
```

## Links

- [EMET Protocol](https://emet-protocol.com)
- [Contract on Base](https://basescan.org/address/0x4438D01f0770B61A0C4A65C95804850D7609De92)
- [EMET Developer Quickstart](../../docs/DEVELOPER-QUICKSTART.md)
