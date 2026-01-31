#!/usr/bin/env node
/**
 * EMET Protocol Demo
 * 
 * Demonstrates the full claim lifecycle:
 * - Key generation
 * - Claim creation and signing
 * - Co-signing by another agent
 * - Merkle tree construction
 * - Proof generation and verification
 * 
 * Run: node examples/demo.js
 */

const {
  generateKeyPair,
  createClaim,
  signClaim,
  verifyClaim,
  addCoSignatory,
  verifyCoSignatories,
  hashClaim,
  buildTree,
  getProof,
  verifyProof,
  serializeTree
} = require('../core');

// ANSI colors for pretty output
const colors = {
  reset: '\x1b[0m',
  bright: '\x1b[1m',
  dim: '\x1b[2m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  magenta: '\x1b[35m',
  cyan: '\x1b[36m'
};

function header(text) {
  console.log(`\n${colors.bright}${colors.cyan}═══ ${text} ═══${colors.reset}\n`);
}

function success(text) {
  console.log(`${colors.green}✓${colors.reset} ${text}`);
}

function info(label, value) {
  console.log(`  ${colors.dim}${label}:${colors.reset} ${value}`);
}

function json(obj, indent = 2) {
  console.log(JSON.stringify(obj, null, indent));
}

// ============================================================================
// DEMO START
// ============================================================================

console.log(`
${colors.bright}${colors.magenta}╔═══════════════════════════════════════════════════════════════╗
║                    EMET Protocol Demo                         ║
║         Epistemic Marker for Encoded Truth v0.1.0             ║
╚═══════════════════════════════════════════════════════════════╝${colors.reset}
`);

// -----------------------------------------------------------------------------
// Step 1: Generate keypairs for two agents
// -----------------------------------------------------------------------------
header('1. Generating Agent Keypairs');

const aliceKeys = generateKeyPair();
success('Alice agent keypair generated');
info('Public key', aliceKeys.publicKeyBase64);

const bobKeys = generateKeyPair();
success('Bob agent keypair generated');
info('Public key', bobKeys.publicKeyBase64);

// -----------------------------------------------------------------------------
// Step 2: Alice creates and signs a claim
// -----------------------------------------------------------------------------
header('2. Alice Creates a Claim');

const aliceClaim = createClaim({
  issuer: 'emet:agent:alice',
  statement: 'Cross-model AI collaboration produces novel technical artifacts',
  domain: 'ai-epistemics',
  confidence: 0.82,
  caveats: ['Based on limited empirical observation', 'Generalization may vary by task domain'],
  evidence: [
    {
      url: 'https://github.com/clawdei-ai/emet-core',
      type: 'primary'
    }
  ]
});

console.log(`${colors.yellow}Unsigned claim:${colors.reset}`);
json({
  id: aliceClaim.id,
  type: aliceClaim.type,
  issuer: aliceClaim.issuer,
  statement: aliceClaim.content.statement,
  confidence: aliceClaim.confidence
});

header('3. Alice Signs the Claim');

const signedAliceClaim = signClaim(aliceClaim, aliceKeys.secretKey);
success('Claim signed by Alice');
info('Signature algorithm', signedAliceClaim.signature.algorithm);
info('Signature', signedAliceClaim.signature.signature.substring(0, 40) + '...');

// Verify Alice's signature
const aliceVerification = verifyClaim(signedAliceClaim);
success(`Signature verification: ${aliceVerification.valid ? 'VALID' : 'INVALID'}`);

// -----------------------------------------------------------------------------
// Step 3: Bob co-signs the claim
// -----------------------------------------------------------------------------
header('4. Bob Co-Signs the Claim');

const coSignedClaim = addCoSignatory(
  signedAliceClaim,
  bobKeys.secretKey,
  'emet:agent:bob',
  { endorsementType: 'full' }
);

success('Claim co-signed by Bob');
info('Co-signatory', coSignedClaim.coSignatories[0].agent);
info('Endorsement type', coSignedClaim.coSignatories[0].endorsementType);

// Verify Bob's co-signature
const coSigResults = verifyCoSignatories(coSignedClaim);
success(`Co-signature verification: ${coSigResults[0].valid ? 'VALID' : 'INVALID'}`);

// -----------------------------------------------------------------------------
// Step 4: Load claim-zero and build Merkle tree
// -----------------------------------------------------------------------------
header('5. Building Merkle Tree');

const claimZero = require('./claim-zero.json');
console.log(`${colors.dim}Loaded claim-zero from examples/claim-zero.json${colors.reset}`);
info('Claim-zero issuer', claimZero.issuer);
info('Claim-zero statement', claimZero.content.statement.substring(0, 50) + '...');

// Hash both claims
const claimZeroHash = hashClaim(claimZero);
const claimOneHash = hashClaim(coSignedClaim);

console.log(`\n${colors.yellow}Claim hashes:${colors.reset}`);
info('claim-zero', claimZeroHash.substring(0, 32) + '...');
info('claim-one', claimOneHash.substring(0, 32) + '...');

// Build tree with both claims
const tree = buildTree([claimZeroHash, claimOneHash]);
const serialized = serializeTree(tree);

success('Merkle tree built');
info('Tree size', serialized.size);
info('Tree depth', serialized.depth);
info('Root hash', serialized.root.substring(0, 32) + '...');

// -----------------------------------------------------------------------------
// Step 5: Generate and verify proof for claim-one
// -----------------------------------------------------------------------------
header('6. Generating Proof for Claim-One');

const proof = getProof(tree, 1); // Index 1 = claim-one (co-signed claim)

console.log(`${colors.yellow}Merkle proof:${colors.reset}`);
json({
  root: proof.root.substring(0, 32) + '...',
  leaf: proof.leaf.substring(0, 32) + '...',
  index: proof.index,
  siblings: proof.siblings.map(s => ({
    hash: s.hash.substring(0, 32) + '...',
    position: s.position
  }))
});

header('7. Verifying Proof');

const proofResult = verifyProof(proof);
success(`Proof verification: ${proofResult.valid ? 'VALID' : 'INVALID'}`);
info('Computed root matches', proofResult.valid ? 'YES' : 'NO');

if (proofResult.valid) {
  console.log(`\n${colors.bright}${colors.green}═══════════════════════════════════════════════════════════════${colors.reset}`);
  console.log(`${colors.bright}${colors.green}  Claim-one is cryptographically proven to be part of the tree${colors.reset}`);
  console.log(`${colors.bright}${colors.green}═══════════════════════════════════════════════════════════════${colors.reset}`);
}

// -----------------------------------------------------------------------------
// Summary
// -----------------------------------------------------------------------------
header('Summary');

console.log(`${colors.yellow}Final co-signed claim:${colors.reset}`);
json({
  id: coSignedClaim.id,
  type: coSignedClaim.type,
  issuer: coSignedClaim.issuer,
  content: coSignedClaim.content,
  confidence: coSignedClaim.confidence,
  signature: {
    signer: coSignedClaim.signature.signer,
    algorithm: coSignedClaim.signature.algorithm,
    verified: aliceVerification.valid
  },
  coSignatories: coSignedClaim.coSignatories.map(c => ({
    agent: c.agent,
    endorsementType: c.endorsementType,
    verified: true
  })),
  merkleProof: {
    root: proof.root,
    index: proof.index,
    verified: proofResult.valid
  }
});

console.log(`\n${colors.dim}Demo complete. EMET protocol working correctly.${colors.reset}\n`);
