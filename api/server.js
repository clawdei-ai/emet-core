#!/usr/bin/env node
/**
 * EMET Protocol — REST API Server
 *
 * A minimal Express server that wraps @emet-protocol/core and exposes
 * claim lifecycle operations over HTTP. Now with SQLite persistence!
 *
 * Usage:
 *   cd api && npm install && npm start
 *
 * Default port: 3141 (override with PORT env var)
 * 
 * @version 0.6.0
 */

const express = require('express');
const cors = require('cors');
const emet = require('../core');
const store = require('./store');
const reputation = require('./db/reputation');
const { resolveOnChain } = require('./onchain');
const { trustCache } = require('./trust-cache');
const { buildAgentProfile, checkStakeFloor } = require('./agent-profile');

const app = express();
const PORT = process.env.PORT || 3141;

// ─── Trust gate config (The Synthesis demo defaults) ─────────────────────────
const TRUST_THRESHOLDS = {
  strict:   { minScore: 70, maxSlashRate: 0.05, minClaims: 10 },
  standard: { minScore: 50, maxSlashRate: 0.15, minClaims: 3  },
  lenient:  { minScore: 30, maxSlashRate: 0.30, minClaims: 1  },
};

// Simulated on-chain reputation snapshots (used when SUBGRAPH_URL not set)
// Mirrors the data in synthesis-demo.js for consistent judge experience
const SIMULATION_AGENTS = {
  'emet:agent:alpha:4f2f7756': {
    emetScore: 78, slashCount: 1, slashRatioBps: 420, taskCount: 24,
    stakeAmount: '8200000000000000', firstSeen: '2023-11-14', lastActive: '2026-03-15',
    label: 'ALPHA (Predictor) — high-reputation agent, consistent track record'
  },
  'emet:agent:gamma:a5a671a3': {
    emetScore: 22, slashCount: 4, slashRatioBps: 3300, taskCount: 12,
    stakeAmount: '500000000000000', firstSeen: '2025-12-01', lastActive: '2026-03-14',
    label: 'GAMMA (Bad Actor) — high slash rate, untrustworthy'
  },
  'emet:agent:epsilon:c2d91e04': {
    emetScore: 50, slashCount: 0, slashRatioBps: 0, taskCount: 0,
    stakeAmount: '0', firstSeen: '2026-03-15', lastActive: '2026-03-15',
    label: 'EPSILON (Fresh Agent) — no history yet, baseline trust'
  },
};

// ---------------------------------------------------------------------------
// Middleware
// ---------------------------------------------------------------------------
app.use(cors());
app.use(express.json());

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Validate required fields on a request body. */
function requireFields(body, fields) {
  const missing = fields.filter(f => body[f] === undefined);
  if (missing.length) {
    return `Missing required fields: ${missing.join(', ')}`;
  }
  return null;
}

// In-memory Merkle tree (rebuilt whenever needed)
let treeCache = null;

/** Rebuild the Merkle tree from all stored claims. */
function rebuildTree() {
  const claims = store.list();
  if (claims.length === 0) {
    treeCache = null;
    return null;
  }
  treeCache = emet.merkle.buildTreeFromClaims(claims, emet.hashClaim);
  return treeCache;
}

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

// Health check
app.get('/', (_req, res) => {
  const schemaVersion = store.getSchemaVersion();
  res.json({
    name: '@emet-protocol/api',
    version: '0.7.0',
    storage: 'sqlite',
    schemaVersion,
    chain: 'Base mainnet (chainId: 8453)',
    hackathon: 'The Synthesis 2026 — Agents that Trust',
    endpoints: [
      'POST   /claims',
      'GET    /claims',
      'GET    /claims/:id',
      'POST   /claims/:id/sign',
      'POST   /verify',
      'GET    /tree',
      'POST   /tree/prove',
      'GET    /reputation/:agentId',
      'GET    /leaderboard',
      'POST   /trust-gate              (v2: mode=fast|slow|auto, accuracyScore, riskAppetite, stakeFloor)',
      'POST   /trust-gate/invalidate   (v2: invalidate cache on slash event)',
      'GET    /trust-gate/cache/stats  (v2: cache observability)',
      'GET    /synthesis',
    ],
    v2Features: [
      'fast/slow trust path (mode param: fast|slow|auto)',
      'accuracyScore separated from legacy blended score',
      'riskAppetite classification (low/medium/high)',
      'stake floor enforcement by requester tier',
      'slash-event cache invalidation endpoint',
    ],
  });
});

// ---- Claims ---------------------------------------------------------------

/**
 * POST /claims — Create a new claim.
 *
 * Body: { issuer, statement, type?, domain?, scope?, caveats?, evidence?, confidence? }
 * Returns: the created (unsigned) claim.
 */
app.post('/claims', (req, res) => {
  try {
    const err = requireFields(req.body, ['issuer', 'statement']);
    if (err) return res.status(400).json({ error: err });

    const claim = emet.createClaim(req.body);
    store.put(claim);
    
    // Record claim for reputation tracking
    reputation.recordClaim(req.body.issuer, claim.id);
    
    treeCache = null; // invalidate

    res.status(201).json(claim);
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

/**
 * GET /claims — List all claims (optional).
 * 
 * Query params:
 *   - issuer: Filter by issuer
 *   - type: Filter by claim type
 *   - limit: Maximum results
 *   - offset: Pagination offset
 */
app.get('/claims', (req, res) => {
  const options = {};
  if (req.query.issuer) options.issuer = req.query.issuer;
  if (req.query.type) options.type = req.query.type;
  if (req.query.limit) options.limit = parseInt(req.query.limit, 10);
  if (req.query.offset) options.offset = parseInt(req.query.offset, 10);
  
  res.json(store.list(options));
});

/**
 * GET /claims/:id — Retrieve a claim by its full EMET id.
 *
 * The :id param is the UUID portion; we prepend "emet:claim:" automatically
 * if the caller omits it.
 */
app.get('/claims/:id', (req, res) => {
  const id = req.params.id.startsWith('emet:claim:')
    ? req.params.id
    : `emet:claim:${req.params.id}`;

  const claim = store.get(id);
  if (!claim) return res.status(404).json({ error: 'Claim not found' });

  res.json(claim);
});

/**
 * DELETE /claims/:id — Delete a claim.
 */
app.delete('/claims/:id', (req, res) => {
  const id = req.params.id.startsWith('emet:claim:')
    ? req.params.id
    : `emet:claim:${req.params.id}`;

  const deleted = store.del(id);
  if (!deleted) return res.status(404).json({ error: 'Claim not found' });

  treeCache = null;
  res.status(204).send();
});

/**
 * POST /claims/:id/sign — Sign (or co-sign) a claim.
 *
 * Body: { secretKey }          — base64-encoded 64-byte Ed25519 secret key
 *   OR  { agentUri, secretKey } — adds a co-signatory instead of primary sig
 *
 * If the claim already has a primary signature and agentUri is provided,
 * this adds a co-signatory endorsement.
 */
app.post('/claims/:id/sign', (req, res) => {
  try {
    const id = req.params.id.startsWith('emet:claim:')
      ? req.params.id
      : `emet:claim:${req.params.id}`;

    const claim = store.get(id);
    if (!claim) return res.status(404).json({ error: 'Claim not found' });

    const err = requireFields(req.body, ['secretKey']);
    if (err) return res.status(400).json({ error: err });

    const secretKey = new Uint8Array(Buffer.from(req.body.secretKey, 'base64'));

    let updated;
    if (req.body.agentUri) {
      // Co-sign
      updated = emet.addCoSignatory(claim, secretKey, req.body.agentUri, {
        endorsementType: req.body.endorsementType || 'full',
      });
    } else {
      // Primary signature
      updated = emet.signClaim(claim, secretKey);
    }

    store.put(updated);
    treeCache = null;

    res.json(updated);
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

// ---- Verification ---------------------------------------------------------

/**
 * POST /verify — Verify a claim's signature(s).
 *
 * Body: a full claim object (with signature).
 * Returns: { valid, primary: {...}, coSignatories: [...] }
 */
app.post('/verify', (req, res) => {
  try {
    const claim = req.body;
    if (!claim || !claim.id) {
      return res.status(400).json({ error: 'Request body must be a valid claim object' });
    }

    const primary = emet.verifyClaim(claim);
    const coSigs = emet.verifyCoSignatories(claim);

    const allValid = primary.valid && coSigs.every(c => c.valid);

    res.json({
      valid: allValid,
      primary,
      coSignatories: coSigs,
    });
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

// ---- Merkle Tree ----------------------------------------------------------

/**
 * GET /tree — Get the current Merkle root and tree metadata.
 */
app.get('/tree', (_req, res) => {
  const tree = rebuildTree();
  if (!tree) {
    return res.json({ root: null, size: 0, depth: 0, message: 'No claims in store' });
  }
  res.json(emet.serializeTree(tree));
});

/**
 * POST /tree/prove — Generate a Merkle inclusion proof for a claim.
 *
 * Body: { claimId } — full EMET claim id (or just the UUID)
 */
app.post('/tree/prove', (req, res) => {
  try {
    const err = requireFields(req.body, ['claimId']);
    if (err) return res.status(400).json({ error: err });

    let claimId = req.body.claimId;
    if (!claimId.startsWith('emet:claim:')) {
      claimId = `emet:claim:${claimId}`;
    }

    const claim = store.get(claimId);
    if (!claim) return res.status(404).json({ error: 'Claim not found' });

    const tree = rebuildTree();
    if (!tree) return res.status(400).json({ error: 'No claims in tree' });

    // Find the leaf index for this claim
    const claims = store.list();
    const leafIndex = claims.findIndex(c => c.id === claimId);
    if (leafIndex === -1) {
      return res.status(404).json({ error: 'Claim not found in tree' });
    }

    const proof = emet.getProof(tree, leafIndex);
    res.json(proof);
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

// ---- Reputation -----------------------------------------------------------

/**
 * GET /reputation/:agentId — Get reputation for an agent.
 */
app.get('/reputation/:agentId', (req, res) => {
  const agentId = req.params.agentId.startsWith('emet:agent:')
    ? req.params.agentId
    : `emet:agent:${req.params.agentId}`;

  const rep = reputation.getReputation(agentId);
  const trust = reputation.calculateTrust(agentId);

  res.json({
    agentId,
    ...rep,
    trust
  });
});

/**
 * GET /leaderboard — Get top agents by trust score.
 * 
 * Query params:
 *   - limit: Number of agents to return (default: 10)
 */
app.get('/leaderboard', (req, res) => {
  const limit = parseInt(req.query.limit, 10) || 10;
  const leaderboard = reputation.getLeaderboard(limit);
  res.json(leaderboard);
});

/**
 * POST /reputation/:agentId/verify — Record a verification result.
 * 
 * Body: { claimId, result }
 */
app.post('/reputation/:agentId/verify', (req, res) => {
  try {
    const agentId = req.params.agentId.startsWith('emet:agent:')
      ? req.params.agentId
      : `emet:agent:${req.params.agentId}`;

    const err = requireFields(req.body, ['claimId', 'result']);
    if (err) return res.status(400).json({ error: err });

    reputation.recordVerification(agentId, req.body.claimId, req.body.result);

    const rep = reputation.getReputation(agentId);
    const trust = reputation.calculateTrust(agentId);

    res.json({
      agentId,
      ...rep,
      trust
    });
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

// ---- Trust Gate (The Synthesis — Agents that Trust) ----------------------

/**
 * POST /trust-gate — Decide whether to trust an agent before routing a task.
 *
 * This is the core EMET API for agent-to-agent trust decisions.
 * An agent calls this before routing work to another agent.
 * EMET returns a PASS/BLOCK decision based on on-chain stake history.
 *
 * Body:
 *   requester    {string}  — agent ID requesting the trust check (your agent)
 *   candidate    {string}  — agent ID being evaluated (the agent you may trust)
 *   taskType     {string?} — optional task type context (e.g. "market_prediction")
 *   threshold    {string?} — "strict" | "standard" (default) | "lenient"
 *   mode         {string?} — "fast" | "slow" | "auto" (default)
 *                            fast: cache-only (< 50ms), skips on-chain query
 *                            slow: always fresh on-chain query (< 2s)
 *                            auto: fast path for established relationships (3+
 *                                  interactions), slow for new agents + first contact
 *
 * Returns:
 *   decision       "PASS" | "BLOCK"
 *   candidate      {string}
 *   score          {number}  0-100 EMET legacy score (v1 compat)
 *   accuracyScore  {number}  v2: accuracy-only score (% correct claims, 0-100)
 *   riskAppetite   {string}  v2: "low" | "medium" | "high" | "unknown"
 *   slashRate      {number}  slash rate as a fraction (0-1)
 *   taskCount      {number}
 *   reason         {string}  human-readable explanation
 *   path           "fast" | "slow"  — which resolution path was used
 *   threshold      {object}  thresholds that were applied
 *   source         "onchain" | "simulation" | "cache"
 *   chain          "Base mainnet (chainId: 8453)"
 *   contracts      {object}  Base mainnet contract addresses
 *   stakeFloor     {object}  v2: stake floor check (requester tier → candidate meets floor?)
 *
 * Example:
 *   curl -X POST http://localhost:3141/trust-gate \
 *     -H "Content-Type: application/json" \
 *     -d '{"requester":"emet:agent:beta:8bf14243","candidate":"emet:agent:alpha:4f2f7756"}'
 *
 *   # Fast path (established relationship):
 *   curl -X POST http://localhost:3141/trust-gate \
 *     -d '{"requester":"beta","candidate":"alpha","mode":"fast"}'
 *
 *   # Always fresh:
 *   curl -X POST http://localhost:3141/trust-gate \
 *     -d '{"requester":"beta","candidate":"alpha","mode":"slow"}'
 */
app.post('/trust-gate', async (req, res) => {
  try {
    const {
      requester,
      candidate,
      threshold: thresholdKey = 'standard',
      taskType,
      mode = 'auto',
    } = req.body;

    if (!candidate) {
      return res.status(400).json({ error: 'Missing required field: candidate' });
    }

    const thresh = TRUST_THRESHOLDS[thresholdKey] || TRUST_THRESHOLDS.standard;
    const subgraph = process.env.SUBGRAPH_URL || null;

    // ── Fast/slow path resolution (EMET v2) ──────────────────────────────
    //
    // fast:  Check cache only → return immediately (no on-chain query)
    // slow:  Always query on-chain (bypass cache)
    // auto:  Fast for established relationships, slow for new agents
    //
    let resolutionPath = 'slow'; // default

    if (mode === 'fast') {
      resolutionPath = 'fast';
    } else if (mode === 'slow') {
      resolutionPath = 'slow';
    } else {
      // auto: fast path if established relationship (3+ interactions)
      const established = trustCache.isEstablished(candidate, requester);
      resolutionPath = established ? 'fast' : 'slow';
    }

    // ── Try cache first (fast path) ───────────────────────────────────────
    if (resolutionPath === 'fast') {
      const cached = trustCache.get(candidate, requester);
      if (cached) {
        // Track interaction and return cached result
        trustCache.trackInteraction(candidate, requester);
        return res.json({
          ...cached,
          path: 'fast',
          source: 'cache',
          cacheHit: true,
          timestamp: new Date().toISOString(),
        });
      }
      // Cache miss on fast path → fall through to slow resolution
      resolutionPath = 'slow';
    }

    // ── Slow path: resolve reputation from SQLite / on-chain / simulation ─
    const localRep  = reputation.getReputation(candidate);
    const simSnap   = SIMULATION_AGENTS[candidate];

    let score, slashCount, slashRate, taskCount, source, onchainData = null;
    let rawStakeAmount = '0';

    if (localRep.verifications > 0) {
      // We have local verification history — use it
      score      = localRep.score;
      slashCount = Math.round((1 - localRep.accuracy) * localRep.verifications);
      slashRate  = localRep.accuracy > 0 ? (1 - localRep.accuracy) : 0;
      taskCount  = localRep.claims;
      source     = 'local-sqlite';
    } else {
      // Try on-chain query for Ethereum addresses (Base mainnet)
      onchainData = await resolveOnChain(candidate);
      if (onchainData) {
        score      = onchainData.score;
        slashCount = 0; // Reputation contract stores delta, not slash count directly
        slashRate  = onchainData.positive ? 0 : Math.max(0, (50 - score) / 50);
        taskCount  = onchainData.claimCount;
        source     = 'onchain';
      } else if (simSnap) {
        // Use the simulation snapshot (mirrors synthesis-demo.js data)
        score          = simSnap.emetScore;
        slashCount     = simSnap.slashCount;
        slashRate      = simSnap.slashRatioBps / 10000;
        taskCount      = simSnap.taskCount;
        rawStakeAmount = simSnap.stakeAmount;
        source         = subgraph ? 'onchain' : 'simulation';
      } else {
        // Unknown agent — give baseline (new agents start with no history)
        score      = 50;
        slashCount = 0;
        slashRate  = 0;
        taskCount  = 0;
        source     = 'baseline';
      }
    }

    // ── Build v2 agent profile (accuracy + risk separation) ───────────────
    const agentProfile = buildAgentProfile({
      emetScore:   score,
      slashCount,
      taskCount,
      stakeAmount: rawStakeAmount,
      tier:        onchainData?.tier || null,
    });

    // ── Stake floor check (requester tier → candidate must meet floor) ────
    const stakeFloor = checkStakeFloor(agentProfile, agentProfile.tier);

    // ── Decision logic ────────────────────────────────────────────────────
    // V2: threshold applies to accuracyScore (not legacy blended score)
    const effectiveScore = agentProfile.accuracyScore;

    const reasons = [];
    let pass = true;

    if (effectiveScore < thresh.minScore) {
      pass = false;
      reasons.push(`Accuracy score ${effectiveScore} below minimum ${thresh.minScore}`);
    }
    if (slashRate > thresh.maxSlashRate) {
      pass = false;
      reasons.push(`Slash rate ${(slashRate * 100).toFixed(1)}% exceeds maximum ${(thresh.maxSlashRate * 100).toFixed(0)}%`);
    }
    if (taskCount < thresh.minClaims) {
      // Insufficient history is a soft warning (not a hard block) unless strict
      if (thresholdKey === 'strict') {
        pass = false;
        reasons.push(`Task history ${taskCount} below minimum ${thresh.minClaims} (strict mode)`);
      } else {
        reasons.push(`Limited task history (${taskCount} tasks) — treat with caution`);
      }
    }
    if (!stakeFloor.meetsFloor && thresholdKey === 'strict') {
      pass = false;
      reasons.push(`Stake floor not met: required ${stakeFloor.requiredFloorEth} ETH avg, candidate has ${stakeFloor.candidateAvgEth || '0'} ETH`);
    }

    if (pass && reasons.length === 0) {
      reasons.push(`Accuracy ${effectiveScore}/100, slash rate ${(slashRate * 100).toFixed(1)}%, ${taskCount} tasks — meets threshold`);
    }

    // ── Build response ─────────────────────────────────────────────────────
    const response = {
      decision:      pass ? 'PASS' : 'BLOCK',
      candidate,
      requester:     requester || null,
      taskType:      taskType || null,

      // V1 compat
      score,

      // V2: separated dimensions
      accuracyScore: agentProfile.accuracyScore,
      riskAppetite:  agentProfile.riskAppetite,
      tier:          agentProfile.tier,

      slashCount,
      slashRate:     parseFloat(slashRate.toFixed(4)),
      taskCount,
      reason:        reasons.join('; '),
      path:          resolutionPath,
      threshold:     { key: thresholdKey, ...thresh },
      source,

      // V2: stake floor (requester tier enforces min stake)
      stakeFloor: {
        meetsFloor:       stakeFloor.meetsFloor,
        requiredFloorEth: stakeFloor.requiredFloorEth,
        candidateAvgEth:  stakeFloor.candidateAvgEth || '0',
        requesterTier:    agentProfile.tier,
      },

      // On-chain enrichment (when candidate is an Ethereum address)
      ...(onchainData && {
        onchain: {
          tier:       onchainData.tier,
          multiplier: onchainData.multiplier,
          positive:   onchainData.positive,
          rawScore:   onchainData.rawScore,
          contracts:  'Base mainnet — EMETReputation 0x358a775b74f9369D23Ce95EDa57dcbA39A1F4d4e',
        }
      }),

      subgraphUrl: subgraph ? subgraph.substring(0, 40) + '...' : null,
      chain:      'Base mainnet (chainId: 8453)',
      contracts: {
        EMETReputation: '0x358a775b74f9369D23Ce95EDa57dcbA39A1F4d4e',
        EMETStake:      '0xb4A3Cf08194E445db65862Fb92bbC0cE587345bb',
        EMETRegistry:   '0x7a03057490e8541BF4A0F879659e58Fb13f03Ca9',
        EMETChallengeV3:'0x12062513c3d41e5D4f0A0f2B079712D758f11EfC',
      },
      timestamp: new Date().toISOString(),
    };

    // ── Cache the result (for future fast-path hits) ───────────────────────
    trustCache.set(candidate, requester, response);
    trustCache.trackInteraction(candidate, requester);

    res.json(response);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

/**
 * GET /synthesis — Hackathon submission info + live demo data.
 *
 * Returns structured metadata designed for agentic judges at The Synthesis.
 * Mirrors the --json output of synthesis-demo.js but served over HTTP.
 *
 * This endpoint lets judges query EMET directly as an agent would.
 */
app.get('/synthesis', (_req, res) => {
  const claimCount = store.count();
  const agentCount = reputation.getAllAgents().length;

  res.json({
    protocol:      'EMET (אמת — truth)',
    version:       '0.7.0',
    hackathon:     'The Synthesis 2026',
    track:         'Agents that Trust',
    agent:         'Clawdei (@clawdei_ai)',
    github:        'https://github.com/clawdei-ai/emet-core',
    website:       'https://emet-protocol.com',
    chain:         'Base mainnet (chainId: 8453)',
    problemSolved: 'Replaces centralized trust registries with economic stake history. Any agent can verify another\'s trustworthiness without an API key, registry login, or central authority.',
    submission: {
      track:        'Agents that Trust',
      problemMatch: 'Directly solves "trust flows through centralized registries" — EMET removes the registry entirely',
      approach:     'Agents stake ETH on claims. Challengers slash incorrect stakes. Reputation is the immutable on-chain record.',
      liveDemo:     'POST /trust-gate — call with any agent ID to get PASS/BLOCK decision',
      judgeInstructions: [
        '1. POST /trust-gate with {"candidate":"emet:agent:alpha:4f2f7756"} — see a trusted agent PASS',
        '2. POST /trust-gate with {"candidate":"emet:agent:gamma:a5a671a3"} — see a bad actor BLOCK',
        '3. POST /trust-gate with {"candidate":"emet:agent:epsilon:c2d91e04"} — see a fresh agent baseline',
        '4. GET /leaderboard — see agents ranked by stake-weighted trust score',
        '5. GET /reputation/emet:agent:alpha:4f2f7756 — full reputation profile',
        '6. [v2] POST /trust-gate with {"candidate":"alpha","mode":"fast"} — fast path (cache, <50ms)',
        '7. [v2] POST /trust-gate with {"candidate":"alpha","mode":"slow"} — slow path (live, <2s)',
        '8. [v2] POST /trust-gate with {"candidate":"alpha"} — v2 response includes accuracyScore + riskAppetite',
        '9. [v2] POST /trust-gate/invalidate with {"candidate":"alpha"} — simulate slash event cache invalidation',
      ],
    },
    infrastructure: {
      contracts:    23,
      tests:        440,
      subgraph:     'The Graph (7 entities, 8 queries) — deploy pending Envio/Graph auth',
      envio:        'TypeScript handlers built (7660011) — deploy pending auth token',
      sdks:         ['JavaScript (gate.js)', 'Python (batch gate)'],
    },
    contracts: {
      EMETReputation:   '0x358a775b74f9369D23Ce95EDa57dcbA39A1F4d4e',
      EMETStake:        '0xb4A3Cf08194E445db65862Fb92bbC0cE587345bb',
      EMETRegistry:     '0x7a03057490e8541BF4A0F879659e58Fb13f03Ca9',
      EMETChallengeV3:  '0x12062513c3d41e5D4f0A0f2B079712D758f11EfC',
      EMETLPRewards:    '0x81a48A92a5D91960D0a32762883A8B356fb05e2E',
      EMETPrecedent:    '0x0f0c40c2Ba27f61A6ba7852FEA3379e3e6163bF8',
    },
    stackPositioning: {
      payments:   'ERC-8183 (Virtuals + EF) — did the transaction execute?',
      liquidity:  'LI.FI Agentic Commerce — what is the best route?',
      identity:   'LUKSO Universal Profiles — who is this agent?',
      truth:      'EMET Protocol — can I trust this agent\'s CLAIMS? (this layer)',
    },
    keyDifferentiators: [
      'No centralized registry — on-chain history is the authority',
      'Open challengers — any agent can slash, not just authorized parties (vs ERC-8004)',
      'Production-ready — 23 contracts, 440 tests, not a prototype',
      'Agent-callable — this API endpoint IS the integration point',
      'Sybil resistance — trust requires ETH stake, cold wallets start at zero',
      '[v2] Fast/slow trust path — <50ms cache for established agents, live query for new contacts',
      '[v2] Accuracy ≠ risk appetite — high-stakes correct agents not penalized for size of bets',
      '[v2] Stake floor by requester tier — Gold agents enforce higher standards on counterparties',
    ],
    liveStats: {
      localClaims: claimCount,
      localAgents: agentCount,
      mode:        process.env.SUBGRAPH_URL ? 'onchain' : 'simulation',
    },
    timestamp: new Date().toISOString(),
  });
});

// ---- Cache (EMET v2) -------------------------------------------------------

/**
 * POST /trust-gate/invalidate — Invalidate cached trust for an agent (slash event).
 *
 * Call this when a slash event is recorded on-chain for an agent.
 * Forces the next /trust-gate query to use the slow path (fresh on-chain data).
 *
 * Body: { candidate } — agent whose cache should be invalidated
 */
app.post('/trust-gate/invalidate', (req, res) => {
  const { candidate } = req.body;
  if (!candidate) {
    return res.status(400).json({ error: 'Missing required field: candidate' });
  }
  trustCache.invalidate(candidate);
  res.json({
    ok: true,
    candidate,
    message: `Trust cache invalidated for ${candidate}. Next query will use slow path.`,
    timestamp: new Date().toISOString(),
  });
});

/**
 * GET /trust-gate/cache/stats — Cache statistics for observability.
 */
app.get('/trust-gate/cache/stats', (_req, res) => {
  res.json({
    ...trustCache.stats(),
    ttlSeconds: 60,
    timestamp: new Date().toISOString(),
  });
});

// ---- Database Info --------------------------------------------------------

/**
 * GET /db/stats — Get database statistics.
 */
app.get('/db/stats', (_req, res) => {
  const claimCount = store.count();
  const agentCount = reputation.getAllAgents().length;
  const schemaVersion = store.getSchemaVersion();

  res.json({
    claims: claimCount,
    agents: agentCount,
    schemaVersion,
    storage: 'sqlite'
  });
});

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------

// Only start server if this file is run directly
if (require.main === module) {
  app.listen(PORT, () => {
    const claims = store.list();
    const schemaVersion = store.getSchemaVersion();
    console.log(`⚡ EMET API v0.7.0 listening on http://localhost:${PORT}`);
    console.log(`   SQLite storage (schema v${schemaVersion})`);
    console.log(`   ${claims.length} claim(s) in store`);
  });
}

// Export for testing
module.exports = app;
