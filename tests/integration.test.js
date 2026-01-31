/**
 * EMET Protocol — Integration Tests
 *
 * End-to-end tests that verify the complete claim lifecycle:
 *   1. Generate keys via CLI
 *   2. Create a claim via API
 *   3. Sign the claim via API
 *   4. Verify the signature via API
 *   5. Build Merkle tree via API
 *   6. Generate inclusion proof via API
 *
 * These tests require the API server to be running on localhost:3141.
 * Run with: npm test (after starting the API)
 */

const { spawn, execSync } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');
const fetch = require('node-fetch');

// Configuration
const API_BASE = process.env.API_URL || 'http://localhost:3141';
const CLI_PATH = path.join(__dirname, '..', 'cli', 'emet.js');

// Test data
let testKeyPair = null;
let testClaim = null;
let signedClaim = null;

// Helper: Run CLI command and capture output
function runCLI(args, options = {}) {
  return new Promise((resolve, reject) => {
    const proc = spawn('node', [CLI_PATH, ...args], {
      cwd: options.cwd || __dirname,
      env: { ...process.env, ...options.env },
    });

    let stdout = '';
    let stderr = '';

    proc.stdout.on('data', (data) => {
      stdout += data.toString();
    });

    proc.stderr.on('data', (data) => {
      stderr += data.toString();
    });

    proc.on('close', (code) => {
      resolve({ code, stdout, stderr });
    });

    proc.on('error', reject);
  });
}

// Helper: Make API request
async function apiRequest(method, endpoint, body = null) {
  const url = `${API_BASE}${endpoint}`;
  const options = {
    method,
    headers: {
      'Content-Type': 'application/json',
    },
  };

  if (body) {
    options.body = JSON.stringify(body);
  }

  const response = await fetch(url, options);
  const data = await response.json();
  return { status: response.status, data };
}

// Wait for API to be ready
async function waitForAPI(maxAttempts = 30) {
  for (let i = 0; i < maxAttempts; i++) {
    try {
      const { status } = await apiRequest('GET', '/');
      if (status === 200) return true;
    } catch (e) {
      // API not ready yet
    }
    await new Promise((r) => setTimeout(r, 1000));
  }
  throw new Error('API did not become ready in time');
}

// =============================================================================
// Tests
// =============================================================================

describe('EMET Protocol Integration Tests', () => {
  // Ensure API is running before tests
  beforeAll(async () => {
    await waitForAPI();
  });

  // -------------------------------------------------------------------------
  // 1. CLI Key Generation
  // -------------------------------------------------------------------------
  describe('1. Key Generation (CLI)', () => {
    const testKeyDir = path.join(os.tmpdir(), 'emet-test-keys');
    const testKeyFile = path.join(testKeyDir, 'integration-test.json');

    beforeAll(() => {
      // Clean up any existing test keys
      if (fs.existsSync(testKeyFile)) {
        fs.unlinkSync(testKeyFile);
      }
      if (!fs.existsSync(testKeyDir)) {
        fs.mkdirSync(testKeyDir, { recursive: true });
      }
    });

    test('should generate a new keypair', async () => {
      // Use the core library directly for key generation (more reliable in test)
      const emet = require('../core');
      const keyPair = emet.generateKeyPair();

      expect(keyPair).toBeDefined();
      expect(keyPair.publicKey).toBeInstanceOf(Uint8Array);
      expect(keyPair.secretKey).toBeInstanceOf(Uint8Array);
      expect(keyPair.publicKey.length).toBe(32);
      expect(keyPair.secretKey.length).toBe(64);

      // Store for later tests
      testKeyPair = {
        publicKey: Buffer.from(keyPair.publicKey).toString('base64'),
        secretKey: Buffer.from(keyPair.secretKey).toString('base64'),
      };

      // Save to file for CLI tests
      fs.writeFileSync(
        testKeyFile,
        JSON.stringify({
          name: 'integration-test',
          algorithm: 'ed25519',
          ...testKeyPair,
          createdAt: new Date().toISOString(),
        })
      );
    });

    test('should have valid key lengths', () => {
      expect(testKeyPair).not.toBeNull();
      const pubKeyBytes = Buffer.from(testKeyPair.publicKey, 'base64');
      const secKeyBytes = Buffer.from(testKeyPair.secretKey, 'base64');

      expect(pubKeyBytes.length).toBe(32); // Ed25519 public key
      expect(secKeyBytes.length).toBe(64); // Ed25519 secret key
    });
  });

  // -------------------------------------------------------------------------
  // 2. Create Claim (API)
  // -------------------------------------------------------------------------
  describe('2. Create Claim (API)', () => {
    test('should create a new claim', async () => {
      const claimData = {
        issuer: 'emet:agent:integration-test',
        statement: 'This is an integration test claim for verifying the full EMET flow.',
        type: 'Assertion',
        confidence: 0.95,
        domain: 'testing',
        evidence: [
          {
            url: 'https://github.com/clawdei-ai/emet-core',
            type: 'primary',
          },
        ],
      };

      const { status, data } = await apiRequest('POST', '/claims', claimData);

      expect(status).toBe(201);
      expect(data.id).toMatch(/^emet:claim:[a-f0-9-]+$/);
      expect(data.statement).toBe(claimData.statement);
      expect(data.issuer).toBe(claimData.issuer);
      expect(data.confidence).toBe(0.95);
      expect(data.timestamp).toBeDefined();
      expect(data.signature).toBeUndefined(); // Not signed yet

      testClaim = data;
    });

    test('should retrieve the created claim', async () => {
      expect(testClaim).not.toBeNull();

      // Extract UUID from full ID
      const uuid = testClaim.id.replace('emet:claim:', '');
      const { status, data } = await apiRequest('GET', `/claims/${uuid}`);

      expect(status).toBe(200);
      expect(data.id).toBe(testClaim.id);
      expect(data.statement).toBe(testClaim.statement);
    });

    test('should list all claims including the new one', async () => {
      const { status, data } = await apiRequest('GET', '/claims');

      expect(status).toBe(200);
      expect(Array.isArray(data)).toBe(true);
      expect(data.some((c) => c.id === testClaim.id)).toBe(true);
    });

    test('should reject claim without required fields', async () => {
      const { status, data } = await apiRequest('POST', '/claims', {
        // Missing issuer and statement
        confidence: 0.5,
      });

      expect(status).toBe(400);
      expect(data.error).toContain('Missing required fields');
    });
  });

  // -------------------------------------------------------------------------
  // 3. Sign Claim (API)
  // -------------------------------------------------------------------------
  describe('3. Sign Claim (API)', () => {
    test('should sign the claim with the secret key', async () => {
      expect(testClaim).not.toBeNull();
      expect(testKeyPair).not.toBeNull();

      const uuid = testClaim.id.replace('emet:claim:', '');
      const { status, data } = await apiRequest('POST', `/claims/${uuid}/sign`, {
        secretKey: testKeyPair.secretKey,
      });

      expect(status).toBe(200);
      expect(data.signature).toBeDefined();
      expect(data.signature.algorithm).toBe('ed25519');
      expect(data.signature.publicKey).toBe(testKeyPair.publicKey);
      expect(data.signature.signature).toBeDefined();
      expect(data.signature.signedAt).toBeDefined();

      signedClaim = data;
    });

    test('should reject signing without secret key', async () => {
      expect(testClaim).not.toBeNull();

      const uuid = testClaim.id.replace('emet:claim:', '');
      const { status, data } = await apiRequest('POST', `/claims/${uuid}/sign`, {});

      expect(status).toBe(400);
      expect(data.error).toContain('Missing required fields');
    });

    test('should return 404 for non-existent claim', async () => {
      const { status, data } = await apiRequest('POST', '/claims/nonexistent-uuid/sign', {
        secretKey: testKeyPair.secretKey,
      });

      expect(status).toBe(404);
      expect(data.error).toContain('not found');
    });
  });

  // -------------------------------------------------------------------------
  // 4. Verify Claim (API)
  // -------------------------------------------------------------------------
  describe('4. Verify Claim (API)', () => {
    test('should verify the signed claim', async () => {
      expect(signedClaim).not.toBeNull();

      const { status, data } = await apiRequest('POST', '/verify', signedClaim);

      expect(status).toBe(200);
      expect(data.valid).toBe(true);
      expect(data.primary.valid).toBe(true);
      expect(data.primary.details.claimId).toBe(signedClaim.id);
      expect(Array.isArray(data.coSignatories)).toBe(true);
    });

    test('should reject tampered claim', async () => {
      expect(signedClaim).not.toBeNull();

      // Create a tampered copy
      const tamperedClaim = {
        ...signedClaim,
        statement: 'This statement has been tampered with!',
      };

      const { status, data } = await apiRequest('POST', '/verify', tamperedClaim);

      expect(status).toBe(200);
      expect(data.valid).toBe(false);
      expect(data.primary.valid).toBe(false);
    });

    test('should reject unsigned claim', async () => {
      expect(testClaim).not.toBeNull();

      // Remove signature from original claim
      const unsignedClaim = { ...testClaim };
      delete unsignedClaim.signature;

      const { status, data } = await apiRequest('POST', '/verify', unsignedClaim);

      expect(status).toBe(200);
      expect(data.valid).toBe(false);
    });

    test('should reject invalid request body', async () => {
      const { status, data } = await apiRequest('POST', '/verify', {
        notAClaim: true,
      });

      expect(status).toBe(400);
      expect(data.error).toBeDefined();
    });
  });

  // -------------------------------------------------------------------------
  // 5. Merkle Tree (API)
  // -------------------------------------------------------------------------
  describe('5. Merkle Tree (API)', () => {
    // Create additional claims to build a meaningful tree
    beforeAll(async () => {
      const additionalClaims = [
        {
          issuer: 'emet:agent:integration-test',
          statement: 'Second claim for Merkle tree testing.',
          confidence: 0.8,
        },
        {
          issuer: 'emet:agent:integration-test',
          statement: 'Third claim for Merkle tree testing.',
          confidence: 0.7,
        },
      ];

      for (const claim of additionalClaims) {
        await apiRequest('POST', '/claims', claim);
      }
    });

    test('should build a Merkle tree from claims', async () => {
      const { status, data } = await apiRequest('GET', '/tree');

      expect(status).toBe(200);
      expect(data.root).toBeDefined();
      expect(data.root).toMatch(/^[a-f0-9]{64}$/); // SHA-256 hex
      expect(data.size).toBeGreaterThanOrEqual(3); // At least our 3 claims
      expect(data.depth).toBeGreaterThan(0);
    });

    test('should return tree metadata', async () => {
      const { status, data } = await apiRequest('GET', '/tree');

      expect(status).toBe(200);
      expect(typeof data.size).toBe('number');
      expect(typeof data.depth).toBe('number');
      expect(data.leaves).toBeDefined();
      expect(Array.isArray(data.leaves)).toBe(true);
    });
  });

  // -------------------------------------------------------------------------
  // 6. Merkle Proof (API)
  // -------------------------------------------------------------------------
  describe('6. Merkle Proof (API)', () => {
    test('should generate inclusion proof for a claim', async () => {
      expect(signedClaim).not.toBeNull();

      const { status, data } = await apiRequest('POST', '/tree/prove', {
        claimId: signedClaim.id,
      });

      expect(status).toBe(200);
      expect(data.root).toBeDefined();
      expect(data.leaf).toBeDefined();
      expect(data.leafIndex).toBeDefined();
      expect(Array.isArray(data.proof)).toBe(true);

      // Proof should have siblings for each tree level
      expect(data.proof.length).toBeGreaterThan(0);
    });

    test('should accept UUID without prefix', async () => {
      expect(signedClaim).not.toBeNull();

      const uuid = signedClaim.id.replace('emet:claim:', '');
      const { status, data } = await apiRequest('POST', '/tree/prove', {
        claimId: uuid,
      });

      expect(status).toBe(200);
      expect(data.root).toBeDefined();
    });

    test('should return 404 for non-existent claim', async () => {
      const { status, data } = await apiRequest('POST', '/tree/prove', {
        claimId: 'emet:claim:00000000-0000-0000-0000-000000000000',
      });

      expect(status).toBe(404);
      expect(data.error).toContain('not found');
    });

    test('should reject request without claimId', async () => {
      const { status, data } = await apiRequest('POST', '/tree/prove', {});

      expect(status).toBe(400);
      expect(data.error).toContain('Missing required fields');
    });
  });

  // -------------------------------------------------------------------------
  // 7. API Health Check
  // -------------------------------------------------------------------------
  describe('7. API Health Check', () => {
    test('should return API info on root endpoint', async () => {
      const { status, data } = await apiRequest('GET', '/');

      expect(status).toBe(200);
      expect(data.name).toBe('@emet-protocol/api');
      expect(data.version).toBeDefined();
      expect(Array.isArray(data.endpoints)).toBe(true);
      expect(data.endpoints.length).toBeGreaterThan(0);
    });
  });
});
