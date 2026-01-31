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
 * @version 0.4.0
 */

const express = require('express');
const cors = require('cors');
const emet = require('../core');
const store = require('./store');
const reputation = require('./db/reputation');

const app = express();
const PORT = process.env.PORT || 3141;

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
    version: '0.4.0',
    storage: 'sqlite',
    schemaVersion,
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
    console.log(`⚡ EMET API v0.4.0 listening on http://localhost:${PORT}`);
    console.log(`   SQLite storage (schema v${schemaVersion})`);
    console.log(`   ${claims.length} claim(s) in store`);
  });
}

// Export for testing
module.exports = app;
