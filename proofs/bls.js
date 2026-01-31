/**
 * EMET Protocol — BLS Signature Aggregation Module
 *
 * BLS (Boneh-Lynn-Shacham) signatures enable efficient aggregation of multiple
 * signatures into a single compact signature. This is particularly valuable
 * for EMET's multi-agent co-signing scenarios where many AI agents may
 * endorse the same claim.
 *
 * Uses @noble/bls12-381 (minimal-pubkey-size variant):
 *   - Public key:  48 bytes (G1 point)
 *   - Signature:   96 bytes (G2 point)
 *   - Private key:  32 bytes (scalar in Fr)
 *
 * Key advantages of BLS for EMET:
 * - N signatures compress to 1 (96 bytes regardless of signer count)
 * - Verification requires one aggregated-key step + one pairing check
 * - Signatures can be aggregated incrementally ("lazy" aggregation)
 * - Perfect for consensus scenarios (multiple AI agents agreeing on a claim)
 *
 * @module @emet-protocol/proofs/bls
 * @version 0.2.0
 */

const bls = require('@noble/bls12-381');

// ---------------------------------------------------------------------------
// Key generation
// ---------------------------------------------------------------------------

/**
 * Generate a BLS key pair suitable for EMET claim signing.
 *
 * @returns {{ publicKey: Uint8Array, privateKey: Uint8Array }}
 *   publicKey  — 48-byte compressed G1 point
 *   privateKey — 32-byte scalar
 */
function generateBLSKeyPair() {
  const privateKey = bls.utils.randomPrivateKey();      // 32 bytes
  const publicKey  = bls.getPublicKey(privateKey);       // 48 bytes (G1)
  return { publicKey, privateKey };
}

// ---------------------------------------------------------------------------
// Signing
// ---------------------------------------------------------------------------

/**
 * Create a partial BLS signature that can later be aggregated with others.
 *
 * @param {Uint8Array|string} message    — payload to sign (claim hash, etc.)
 * @param {Uint8Array}        privateKey — 32-byte BLS secret key
 * @returns {Promise<Uint8Array>} 96-byte BLS signature (G2 point)
 */
async function createPartialSignature(message, privateKey) {
  const msg = typeof message === 'string'
    ? new TextEncoder().encode(message)
    : message;
  return bls.sign(msg, privateKey);
}

// ---------------------------------------------------------------------------
// Aggregation
// ---------------------------------------------------------------------------

/**
 * Aggregate multiple BLS signatures into a single signature.
 *
 * All input signatures must be 96-byte G2 points produced by
 * {@link createPartialSignature}.  The result is itself 96 bytes,
 * regardless of how many inputs were combined.
 *
 * @param {Uint8Array[]} signatures — array of 96-byte BLS signatures
 * @returns {Uint8Array} aggregated 96-byte signature
 * @throws {Error} if fewer than 2 signatures are supplied
 */
function aggregateSignatures(signatures) {
  if (!Array.isArray(signatures) || signatures.length < 2) {
    throw new Error('aggregateSignatures requires at least 2 signatures');
  }
  return bls.aggregateSignatures(signatures);
}

// ---------------------------------------------------------------------------
// Verification
// ---------------------------------------------------------------------------

/**
 * Verify an aggregated BLS signature against the set of signer public keys.
 *
 * All signers must have signed the **same** message.  The function
 * aggregates the supplied public keys into a single G1 point and performs
 * a single pairing check.
 *
 * @param {Uint8Array|string}  message        — the message all signers signed
 * @param {Uint8Array}         aggregatedSig  — the aggregated 96-byte signature
 * @param {Uint8Array[]}       publicKeys     — array of 48-byte signer public keys
 * @returns {Promise<boolean>} true when the aggregate signature is valid
 */
async function verifyAggregate(message, aggregatedSig, publicKeys) {
  if (!Array.isArray(publicKeys) || publicKeys.length === 0) {
    throw new Error('verifyAggregate requires at least one public key');
  }
  const msg = typeof message === 'string'
    ? new TextEncoder().encode(message)
    : message;

  const aggregatedPub = bls.aggregatePublicKeys(publicKeys);
  return bls.verify(aggregatedSig, msg, aggregatedPub);
}

// ---------------------------------------------------------------------------
// Exports
// ---------------------------------------------------------------------------

module.exports = {
  generateBLSKeyPair,
  createPartialSignature,
  aggregateSignatures,
  verifyAggregate,

  // Module metadata
  __BLS_VERSION__: '0.2.0',
  __BLS_CURVE__: 'BLS12-381',
  __BLS_STATUS__: 'implemented',
};
