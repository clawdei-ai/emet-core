#!/usr/bin/env node
/**
 * EMET Agent Gate — AgentGrid Integration
 *
 * Drop this into your AgentGrid task router to gate task assignment
 * based on on-chain EMET reputation. Three presets + custom config.
 *
 * Usage:
 *   const { agentGate, getAgentStats, logOutcome } = require('./emet-agent-gate');
 *
 *   // Before assigning a task:
 *   const { allowed, reason, stats } = await agentGate(agentId, 'standard');
 *   if (!allowed) return rejectTask(reason);
 *
 *   // After task completes:
 *   await logOutcome(agentId, taskId, passed, slashAmount);
 *
 * On-chain data source: EMET Protocol on Base
 * Contract: https://basescan.org/address/0x4438D01f0770B61A0C4A65C95804850D7609De92
 */

const https = require('https');

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const EMET_API = process.env.EMET_API_URL || 'https://api.emet-protocol.com';
const BASE_RPC  = process.env.BASE_RPC_URL  || 'https://mainnet.base.org';

// Gate presets
const PRESETS = {
  open: {
    minStake:      0,
    maxSlashRatio: 1.0,
    maxSlashCount: Infinity,
    description:   'No restrictions — any registered agent passes'
  },
  standard: {
    minStake:      0.001,   // ETH equivalent staked on-chain
    maxSlashRatio: 0.30,    // max 30% of tasks resulted in slash
    maxSlashCount: 5,       // hard cap on total slashes
    description:   'Balanced — filters out consistently bad actors'
  },
  strict: {
    minStake:      0.01,
    maxSlashRatio: 0.10,
    maxSlashCount: 2,
    description:   'High-value tasks — only well-staked, low-slash agents'
  }
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function httpsGet(url) {
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch (e) { reject(new Error(`Parse error: ${e.message} | body: ${data.slice(0, 200)}`)); }
      });
    }).on('error', reject);
  });
}

function httpsPost(url, body) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify(body);
    const urlObj  = new URL(url);
    const options = {
      hostname: urlObj.hostname,
      path:     urlObj.pathname + urlObj.search,
      method:   'POST',
      headers:  { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) }
    };
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch (e) { reject(new Error(`Parse error: ${e.message}`)); }
      });
    });
    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

// ---------------------------------------------------------------------------
// getAgentStats
// ---------------------------------------------------------------------------

/**
 * Fetch an agent's on-chain EMET stats.
 *
 * Returns:
 *   { agentId, stake, slashCount, slashRatio, emet_score, registered }
 */
async function getAgentStats(agentId) {
  try {
    // Try EMET REST API first (faster, cached)
    const data = await httpsGet(`${EMET_API}/v1/agents/${encodeURIComponent(agentId)}/stats`);
    return {
      agentId,
      stake:      data.stake      ?? 0,
      slashCount: data.slash_count ?? 0,
      slashRatio: data.slash_ratio ?? 0,
      emet_score: data.emet_score  ?? 0,
      registered: true,
      source:     'api'
    };
  } catch (_) {
    // Fallback: local tracking file (dev/offline mode)
    try {
      const fs   = require('fs');
      const path = require('path');
      const ledgerPath = path.join(__dirname, 'agent-ledger.json');
      if (fs.existsSync(ledgerPath)) {
        const ledger = JSON.parse(fs.readFileSync(ledgerPath, 'utf8'));
        const entry  = ledger[agentId];
        if (entry) {
          const slashRatio = entry.taskCount > 0
            ? entry.slashCount / entry.taskCount
            : 0;
          return {
            agentId,
            stake:      entry.stake      || 0,
            slashCount: entry.slashCount || 0,
            slashRatio,
            emet_score: entry.emet_score || 0,
            registered: true,
            source:     'local-ledger'
          };
        }
      }
    } catch (_) { /* ignore */ }

    // Unknown agent — not registered
    return {
      agentId,
      stake:      0,
      slashCount: 0,
      slashRatio: 0,
      emet_score: 0,
      registered: false,
      source:     'fallback'
    };
  }
}

// ---------------------------------------------------------------------------
// agentGate
// ---------------------------------------------------------------------------

/**
 * Decide whether an agent should be allowed to handle a task.
 *
 * @param {string} agentId    - Agent identifier (e.g. 'agentgrid:abc123')
 * @param {string|object} preset - 'open' | 'standard' | 'strict' | custom config object
 *
 * @returns {{ allowed: boolean, reason: string, stats: object, config: object }}
 */
async function agentGate(agentId, preset = 'standard') {
  const config = typeof preset === 'string'
    ? PRESETS[preset] || PRESETS.standard
    : preset;

  const stats = await getAgentStats(agentId);

  // Not registered at all
  if (!stats.registered && config.minStake > 0) {
    return {
      allowed: false,
      reason:  `Agent ${agentId} has no EMET reputation record`,
      stats,
      config
    };
  }

  // Stake check
  if (stats.stake < config.minStake) {
    return {
      allowed: false,
      reason:  `Insufficient stake: ${stats.stake} ETH < required ${config.minStake} ETH`,
      stats,
      config
    };
  }

  // Slash count hard cap
  if (stats.slashCount > config.maxSlashCount) {
    return {
      allowed: false,
      reason:  `Too many slashes: ${stats.slashCount} > limit ${config.maxSlashCount}`,
      stats,
      config
    };
  }

  // Slash ratio check
  if (stats.slashRatio > config.maxSlashRatio) {
    return {
      allowed: false,
      reason:  `Slash ratio too high: ${(stats.slashRatio * 100).toFixed(1)}% > limit ${(config.maxSlashRatio * 100).toFixed(1)}%`,
      stats,
      config
    };
  }

  return {
    allowed: true,
    reason:  `Passed ${typeof preset === 'string' ? preset : 'custom'} gate`,
    stats,
    config
  };
}

// ---------------------------------------------------------------------------
// logOutcome — post-task slash routing
// ---------------------------------------------------------------------------

/**
 * Record a task outcome. Emits OutcomeLogged for indexers.
 *
 * @param {string}  agentId     - Agent identifier
 * @param {string}  taskId      - Task/job identifier from AgentGrid
 * @param {boolean} passed      - true = success, false = failure/slash
 * @param {number}  slashAmount - Amount slashed (0 if passed)
 *
 * Subgraph schema suggestion:
 *   type OutcomeLogged @entity {
 *     id: ID!                    # taskId
 *     agent: String!
 *     taskId: String!
 *     passed: Boolean!
 *     slashAmount: BigInt!
 *     timestamp: BigInt!
 *   }
 */
async function logOutcome(agentId, taskId, passed, slashAmount = 0) {
  const event = {
    event:        'OutcomeLogged',
    agent:        agentId,
    taskId,
    passed,
    slashAmount:  BigInt(Math.round(slashAmount * 1e18)).toString(), // wei
    timestamp:    Math.floor(Date.now() / 1000)
  };

  // Emit to EMET API (for indexers / The Graph / Envio)
  try {
    await httpsPost(`${EMET_API}/v1/outcomes`, event);
  } catch (err) {
    // Non-fatal — log locally if API unreachable
    const fs   = require('fs');
    const path = require('path');
    const log  = path.join(__dirname, 'outcome-log.jsonl');
    fs.appendFileSync(log, JSON.stringify(event) + '\n');
  }

  // Update local ledger (dev mode)
  try {
    const fs         = require('fs');
    const path       = require('path');
    const ledgerPath = path.join(__dirname, 'agent-ledger.json');
    const ledger     = fs.existsSync(ledgerPath)
      ? JSON.parse(fs.readFileSync(ledgerPath, 'utf8'))
      : {};

    if (!ledger[agentId]) {
      ledger[agentId] = { taskCount: 0, slashCount: 0, stake: 0, emet_score: 50 };
    }

    ledger[agentId].taskCount++;
    if (!passed) {
      ledger[agentId].slashCount++;
      // Simple score decay on slash
      ledger[agentId].emet_score = Math.max(0, ledger[agentId].emet_score - 10);
    } else {
      // Slow score recovery on success
      ledger[agentId].emet_score = Math.min(100, ledger[agentId].emet_score + 1);
    }

    fs.writeFileSync(ledgerPath, JSON.stringify(ledger, null, 2));
  } catch (_) { /* ignore in prod */ }

  return event;
}

// ---------------------------------------------------------------------------
// registerFromAgentGridSchema — register an AgentGrid agent with EMET
// ---------------------------------------------------------------------------

/**
 * Register an AgentGrid agent using their native schema format.
 *
 * AgentGrid schema:
 *   { agent_id, name, capabilities[], emet_score, chains[], endpoint }
 */
async function registerFromAgentGridSchema(agentGridAgent) {
  const { agent_id, name, capabilities = [], chains = [], endpoint } = agentGridAgent;

  const registration = {
    agentId:      agent_id,
    name,
    capabilities,
    chains,
    endpoint,
    registeredAt: new Date().toISOString(),
    protocol:     'emet-v1'
  };

  try {
    const result = await httpsPost(`${EMET_API}/v1/agents/register`, registration);
    return { success: true, agentId: agent_id, emetId: result.emetId, ...result };
  } catch (err) {
    // Fallback: write to local ledger
    const fs         = require('fs');
    const path       = require('path');
    const ledgerPath = path.join(__dirname, 'agent-ledger.json');
    const ledger     = fs.existsSync(ledgerPath)
      ? JSON.parse(fs.readFileSync(ledgerPath, 'utf8'))
      : {};

    if (!ledger[agent_id]) {
      ledger[agent_id] = {
        taskCount:  0,
        slashCount: 0,
        stake:      0,
        emet_score: agentGridAgent.emet_score || 50,
        name,
        capabilities,
        chains,
        endpoint
      };
      fs.writeFileSync(ledgerPath, JSON.stringify(ledger, null, 2));
    }
    return { success: true, agentId: agent_id, source: 'local-ledger' };
  }
}

// ---------------------------------------------------------------------------
// Exports
// ---------------------------------------------------------------------------

module.exports = { getAgentStats, agentGate, logOutcome, registerFromAgentGridSchema, PRESETS };

// ---------------------------------------------------------------------------
// CLI demo
// ---------------------------------------------------------------------------

if (require.main === module) {
  (async () => {
    const agentId = process.argv[2] || 'agentgrid:demo-agent-001';
    const preset  = process.argv[3] || 'standard';

    console.log(`\n⚡ EMET Agent Gate Demo\n`);
    console.log(`Agent:  ${agentId}`);
    console.log(`Preset: ${preset}\n`);

    const stats = await getAgentStats(agentId);
    console.log('Stats:', stats);

    const gate = await agentGate(agentId, preset);
    console.log('\nGate result:', gate.allowed ? '✅ ALLOWED' : '❌ BLOCKED');
    console.log('Reason:', gate.reason);

    if (gate.allowed) {
      const outcome = await logOutcome(agentId, `task-${Date.now()}`, true, 0);
      console.log('\nLogged outcome:', outcome);
    }
  })().catch(console.error);
}
