/**
 * EMET Protocol — API Integration Tests with SQLite
 * 
 * Tests the Express API endpoints with SQLite persistence.
 */

// Mock the db/index module to use in-memory test database
jest.mock('./index', () => {
  const actual = jest.requireActual('./index');
  const Database = require('better-sqlite3');
  
  let mockDb = null;
  
  return {
    ...actual,
    getDatabase: () => {
      if (!mockDb) {
        mockDb = new Database(':memory:');
        mockDb.pragma('foreign_keys = ON');
        actual.runMigrations(mockDb);
      }
      return mockDb;
    },
    closeDatabase: () => {
      if (mockDb) {
        mockDb.close();
        mockDb = null;
      }
    }
  };
});

const request = require('supertest');
const app = require('../server');

afterAll(() => {
  const { closeDatabase } = require('./index');
  closeDatabase();
});

describe('API Endpoints with SQLite', () => {
  
  describe('GET /', () => {
    test('should return API info with SQLite storage', async () => {
      const res = await request(app).get('/');
      
      expect(res.status).toBe(200);
      expect(res.body.name).toBe('@emet-protocol/api');
      expect(res.body.version).toBe('0.4.0');
      expect(res.body.storage).toBe('sqlite');
      expect(res.body.schemaVersion).toBe(1);
    });
  });
  
  describe('POST /claims', () => {
    test('should create a claim and persist it', async () => {
      const res = await request(app)
        .post('/claims')
        .send({
          issuer: 'emet:agent:test-agent',
          statement: 'Test claim for SQLite persistence',
          confidence: 0.95,
          domain: 'testing'
        });
      
      expect(res.status).toBe(201);
      expect(res.body.id).toMatch(/^emet:claim:/);
      expect(res.body.confidence).toBe(0.95);
    });
    
    test('should reject claims without required fields', async () => {
      const res = await request(app)
        .post('/claims')
        .send({ confidence: 0.5 });
      
      expect(res.status).toBe(400);
      expect(res.body.error).toContain('Missing required fields');
    });
  });
  
  describe('GET /claims', () => {
    test('should list all claims', async () => {
      const res = await request(app).get('/claims');
      
      expect(res.status).toBe(200);
      expect(Array.isArray(res.body)).toBe(true);
      expect(res.body.length).toBeGreaterThanOrEqual(1);
    });
    
    test('should filter by issuer', async () => {
      await request(app)
        .post('/claims')
        .send({
          issuer: 'emet:agent:unique-filter-test',
          statement: 'Unique issuer claim'
        });
      
      const res = await request(app)
        .get('/claims?issuer=emet:agent:unique-filter-test');
      
      expect(res.status).toBe(200);
      expect(res.body.every(c => c.issuer === 'emet:agent:unique-filter-test')).toBe(true);
    });
  });
  
  describe('GET /claims/:id', () => {
    let claimId;
    
    beforeAll(async () => {
      const res = await request(app)
        .post('/claims')
        .send({
          issuer: 'emet:agent:get-test',
          statement: 'Claim for GET test'
        });
      claimId = res.body.id;
    });
    
    test('should retrieve claim by full ID', async () => {
      const res = await request(app).get(`/claims/${claimId}`);
      
      expect(res.status).toBe(200);
      expect(res.body.id).toBe(claimId);
    });
    
    test('should retrieve claim by UUID only', async () => {
      const uuid = claimId.replace('emet:claim:', '');
      const res = await request(app).get(`/claims/${uuid}`);
      
      expect(res.status).toBe(200);
      expect(res.body.id).toBe(claimId);
    });
    
    test('should return 404 for non-existent claim', async () => {
      const res = await request(app).get('/claims/does-not-exist');
      expect(res.status).toBe(404);
    });
  });
  
  describe('Signing and Verification flow', () => {
    let claimId;
    let secretKeyBase64;
    let signedClaim;
    
    beforeAll(async () => {
      const emet = require('../../core');
      const keyPair = emet.generateKeyPair();
      secretKeyBase64 = Buffer.from(keyPair.secretKey).toString('base64');
      
      const res = await request(app)
        .post('/claims')
        .send({
          issuer: 'emet:agent:sign-test',
          statement: 'Claim for signing test'
        });
      claimId = res.body.id;
    });
    
    test('should sign a claim', async () => {
      const uuid = claimId.replace('emet:claim:', '');
      const res = await request(app)
        .post(`/claims/${uuid}/sign`)
        .send({ secretKey: secretKeyBase64 });
      
      expect(res.status).toBe(200);
      expect(res.body.signature).toBeDefined();
      expect(res.body.signature.algorithm).toBe('ed25519');
      
      signedClaim = res.body;
    });
    
    test('should persist signature to SQLite', async () => {
      const res = await request(app).get(`/claims/${claimId}`);
      
      expect(res.status).toBe(200);
      expect(res.body.signature).toBeDefined();
      expect(res.body.signature.algorithm).toBe('ed25519');
    });
    
    test('should verify a valid signed claim', async () => {
      const res = await request(app)
        .post('/verify')
        .send(signedClaim);
      
      expect(res.status).toBe(200);
      expect(res.body.valid).toBe(true);
    });
    
    test('should reject tampered claim', async () => {
      const tampered = {
        ...signedClaim,
        content: { ...signedClaim.content, statement: 'TAMPERED' }
      };
      
      const res = await request(app)
        .post('/verify')
        .send(tampered);
      
      expect(res.status).toBe(200);
      expect(res.body.valid).toBe(false);
    });
  });
  
  describe('DELETE /claims/:id', () => {
    test('should delete an existing claim', async () => {
      const createRes = await request(app)
        .post('/claims')
        .send({
          issuer: 'emet:agent:delete-test',
          statement: 'Claim for deletion test'
        });
      
      const uuid = createRes.body.id.replace('emet:claim:', '');
      const deleteRes = await request(app).delete(`/claims/${uuid}`);
      
      expect(deleteRes.status).toBe(204);
      
      const getRes = await request(app).get(`/claims/${uuid}`);
      expect(getRes.status).toBe(404);
    });
  });
  
  describe('Reputation endpoints', () => {
    test('GET /reputation/:agentId returns reputation', async () => {
      const res = await request(app).get('/reputation/test-rep-agent');
      
      expect(res.status).toBe(200);
      expect(res.body.agentId).toBe('emet:agent:test-rep-agent');
      expect(res.body.score).toBeDefined();
      expect(res.body.trust).toBeDefined();
    });
    
    test('POST /reputation/:agentId/verify records result', async () => {
      const res = await request(app)
        .post('/reputation/test-rep-agent/verify')
        .send({
          claimId: 'emet:claim:some-claim',
          result: true
        });
      
      expect(res.status).toBe(200);
      expect(res.body.verifications).toBeGreaterThan(0);
    });
    
    test('GET /leaderboard returns agent leaderboard', async () => {
      const res = await request(app).get('/leaderboard');
      
      expect(res.status).toBe(200);
      expect(Array.isArray(res.body)).toBe(true);
    });
  });
  
  describe('GET /db/stats', () => {
    test('should return database statistics', async () => {
      const res = await request(app).get('/db/stats');
      
      expect(res.status).toBe(200);
      expect(res.body.storage).toBe('sqlite');
      expect(res.body.schemaVersion).toBe(1);
      expect(typeof res.body.claims).toBe('number');
      expect(typeof res.body.agents).toBe('number');
    });
  });
});
