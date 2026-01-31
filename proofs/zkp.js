/**
 * Zero-Knowledge Proof module for private EMET claims
 *
 * Allows proving properties of claims without revealing the claims themselves.
 * Use cases:
 * - Medical verification ("I have valid health claim" without revealing condition)
 * - Whistleblower protection (prove insider knowledge without revealing identity)
 * - Competitive intelligence (prove market knowledge without revealing sources)
 *
 * === SETUP ===
 * This module requires snarkjs for proof generation/verification and circom
 * for circuit compilation. Install dependencies:
 *
 *   cd proofs && npm install
 *
 * To compile circuits you also need the circom compiler:
 *
 *   # Install Rust (if not present)
 *   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
 *
 *   # Clone and build circom
 *   git clone https://github.com/iden3/circom.git
 *   cd circom && cargo build --release
 *   cargo install --path circom
 *
 * See proofs/circuits/README.md for circuit compilation instructions.
 */

const snarkjs = require('snarkjs');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// ---------------------------------------------------------------------------
// Proof generation & verification
// ---------------------------------------------------------------------------

/**
 * Generate a zero-knowledge proof for a given circuit.
 *
 * @param {Object} input        - Circuit input signals (key-value pairs)
 * @param {string} wasmPath     - Path to the compiled circuit WASM file
 * @param {string} zkeyPath     - Path to the proving key (.zkey)
 * @returns {Promise<{proof: Object, publicSignals: string[]}>}
 *
 * @example
 *   const { proof, publicSignals } = await generateProof(
 *     { preimage: '0x1234..', hash: '0xabcd..' },
 *     './circuits/build/claim_hash_js/claim_hash.wasm',
 *     './circuits/build/claim_hash.zkey'
 *   );
 */
async function generateProof(input, wasmPath, zkeyPath) {
  if (!input || typeof input !== 'object') {
    throw new Error('input must be a non-null object of circuit signals');
  }
  if (!fs.existsSync(wasmPath)) {
    throw new Error(`WASM file not found: ${wasmPath}`);
  }
  if (!fs.existsSync(zkeyPath)) {
    throw new Error(`zkey file not found: ${zkeyPath}`);
  }

  const { proof, publicSignals } = await snarkjs.groth16.fullProve(
    input,
    wasmPath,
    zkeyPath
  );

  return { proof, publicSignals };
}

/**
 * Verify a zero-knowledge proof.
 *
 * @param {Object}   proof          - The proof object from generateProof
 * @param {string[]} publicSignals  - Public signals from generateProof
 * @param {string}   vkeyPath       - Path to the verification key JSON
 * @returns {Promise<boolean>}      - true if the proof is valid
 *
 * @example
 *   const vkey = './circuits/build/claim_hash_vkey.json';
 *   const ok = await verifyProof(proof, publicSignals, vkey);
 *   console.log(ok ? 'Valid proof' : 'Invalid proof');
 */
async function verifyProof(proof, publicSignals, vkeyPath) {
  if (!proof || !publicSignals) {
    throw new Error('proof and publicSignals are required');
  }
  if (!fs.existsSync(vkeyPath)) {
    throw new Error(`Verification key not found: ${vkeyPath}`);
  }

  const vkey = JSON.parse(fs.readFileSync(vkeyPath, 'utf8'));
  const valid = await snarkjs.groth16.verify(vkey, publicSignals, proof);
  return valid;
}

// ---------------------------------------------------------------------------
// Helper utilities
// ---------------------------------------------------------------------------

/**
 * Export a Solidity verifier contract from a zkey file.
 * Useful for on-chain verification of EMET claims.
 *
 * @param {string} zkeyPath - Path to the .zkey file
 * @returns {Promise<string>} Solidity source code
 */
async function exportSolidityVerifier(zkeyPath) {
  if (!fs.existsSync(zkeyPath)) {
    throw new Error(`zkey file not found: ${zkeyPath}`);
  }
  const templates = {};  // snarkjs uses its built-in templates
  const solidityCode = await snarkjs.zKey.exportSolidityVerifier(
    zkeyPath,
    templates
  );
  return solidityCode;
}

/**
 * Export the verification key from a zkey file.
 *
 * @param {string} zkeyPath - Path to the .zkey file
 * @returns {Promise<Object>} Verification key JSON
 */
async function exportVerificationKey(zkeyPath) {
  if (!fs.existsSync(zkeyPath)) {
    throw new Error(`zkey file not found: ${zkeyPath}`);
  }
  const vkey = await snarkjs.zKey.exportVerificationKey(zkeyPath);
  return vkey;
}

/**
 * Hash a claim body into a field element suitable for circom circuits.
 * Uses Poseidon-compatible representation: SHA-256 truncated to 253 bits
 * (to fit within the BN128 scalar field).
 *
 * @param {string|Buffer} data - Claim content to hash
 * @returns {string} BigInt string suitable as circuit input
 */
function claimToFieldElement(data) {
  const buf = Buffer.isBuffer(data) ? data : Buffer.from(data, 'utf8');
  const hash = crypto.createHash('sha256').update(buf).digest();
  // Truncate to 253 bits to fit in BN128 field (snarkjs default curve)
  hash[0] &= 0x1f;  // Clear top 3 bits
  return BigInt('0x' + hash.toString('hex')).toString();
}

/**
 * Convert a confidence value (0-1 float) to a circuit-friendly integer.
 * Multiplies by 10000 to preserve 4 decimal places of precision.
 *
 * @param {number} confidence - Value between 0 and 1
 * @returns {string} Integer string for circuit input (0-10000)
 */
function confidenceToSignal(confidence) {
  if (typeof confidence !== 'number' || confidence < 0 || confidence > 1) {
    throw new Error('confidence must be a number between 0 and 1');
  }
  return Math.round(confidence * 10000).toString();
}

// ---------------------------------------------------------------------------
// Exports
// ---------------------------------------------------------------------------

module.exports = {
  // Core proof functions
  generateProof,
  verifyProof,

  // Key management helpers
  exportSolidityVerifier,
  exportVerificationKey,

  // Signal conversion helpers
  claimToFieldElement,
  confidenceToSignal,
};
