/**
 * EMET Protocol — Claim Module Tests
 */

const nacl = require('tweetnacl');
const {
  createClaim,
  signClaim,
  verifyClaim,
  hashClaim,
  generateKeyPair,
  addCoSignatory,
  verifyCoSignatories,
  ClaimType
} = require('../claim');

// Deterministic helpers
const baseClaim = () => createClaim({
  issuer: 'emet:agent:test-agent',
  statement: 'Water boils at 100 °C at sea level.',
  domain: 'physics',
  confidence: 0.99
});

describe('createClaim()', () => {
  test('returns object with all required fields', () => {
    const c = baseClaim();
    expect(c).toHaveProperty('id');
    expect(c.id).toMatch(/^emet:claim:/);
    expect(c).toHaveProperty('type', 'Assertion');
    expect(c).toHaveProperty('issuer', 'emet:agent:test-agent');
    expect(c.content).toHaveProperty('statement', 'Water boils at 100 °C at sea level.');
    expect(c.content).toHaveProperty('domain', 'physics');
    expect(c).toHaveProperty('confidence', 0.99);
    expect(c).toHaveProperty('timestamp');
    expect(c).toHaveProperty('version', '1.0.0');
    expect(c).toHaveProperty('coSignatories');
    expect(Array.isArray(c.coSignatories)).toBe(true);
  });

  test('supports all claim types', () => {
    for (const type of Object.values(ClaimType)) {
      const c = createClaim({
        issuer: 'emet:agent:x',
        statement: 'test',
        type
      });
      expect(c.type).toBe(type);
    }
  });

  test('throws on missing issuer', () => {
    expect(() => createClaim({ statement: 'hello' })).toThrow('issuer is required');
  });

  test('throws on missing statement', () => {
    expect(() => createClaim({ issuer: 'emet:agent:x' })).toThrow('statement is required');
  });

  test('throws on invalid confidence', () => {
    expect(() =>
      createClaim({ issuer: 'emet:agent:x', statement: 'x', confidence: 1.5 })
    ).toThrow(RangeError);
    expect(() =>
      createClaim({ issuer: 'emet:agent:x', statement: 'x', confidence: -0.1 })
    ).toThrow(RangeError);
  });

  test('throws on invalid claim type', () => {
    expect(() =>
      createClaim({ issuer: 'emet:agent:x', statement: 'x', type: 'Bogus' })
    ).toThrow('Invalid claim type');
  });

  test('includes caveats and evidence when provided', () => {
    const c = createClaim({
      issuer: 'emet:agent:x',
      statement: 'x',
      caveats: ['caveat1'],
      evidence: [{ url: 'https://example.com', type: 'primary' }]
    });
    expect(c.content.caveats).toEqual(['caveat1']);
    expect(c.evidence).toHaveLength(1);
    expect(c.evidence[0].url).toBe('https://example.com');
  });
});

describe('hashClaim()', () => {
  test('returns a 64-char hex string (SHA-256)', () => {
    const hash = hashClaim(baseClaim());
    expect(hash).toMatch(/^[0-9a-f]{64}$/);
  });

  test('is deterministic — same input yields same hash', () => {
    const c = baseClaim();
    expect(hashClaim(c)).toBe(hashClaim(c));
  });

  test('different claims produce different hashes', () => {
    const a = baseClaim();
    const b = createClaim({
      issuer: 'emet:agent:other',
      statement: 'Something else entirely.',
    });
    expect(hashClaim(a)).not.toBe(hashClaim(b));
  });

  test('excludes signature field by default', () => {
    const c = baseClaim();
    const withSig = { ...c, signature: { bogus: true } };
    expect(hashClaim(c)).toBe(hashClaim(withSig));
  });

  test('supports buffer encoding', () => {
    const buf = hashClaim(baseClaim(), { encoding: 'buffer' });
    expect(Buffer.isBuffer(buf)).toBe(true);
    expect(buf.length).toBe(32);
  });
});

describe('signClaim() / verifyClaim()', () => {
  let keys;
  beforeAll(() => {
    keys = generateKeyPair();
  });

  test('signClaim attaches a valid signature object', () => {
    const c = baseClaim();
    const signed = signClaim(c, keys.secretKey);

    expect(signed.signature).toBeDefined();
    expect(signed.signature.algorithm).toBe('ed25519');
    expect(signed.signature.publicKey).toBe(keys.publicKeyBase64);
    expect(signed.signature).toHaveProperty('signature');
    expect(signed.signature).toHaveProperty('timestamp');
  });

  test('verifyClaim succeeds on a correctly signed claim', () => {
    const signed = signClaim(baseClaim(), keys.secretKey);
    const result = verifyClaim(signed);
    expect(result.valid).toBe(true);
    expect(result.error).toBeUndefined();
  });

  test('verifyClaim fails when the statement is tampered', () => {
    const signed = signClaim(baseClaim(), keys.secretKey);
    signed.content.statement = 'TAMPERED';
    const result = verifyClaim(signed);
    expect(result.valid).toBe(false);
  });

  test('verifyClaim fails when the confidence is tampered', () => {
    const signed = signClaim(baseClaim(), keys.secretKey);
    signed.confidence = 0.01;
    const result = verifyClaim(signed);
    expect(result.valid).toBe(false);
  });

  test('verifyClaim fails with a different key pair', () => {
    const other = generateKeyPair();
    const signed = signClaim(baseClaim(), keys.secretKey);
    const result = verifyClaim(signed, { publicKey: other.publicKey });
    expect(result.valid).toBe(false);
  });

  test('verifyClaim returns error when signature is missing', () => {
    const result = verifyClaim(baseClaim());
    expect(result.valid).toBe(false);
    expect(result.error).toMatch(/no signature/i);
  });

  test('signClaim rejects invalid secret key', () => {
    expect(() => signClaim(baseClaim(), new Uint8Array(10))).toThrow(/invalid secret key/i);
  });
});

describe('addCoSignatory() / verifyCoSignatories()', () => {
  test('adds a co-signatory with correct structure', () => {
    const coKeys = generateKeyPair();
    const c = baseClaim();
    const coSigned = addCoSignatory(c, coKeys.secretKey, 'emet:agent:co-signer');

    expect(coSigned.coSignatories).toHaveLength(1);
    const co = coSigned.coSignatories[0];
    expect(co.agent).toBe('emet:agent:co-signer');
    expect(co.endorsementType).toBe('full');
    expect(co.signature.algorithm).toBe('ed25519');
    expect(co.signature.publicKey).toBe(coKeys.publicKeyBase64);
    expect(co.signature).toHaveProperty('signature');
    expect(co.signature).toHaveProperty('timestamp');
  });

  test('verifyCoSignatories returns empty array when none present', () => {
    const c = baseClaim();
    expect(verifyCoSignatories(c)).toEqual([]);
  });
});
