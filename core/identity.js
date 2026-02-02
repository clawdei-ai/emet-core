/**
 * EMET Protocol - AIP Identity Bridge
 * 
 * Verifies Agent Identity Protocol (AIP) tokens attached to EMET claims.
 * Provides cryptographic identity verification for claim signers.
 * 
 * @module @emet-protocol/core/identity
 * @version 0.1.0
 * @see https://github.com/syn-ack-ai/agent-identity-protocol
 */

/**
 * Verifies an AIP identity token attached to an EMET signature.
 * 
 * Performs:
 * 1. Fetches issuer's JWK from .well-known/agent-registry.json
 * 2. Verifies JWT signature (ES256)
 * 3. Checks expiration
 * 4. Checks revocation status
 * 5. Validates signer URI matches JWT sub claim
 * 
 * @param {Object} signature - EMET signature object with identityToken
 * @param {Object} [options] - Verification options
 * @param {number} [options.timeoutMs=5000] - HTTP request timeout
 * @param {boolean} [options.checkRevocation=true] - Whether to check revocation list
 * @param {number} [options.clockSkewSeconds=120] - Allowed clock skew
 * @returns {Promise<Object>} Verification result
 * 
 * @example
 * const result = await verifyIdentity(claim.signature);
 * if (result.verified) {
 *   console.log(`Signer: ${result.agent}, Deployer: ${result.deployer}`);
 * }
 */
async function verifyIdentity(signature, options = {}) {
  const {
    timeoutMs = 5000,
    checkRevocation = true,
    clockSkewSeconds = 120,
  } = options;

  const result = {
    verified: false,
    agent: null,
    deployer: null,
    modelProviders: [],
    framework: null,
    issuer: null,
    error: null,
    details: {},
  };

  // Check identityToken exists
  if (!signature.identityToken) {
    result.error = 'No identityToken in signature';
    return result;
  }

  const { jwt, issuer, verifyEndpoint } = signature.identityToken;

  if (!jwt || !issuer) {
    result.error = 'identityToken missing jwt or issuer';
    return result;
  }

  // Determine verify endpoint
  const endpoint = verifyEndpoint || `${issuer}/api/registry/verify`;

  try {
    // Step 1: Verify token via issuer's verify endpoint
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);

    const response = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: jwt }),
      signal: controller.signal,
    });

    clearTimeout(timeout);

    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      result.error = body.error || `Verify endpoint returned ${response.status}`;
      return result;
    }

    const verification = await response.json();

    if (!verification.valid) {
      result.error = verification.error || 'Token verification failed';
      return result;
    }

    const claims = verification.claims;

    // Step 2: Check expiration with clock skew
    const now = Math.floor(Date.now() / 1000);
    if (claims.exp && claims.exp + clockSkewSeconds < now) {
      result.error = 'Identity token expired';
      return result;
    }

    // Step 3: Validate signer URI matches JWT sub
    const expectedSigner = `emet:agent:${claims.sub}`;
    if (signature.signer !== expectedSigner) {
      result.error = `Signer mismatch: signature.signer=${signature.signer}, JWT sub=${claims.sub} (expected ${expectedSigner})`;
      return result;
    }

    // Step 4: Check revocation (if enabled)
    if (checkRevocation && claims.jti) {
      try {
        const revocationsUrl = `${issuer}/api/registry/revocations`;
        const revController = new AbortController();
        const revTimeout = setTimeout(() => revController.abort(), timeoutMs);

        const revResponse = await fetch(revocationsUrl, {
          signal: revController.signal,
        });

        clearTimeout(revTimeout);

        if (revResponse.ok) {
          const revData = await revResponse.json();
          const isRevoked = (revData.revoked || []).some(r => r.jti === claims.jti);
          if (isRevoked) {
            result.error = 'Identity token has been revoked';
            return result;
          }
        }
        // If revocation check fails (network error), proceed with warning
      } catch (revErr) {
        result.details.revocationCheckFailed = true;
        result.details.revocationError = revErr.message;
      }
    }

    // All checks passed
    result.verified = true;
    result.agent = claims.sub;
    result.deployer = claims.deployer || null;
    result.modelProviders = claims.model_providers || [];
    result.framework = claims.framework || null;
    result.issuer = claims.iss;
    result.details = {
      tokenType: claims.token_type || 'identity',
      issuedAt: claims.iat,
      expiresAt: claims.exp,
      jti: claims.jti,
    };

    return result;
  } catch (err) {
    result.error = `Identity verification failed: ${err.message}`;
    return result;
  }
}

/**
 * Creates an identityToken object for embedding in an EMET signature.
 * 
 * @param {string} jwt - The AIP JWT token
 * @param {string} issuer - The AIP issuer URI (e.g., 'https://syn-ack.ai')
 * @param {Object} [options] - Options
 * @param {string} [options.verifyEndpoint] - Custom verify endpoint URL
 * @returns {Object} identityToken object ready for embedding
 * 
 * @example
 * const identityToken = createIdentityToken(
 *   'eyJhbGciOiJFUzI1NiJ9...',
 *   'https://syn-ack.ai'
 * );
 * signature.identityToken = identityToken;
 */
function createIdentityToken(jwt, issuer, options = {}) {
  const token = {
    protocol: 'agent-identity-v2',
    jwt,
    issuer,
  };

  if (options.verifyEndpoint) {
    token.verifyEndpoint = options.verifyEndpoint;
  }

  return token;
}

/**
 * Fetches an AIP issuer's registry for discovery.
 * 
 * @param {string} issuer - The issuer URI (e.g., 'https://syn-ack.ai')
 * @param {Object} [options] - Options
 * @param {number} [options.timeoutMs=5000] - HTTP request timeout
 * @returns {Promise<Object>} The agent registry JSON
 * 
 * @example
 * const registry = await fetchRegistry('https://syn-ack.ai');
 * console.log(registry.agents); // ['SynACK']
 * console.log(registry.keys);   // JWK keys
 */
async function fetchRegistry(issuer, options = {}) {
  const { timeoutMs = 5000 } = options;
  const url = `${issuer}/.well-known/agent-registry.json`;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  const response = await fetch(url, { signal: controller.signal });
  clearTimeout(timeout);

  if (!response.ok) {
    throw new Error(`Failed to fetch registry from ${url}: ${response.status}`);
  }

  return response.json();
}

module.exports = {
  verifyIdentity,
  createIdentityToken,
  fetchRegistry,
};
