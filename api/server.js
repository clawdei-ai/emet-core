#!/usr/bin/env node
/**
 * EMET Protocol — REST API Server
 *
 * A minimal Express server that wraps @emet-protocol/core and exposes
 * claim lifecycle operations over HTTP.  Designed for local dev/test.
 *
 * Usage:
 *   cd api && npm install && npm start
 *
 * Default port: 3141 (override with PORT env var)
 */

const express = require('express');
const cors = require('cors');
const emet = require('../core');
const store = require('./store');

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
  res.json({
    name: '@emet-protocol/api',
    version: '0.1.0',
    endpoints: [
      'POST   /claims',
      'GET    /claims/:id',
      'POST   /claims/:id/sign',
      'POST   /verify',
      'GET    /tree',
      'POST   /tree/prove',
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
    treeCache = null; // invalidate

    res.status(201).json(claim);
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

/**
 * GET /claims — List all claims (optional).
 */
app.get('/claims', (_req, res) => {
  res.json(store.list());
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

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------
app.listen(PORT, () => {
  const claims = store.list();
  console.log(`⚡ EMET API listening on http://localhost:${PORT}`);
  console.log(`   ${claims.length} claim(s) in store`);
});
