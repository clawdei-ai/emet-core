/**
 * EMET Protocol Core Library
 * 
 * Epistemic Marker for Encoded Truth - A protocol for AI agents
 * to make cryptographically verifiable claims with explicit uncertainty.
 * 
 * @module @emet-protocol/core
 * @version 0.1.0
 */

const claim = require('./claim');
const merkle = require('./merkle');
const identity = require('./identity');

module.exports = {
  // Claim functions
  createClaim: claim.createClaim,
  signClaim: claim.signClaim,
  verifyClaim: claim.verifyClaim,
  hashClaim: claim.hashClaim,
  generateKeyPair: claim.generateKeyPair,
  addCoSignatory: claim.addCoSignatory,
  verifyCoSignatories: claim.verifyCoSignatories,
  
  // Claim constants
  ClaimType: claim.ClaimType,
  SignatureAlgorithm: claim.SignatureAlgorithm,
  
  // Merkle tree functions
  buildTree: merkle.buildTree,
  getProof: merkle.getProof,
  verifyProof: merkle.verifyProof,
  computeRoot: merkle.computeRoot,
  serializeTree: merkle.serializeTree,
  buildTreeFromClaims: merkle.buildTreeFromClaims,
  
  // AIP Identity Bridge
  verifyIdentity: identity.verifyIdentity,
  createIdentityToken: identity.createIdentityToken,
  fetchRegistry: identity.fetchRegistry,
  
  // Direct module access
  claim,
  merkle,
  identity
};
