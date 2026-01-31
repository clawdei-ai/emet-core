/**
 * EMET Protocol — SQLite Database Tests
 * 
 * Tests for the database layer including migrations, claims, and reputation.
 */

const { getTestDatabase, getSchemaVersion, MIGRATIONS } = require('./index');
const { createClaimsStore } = require('./claims');
const { createReputationStore, BASELINE_REPUTATION } = require('./reputation');

describe('Database Migrations', () => {
  let db;
  
  beforeEach(() => {
    db = getTestDatabase();
  });
  
  afterEach(() => {
    db.close();
  });
  
  test('should run all migrations on fresh database', () => {
    const version = getSchemaVersion(db);
    expect(version).toBe(MIGRATIONS.length);
  });
  
  test('should create all required tables', () => {
    const tables = db.prepare(`
      SELECT name FROM sqlite_master WHERE type='table' ORDER BY name
    `).all().map(r => r.name);
    
    expect(tables).toContain('claims');
    expect(tables).toContain('signatures');
    expect(tables).toContain('co_signatories');
    expect(tables).toContain('agents');
    expect(tables).toContain('agent_claims');
    expect(tables).toContain('verification_results');
    expect(tables).toContain('migrations');
  });
  
  test('should create all required indexes', () => {
    const indexes = db.prepare(`
      SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%'
    `).all().map(r => r.name);
    
    expect(indexes).toContain('idx_claims_issuer');
    expect(indexes).toContain('idx_claims_type');
    expect(indexes).toContain('idx_signatures_claim');
  });
  
  test('should track migration history', () => {
    const migrations = db.prepare('SELECT * FROM migrations ORDER BY version').all();
    
    expect(migrations.length).toBe(MIGRATIONS.length);
    expect(migrations[0].name).toBe('initial_schema');
    expect(migrations[0].applied_at).toBeDefined();
  });
});

describe('Claims Store', () => {
  let db;
  let store;
  
  const testClaim = {
    id: 'emet:claim:test-123',
    type: 'Assertion',
    issuer: 'emet:agent:test-agent',
    content: {
      statement: 'Water boils at 100°C at sea level.',
      domain: 'physics',
      scope: 'contextual'
    },
    evidence: [
      { url: 'https://example.com/source', type: 'primary', retrievedAt: '2024-01-01T00:00:00Z' }
    ],
    confidence: 0.99,
    timestamp: '2024-01-01T00:00:00Z',
    version: '1.0.0',
    coSignatories: []
  };
  
  beforeEach(() => {
    db = getTestDatabase();
    store = createClaimsStore(db);
  });
  
  afterEach(() => {
    db.close();
  });
  
  describe('put()', () => {
    test('should store a claim', () => {
      const result = store.put(testClaim);
      expect(result).toEqual(testClaim);
      
      const stored = store.get(testClaim.id);
      expect(stored.id).toBe(testClaim.id);
      expect(stored.issuer).toBe(testClaim.issuer);
      expect(stored.content.statement).toBe(testClaim.content.statement);
    });
    
    test('should update an existing claim', () => {
      store.put(testClaim);
      
      const updated = { ...testClaim, confidence: 0.75 };
      store.put(updated);
      
      const stored = store.get(testClaim.id);
      expect(stored.confidence).toBe(0.75);
    });
    
    test('should store claim with signature', () => {
      const signedClaim = {
        ...testClaim,
        signature: {
          claimId: testClaim.id,
          signer: testClaim.issuer,
          algorithm: 'ed25519',
          publicKey: 'dGVzdC1wdWJsaWMta2V5',
          signature: 'dGVzdC1zaWduYXR1cmU=',
          timestamp: '2024-01-01T00:00:00Z',
          canonicalization: 'jcs',
          hashAlgorithm: 'sha256'
        }
      };
      
      store.put(signedClaim);
      const stored = store.get(testClaim.id);
      
      expect(stored.signature).toBeDefined();
      expect(stored.signature.algorithm).toBe('ed25519');
      expect(stored.signature.publicKey).toBe('dGVzdC1wdWJsaWMta2V5');
    });
    
    test('should store claim with co-signatories', () => {
      const coSignedClaim = {
        ...testClaim,
        coSignatories: [
          {
            agent: 'emet:agent:co-signer',
            endorsementType: 'full',
            timestamp: '2024-01-01T00:00:00Z',
            signature: {
              claimId: testClaim.id,
              signer: 'emet:agent:co-signer',
              algorithm: 'ed25519',
              publicKey: 'Y28tc2lnbmVyLWtleQ==',
              signature: 'Y28tc2lnbmF0dXJl',
              timestamp: '2024-01-01T00:00:00Z'
            }
          }
        ]
      };
      
      store.put(coSignedClaim);
      const stored = store.get(testClaim.id);
      
      expect(stored.coSignatories).toHaveLength(1);
      expect(stored.coSignatories[0].agent).toBe('emet:agent:co-signer');
      expect(stored.coSignatories[0].endorsementType).toBe('full');
    });
  });
  
  describe('get()', () => {
    test('should return null for non-existent claim', () => {
      const result = store.get('emet:claim:does-not-exist');
      expect(result).toBeNull();
    });
    
    test('should retrieve stored claim with all fields', () => {
      store.put(testClaim);
      const stored = store.get(testClaim.id);
      
      expect(stored.id).toBe(testClaim.id);
      expect(stored.type).toBe(testClaim.type);
      expect(stored.issuer).toBe(testClaim.issuer);
      expect(stored.content).toEqual(testClaim.content);
      expect(stored.evidence).toEqual(testClaim.evidence);
      expect(stored.confidence).toBe(testClaim.confidence);
      expect(stored.timestamp).toBe(testClaim.timestamp);
      expect(stored.version).toBe(testClaim.version);
    });
  });
  
  describe('list()', () => {
    beforeEach(() => {
      // Add multiple claims
      store.put(testClaim);
      store.put({
        ...testClaim,
        id: 'emet:claim:test-456',
        type: 'Correction',
        timestamp: '2024-01-02T00:00:00Z'
      });
      store.put({
        ...testClaim,
        id: 'emet:claim:test-789',
        issuer: 'emet:agent:other-agent',
        timestamp: '2024-01-03T00:00:00Z'
      });
    });
    
    test('should return all claims', () => {
      const claims = store.list();
      expect(claims.length).toBe(3);
    });
    
    test('should filter by issuer', () => {
      const claims = store.list({ issuer: 'emet:agent:test-agent' });
      expect(claims.length).toBe(2);
    });
    
    test('should filter by type', () => {
      const claims = store.list({ type: 'Correction' });
      expect(claims.length).toBe(1);
      expect(claims[0].id).toBe('emet:claim:test-456');
    });
    
    test('should support limit and offset', () => {
      const page1 = store.list({ limit: 2 });
      expect(page1.length).toBe(2);
      
      const page2 = store.list({ limit: 2, offset: 2 });
      expect(page2.length).toBe(1);
    });
    
    test('should order by timestamp descending by default', () => {
      const claims = store.list();
      expect(claims[0].id).toBe('emet:claim:test-789');
      expect(claims[2].id).toBe('emet:claim:test-123');
    });
  });
  
  describe('del()', () => {
    test('should delete an existing claim', () => {
      store.put(testClaim);
      const deleted = store.del(testClaim.id);
      
      expect(deleted).toBe(true);
      expect(store.get(testClaim.id)).toBeNull();
    });
    
    test('should return false for non-existent claim', () => {
      const deleted = store.del('emet:claim:does-not-exist');
      expect(deleted).toBe(false);
    });
    
    test('should cascade delete signatures', () => {
      const signedClaim = {
        ...testClaim,
        signature: {
          claimId: testClaim.id,
          signer: testClaim.issuer,
          algorithm: 'ed25519',
          publicKey: 'a2V5',
          signature: 'c2ln',
          timestamp: '2024-01-01T00:00:00Z'
        }
      };
      
      store.put(signedClaim);
      store.del(testClaim.id);
      
      const signatures = db.prepare(
        'SELECT * FROM signatures WHERE claim_id = ?'
      ).all(testClaim.id);
      
      expect(signatures.length).toBe(0);
    });
  });
  
  describe('count()', () => {
    test('should count all claims', () => {
      store.put(testClaim);
      store.put({ ...testClaim, id: 'emet:claim:test-456' });
      
      expect(store.count()).toBe(2);
    });
    
    test('should count with filters', () => {
      store.put(testClaim);
      store.put({ ...testClaim, id: 'emet:claim:test-456', type: 'Correction' });
      
      expect(store.count({ type: 'Assertion' })).toBe(1);
    });
  });
  
  describe('readAll()', () => {
    test('should return claims as a map', () => {
      store.put(testClaim);
      store.put({ ...testClaim, id: 'emet:claim:test-456' });
      
      const map = store.readAll();
      
      expect(Object.keys(map).length).toBe(2);
      expect(map['emet:claim:test-123']).toBeDefined();
      expect(map['emet:claim:test-456']).toBeDefined();
    });
  });
  
  describe('clear()', () => {
    test('should remove all claims', () => {
      store.put(testClaim);
      store.put({ ...testClaim, id: 'emet:claim:test-456' });
      
      store.clear();
      
      expect(store.count()).toBe(0);
    });
  });
});

describe('Reputation Store', () => {
  let db;
  let store;
  let claimsStore;
  
  const testAgentId = 'emet:agent:test-agent';
  const testClaimId = 'emet:claim:test-123';
  
  beforeEach(() => {
    db = getTestDatabase();
    store = createReputationStore(db);
    claimsStore = createClaimsStore(db);
    
    // Create a test claim for foreign key references
    claimsStore.put({
      id: testClaimId,
      type: 'Assertion',
      issuer: testAgentId,
      content: { statement: 'test' },
      evidence: [],
      confidence: 0.5,
      timestamp: new Date().toISOString(),
      version: '1.0.0',
      coSignatories: []
    });
  });
  
  afterEach(() => {
    db.close();
  });
  
  describe('getReputation()', () => {
    test('should return baseline for new agent', () => {
      const rep = store.getReputation(testAgentId);
      
      expect(rep.score).toBe(BASELINE_REPUTATION.score);
      expect(rep.claims).toBe(0);
      expect(rep.verifications).toBe(0);
      expect(rep.accuracy).toBe(BASELINE_REPUTATION.accuracy);
    });
    
    test('should create agent on first access', () => {
      store.getReputation(testAgentId);
      expect(store.hasAgent(testAgentId)).toBe(true);
    });
  });
  
  describe('recordClaim()', () => {
    test('should record a new claim', () => {
      const recorded = store.recordClaim(testAgentId, testClaimId);
      
      expect(recorded).toBe(true);
      
      const rep = store.getReputation(testAgentId);
      expect(rep.claims).toBe(1);
    });
    
    test('should reject duplicate claims', () => {
      store.recordClaim(testAgentId, testClaimId);
      const duplicate = store.recordClaim(testAgentId, testClaimId);
      
      expect(duplicate).toBe(false);
      
      const rep = store.getReputation(testAgentId);
      expect(rep.claims).toBe(1);
    });
    
    test('should track claims per agent', () => {
      store.recordClaim(testAgentId, testClaimId);
      
      const claims = store.getAgentClaims(testAgentId);
      expect(claims).toContain(testClaimId);
    });
  });
  
  describe('recordVerification()', () => {
    test('should increase score on correct verification', () => {
      const before = store.getReputation(testAgentId);
      store.recordVerification(testAgentId, testClaimId, true);
      const after = store.getReputation(testAgentId);
      
      expect(after.score).toBeGreaterThan(before.score);
      expect(after.verifications).toBe(1);
      expect(after.accuracy).toBe(1.0);
    });
    
    test('should decrease score on incorrect verification', () => {
      const before = store.getReputation(testAgentId);
      store.recordVerification(testAgentId, testClaimId, false);
      const after = store.getReputation(testAgentId);
      
      expect(after.score).toBeLessThan(before.score);
      expect(after.accuracy).toBe(0);
    });
    
    test('should track verification history', () => {
      store.recordVerification(testAgentId, testClaimId, true);
      store.recordVerification(testAgentId, 'emet:claim:other', false);
      
      const history = store.getVerificationHistory(testAgentId);
      
      expect(history.length).toBe(2);
      // Both results should be present
      const results = history.map(h => h.result);
      expect(results).toContain(true);
      expect(results).toContain(false);
    });
    
    test('should calculate correct accuracy', () => {
      store.recordVerification(testAgentId, 'claim1', true);
      store.recordVerification(testAgentId, 'claim2', true);
      store.recordVerification(testAgentId, 'claim3', false);
      
      const rep = store.getReputation(testAgentId);
      expect(rep.accuracy).toBeCloseTo(2/3);
    });
  });
  
  describe('calculateTrust()', () => {
    test('should return 0 for agent with no claims', () => {
      const trust = store.calculateTrust(testAgentId);
      expect(trust).toBe(0);
    });
    
    test('should increase with more verified claims', () => {
      store.recordClaim(testAgentId, testClaimId);
      store.recordVerification(testAgentId, testClaimId, true);
      
      const trust = store.calculateTrust(testAgentId);
      expect(trust).toBeGreaterThan(0);
    });
  });
  
  describe('applyDecay()', () => {
    test('should decay inactive agent scores', () => {
      store.recordVerification(testAgentId, testClaimId, true);
      store.recordVerification(testAgentId, testClaimId, true);
      
      const before = store.getReputation(testAgentId);
      
      // Force agent's last_activity to the past so decay kicks in
      db.prepare('UPDATE agents SET last_activity = ? WHERE id = ?')
        .run(Date.now() - 200000, testAgentId);
      
      store.applyDecay(0.1, 100000); // 100s threshold
      
      const after = store.getReputation(testAgentId);
      expect(after.score).toBeLessThan(before.score);
    });
  });
  
  describe('getLeaderboard()', () => {
    test('should return agents sorted by trust', () => {
      // Create two agents with different trust levels
      store.recordClaim(testAgentId, testClaimId);
      store.recordVerification(testAgentId, testClaimId, true);
      
      const otherAgent = 'emet:agent:other';
      store.getReputation(otherAgent); // Create but don't add claims
      
      const leaderboard = store.getLeaderboard(10);
      
      expect(leaderboard.length).toBe(2);
      expect(leaderboard[0].agentId).toBe(testAgentId);
    });
    
    test('should respect limit parameter', () => {
      store.getReputation('agent1');
      store.getReputation('agent2');
      store.getReputation('agent3');
      
      const leaderboard = store.getLeaderboard(2);
      expect(leaderboard.length).toBe(2);
    });
  });
  
  describe('getAllAgents()', () => {
    test('should return all agent IDs', () => {
      store.getReputation('agent1');
      store.getReputation('agent2');
      
      const agents = store.getAllAgents();
      expect(agents).toContain('agent1');
      expect(agents).toContain('agent2');
    });
  });
  
  describe('clear()', () => {
    test('should remove all reputation data', () => {
      store.recordClaim(testAgentId, testClaimId);
      store.recordVerification(testAgentId, testClaimId, true);
      
      store.clear();
      
      expect(store.getAllAgents().length).toBe(0);
    });
  });
});
