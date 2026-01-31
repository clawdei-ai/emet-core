/**
 * EMET Protocol - Claim Module
 * 
 * Core functionality for creating, signing, and verifying EMET claims.
 * Uses Ed25519 signatures via tweetnacl for cryptographic operations.
 * 
 * @module @emet-protocol/core/claim
 * @version 1.0.0
 */

const nacl = require('tweetnacl');
const { createHash, randomUUID } = require('crypto');

/**
 * Supported claim types in the EMET protocol
 * @readonly
 * @enum {string}
 */
const ClaimType = {
  ASSERTION: 'Assertion',
  CORRECTION: 'Correction',
  RETRACTION: 'Retraction',
  ENDORSEMENT: 'Endorsement',
  DISPUTE: 'Dispute'
};

/**
 * Supported signature algorithms
 * @readonly
 * @enum {string}
 */
const SignatureAlgorithm = {
  ED25519: 'ed25519',
  // Future: post-quantum algorithms
  DILITHIUM2: 'dilithium2',
  DILITHIUM3: 'dilithium3',
  DILITHIUM5: 'dilithium5'
};

/**
 * Creates a canonical JSON representation for hashing.
 * Implements JCS (RFC 8785) canonicalization.
 * 
 * @private
 * @param {Object} obj - Object to canonicalize
 * @returns {string} Canonical JSON string
 */
function canonicalize(obj) {
  if (obj === null || typeof obj !== 'object') {
    return JSON.stringify(obj);
  }
  
  if (Array.isArray(obj)) {
    return '[' + obj.map(canonicalize).join(',') + ']';
  }
  
  const sortedKeys = Object.keys(obj).sort();
  const pairs = sortedKeys
    .filter(key => obj[key] !== undefined)
    .map(key => JSON.stringify(key) + ':' + canonicalize(obj[key]));
  
  return '{' + pairs.join(',') + '}';
}

/**
 * Computes the SHA-256 hash of an EMET claim.
 * 
 * The hash is computed over the canonical JSON representation of the claim,
 * excluding the signature field to allow signature verification.
 * 
 * @param {Object} claim - The claim object to hash
 * @param {Object} [options] - Hashing options
 * @param {string[]} [options.excludeFields=['signature']] - Fields to exclude from hash
 * @param {string} [options.encoding='hex'] - Output encoding ('hex', 'base64', 'buffer')
 * @returns {string|Buffer} The SHA-256 hash of the claim
 * 
 * @example
 * const hash = hashClaim(claim);
 * console.log(hash); // '7d865e959b2466918c9863afca942d0fb89d7c9ac0c99bafc3749504ded97730'
 * 
 * @example
 * // Get raw buffer for signing
 * const hashBuffer = hashClaim(claim, { encoding: 'buffer' });
 */
function hashClaim(claim, options = {}) {
  const { excludeFields = ['signature'], encoding = 'hex' } = options;
  
  // Create a copy without excluded fields
  const claimToHash = { ...claim };
  excludeFields.forEach(field => delete claimToHash[field]);
  
  // Canonicalize and hash
  const canonical = canonicalize(claimToHash);
  const hash = createHash('sha256').update(canonical).digest();
  
  if (encoding === 'buffer') {
    return hash;
  }
  return hash.toString(encoding);
}

/**
 * Creates a new EMET claim.
 * 
 * @param {Object} params - Claim parameters
 * @param {string} params.issuer - URI of the issuing agent (e.g., 'emet:agent:claude-3-opus')
 * @param {string} params.statement - The assertion being made
 * @param {string} [params.type='Assertion'] - Type of claim (Assertion, Correction, etc.)
 * @param {string} [params.subject] - URI of what/who the claim is about
 * @param {string} [params.domain] - Knowledge domain (e.g., 'science', 'history')
 * @param {string} [params.scope='contextual'] - Scope of validity
 * @param {string[]} [params.caveats=[]] - Known limitations
 * @param {Array<{url: string, type?: string}>} [params.evidence=[]] - Supporting evidence
 * @param {number} [params.confidence] - Confidence level (0-1)
 * @param {string} [params.threadId] - Thread ID for Merkle proof inclusion
 * @param {string} [params.previousVersion] - Reference to previous version if updating
 * @returns {Object} The created claim object (unsigned)
 * 
 * @throws {Error} If required parameters are missing
 * @throws {RangeError} If confidence is not between 0 and 1
 * 
 * @example
 * const claim = createClaim({
 *   issuer: 'emet:agent:claude-3-opus-20240229',
 *   statement: 'Water boils at 100°C at sea level.',
 *   domain: 'physics',
 *   confidence: 0.99,
 *   evidence: [{ url: 'https://example.com/source', type: 'primary' }]
 * });
 */
function createClaim(params) {
  const {
    issuer,
    statement,
    type = ClaimType.ASSERTION,
    subject,
    domain,
    scope = 'contextual',
    caveats = [],
    evidence = [],
    confidence,
    threadId,
    previousVersion
  } = params;
  
  // Validation
  if (!issuer) {
    throw new Error('Claim issuer is required');
  }
  if (!statement) {
    throw new Error('Claim statement is required');
  }
  if (confidence !== undefined && (confidence < 0 || confidence > 1)) {
    throw new RangeError('Confidence must be between 0 and 1');
  }
  if (!Object.values(ClaimType).includes(type)) {
    throw new Error(`Invalid claim type: ${type}. Must be one of: ${Object.values(ClaimType).join(', ')}`);
  }
  
  const claim = {
    id: `emet:claim:${randomUUID()}`,
    type,
    issuer,
    content: {
      statement,
      ...(domain && { domain }),
      scope,
      ...(caveats.length > 0 && { caveats })
    },
    ...(subject && { subject }),
    evidence: evidence.map(e => ({
      url: e.url,
      type: e.type || 'primary',
      retrievedAt: e.retrievedAt || new Date().toISOString(),
      ...(e.hash && { hash: e.hash })
    })),
    confidence: confidence !== undefined ? confidence : 0.5,
    timestamp: new Date().toISOString(),
    version: previousVersion ? incrementVersion(previousVersion) : '1.0.0',
    ...(previousVersion && { previousVersion }),
    ...(threadId && { threadId }),
    coSignatories: []
  };
  
  return claim;
}

/**
 * Increments the patch version of a semantic version string.
 * @private
 */
function incrementVersion(version) {
  const parts = version.split('.');
  parts[2] = String(parseInt(parts[2], 10) + 1);
  return parts.join('.');
}

/**
 * Signs an EMET claim using Ed25519.
 * 
 * @param {Object} claim - The claim to sign
 * @param {Uint8Array} secretKey - The 64-byte Ed25519 secret key
 * @param {Object} [options] - Signing options
 * @param {string} [options.algorithm='ed25519'] - Signature algorithm
 * @returns {Object} The claim with signature attached
 * 
 * @throws {Error} If the secret key is invalid
 * 
 * @example
 * const keyPair = nacl.sign.keyPair();
 * const signedClaim = signClaim(claim, keyPair.secretKey);
 */
function signClaim(claim, secretKey, options = {}) {
  const { algorithm = SignatureAlgorithm.ED25519 } = options;
  
  if (algorithm !== SignatureAlgorithm.ED25519) {
    throw new Error(`Unsupported algorithm: ${algorithm}. Currently only ed25519 is implemented.`);
  }
  
  if (!secretKey || secretKey.length !== nacl.sign.secretKeyLength) {
    throw new Error(`Invalid secret key: must be ${nacl.sign.secretKeyLength} bytes`);
  }
  
  // Get the public key from the secret key
  const publicKey = secretKey.slice(32);
  
  // Hash the claim
  const claimHash = hashClaim(claim, { encoding: 'buffer' });
  
  // Sign the hash
  const signatureBytes = nacl.sign.detached(claimHash, secretKey);
  
  // Create the signature object
  const signature = {
    claimId: claim.id,
    signer: claim.issuer,
    algorithm,
    publicKey: Buffer.from(publicKey).toString('base64'),
    signature: Buffer.from(signatureBytes).toString('base64'),
    timestamp: new Date().toISOString(),
    canonicalization: 'jcs',
    hashAlgorithm: 'sha256'
  };
  
  return {
    ...claim,
    signature
  };
}

/**
 * Verifies the signature on an EMET claim.
 * 
 * @param {Object} claim - The signed claim to verify
 * @param {Object} [options] - Verification options
 * @param {Uint8Array} [options.publicKey] - Override public key (uses embedded key if not provided)
 * @returns {Object} Verification result
 * @returns {boolean} returns.valid - Whether the signature is valid
 * @returns {string} [returns.error] - Error message if invalid
 * @returns {Object} returns.details - Additional verification details
 * 
 * @example
 * const result = verifyClaim(signedClaim);
 * if (result.valid) {
 *   console.log('Signature verified!');
 * } else {
 *   console.error('Invalid signature:', result.error);
 * }
 */
function verifyClaim(claim, options = {}) {
  const result = {
    valid: false,
    details: {
      claimId: claim.id,
      issuer: claim.issuer,
      timestamp: claim.timestamp
    }
  };
  
  // Check signature exists
  if (!claim.signature) {
    result.error = 'Claim has no signature';
    return result;
  }
  
  const { signature } = claim;
  
  // Verify algorithm is supported
  if (signature.algorithm !== SignatureAlgorithm.ED25519) {
    result.error = `Unsupported algorithm: ${signature.algorithm}`;
    return result;
  }
  
  // Get public key
  let publicKey;
  if (options.publicKey) {
    publicKey = options.publicKey;
  } else if (signature.publicKey) {
    publicKey = new Uint8Array(Buffer.from(signature.publicKey, 'base64'));
  } else {
    result.error = 'No public key available for verification';
    return result;
  }
  
  // Verify public key length
  if (publicKey.length !== nacl.sign.publicKeyLength) {
    result.error = `Invalid public key length: expected ${nacl.sign.publicKeyLength}, got ${publicKey.length}`;
    return result;
  }
  
  // Get signature bytes
  const signatureBytes = new Uint8Array(Buffer.from(signature.signature, 'base64'));
  
  // Verify signature length
  if (signatureBytes.length !== nacl.sign.signatureLength) {
    result.error = `Invalid signature length: expected ${nacl.sign.signatureLength}, got ${signatureBytes.length}`;
    return result;
  }
  
  // Hash the claim (excluding signature)
  const claimHash = hashClaim(claim, { encoding: 'buffer' });
  
  // Verify
  try {
    const valid = nacl.sign.detached.verify(claimHash, signatureBytes, publicKey);
    result.valid = valid;
    if (!valid) {
      result.error = 'Signature verification failed';
    }
    result.details.algorithm = signature.algorithm;
    result.details.signedAt = signature.timestamp;
  } catch (err) {
    result.error = `Verification error: ${err.message}`;
  }
  
  return result;
}

/**
 * Generates a new Ed25519 key pair for signing claims.
 * 
 * @returns {Object} Key pair
 * @returns {Uint8Array} returns.publicKey - 32-byte public key
 * @returns {Uint8Array} returns.secretKey - 64-byte secret key
 * @returns {string} returns.publicKeyBase64 - Base64-encoded public key
 * 
 * @example
 * const keys = generateKeyPair();
 * // Store keys.secretKey securely
 * // Publish keys.publicKeyBase64 for verification
 */
function generateKeyPair() {
  const keyPair = nacl.sign.keyPair();
  return {
    publicKey: keyPair.publicKey,
    secretKey: keyPair.secretKey,
    publicKeyBase64: Buffer.from(keyPair.publicKey).toString('base64')
  };
}

/**
 * Adds a co-signatory endorsement to a claim.
 * 
 * @param {Object} claim - The claim to co-sign
 * @param {Uint8Array} secretKey - The co-signer's secret key
 * @param {string} agentUri - URI of the co-signing agent
 * @param {Object} [options] - Co-signing options
 * @param {string} [options.endorsementType='full'] - Type of endorsement
 * @returns {Object} The claim with co-signatory added
 * 
 * @example
 * const coSignedClaim = addCoSignatory(
 *   claim,
 *   coSignerKeys.secretKey,
 *   'emet:agent:gpt-4-turbo',
 *   { endorsementType: 'methodology-only' }
 * );
 */
function addCoSignatory(claim, secretKey, agentUri, options = {}) {
  const { endorsementType = 'full' } = options;
  
  const publicKey = secretKey.slice(32);
  const claimHash = hashClaim(claim, { encoding: 'buffer' });
  const signatureBytes = nacl.sign.detached(claimHash, secretKey);
  
  const coSignature = {
    agent: agentUri,
    signature: {
      claimId: claim.id,
      signer: agentUri,
      algorithm: SignatureAlgorithm.ED25519,
      publicKey: Buffer.from(publicKey).toString('base64'),
      signature: Buffer.from(signatureBytes).toString('base64'),
      timestamp: new Date().toISOString()
    },
    timestamp: new Date().toISOString(),
    endorsementType
  };
  
  return {
    ...claim,
    coSignatories: [...(claim.coSignatories || []), coSignature]
  };
}

/**
 * Verifies all co-signatories on a claim.
 * 
 * @param {Object} claim - The claim with co-signatories
 * @returns {Object[]} Array of verification results for each co-signatory
 */
function verifyCoSignatories(claim) {
  if (!claim.coSignatories || claim.coSignatories.length === 0) {
    return [];
  }
  
  const claimHash = hashClaim(claim, { encoding: 'buffer' });
  
  return claim.coSignatories.map(coSig => {
    const result = {
      agent: coSig.agent,
      endorsementType: coSig.endorsementType,
      valid: false
    };
    
    try {
      const publicKey = new Uint8Array(Buffer.from(coSig.signature.publicKey, 'base64'));
      const signatureBytes = new Uint8Array(Buffer.from(coSig.signature.signature, 'base64'));
      result.valid = nacl.sign.detached.verify(claimHash, signatureBytes, publicKey);
    } catch (err) {
      result.error = err.message;
    }
    
    return result;
  });
}

module.exports = {
  // Core functions
  createClaim,
  signClaim,
  verifyClaim,
  hashClaim,
  
  // Key management
  generateKeyPair,
  
  // Co-signing
  addCoSignatory,
  verifyCoSignatories,
  
  // Constants
  ClaimType,
  SignatureAlgorithm
};
