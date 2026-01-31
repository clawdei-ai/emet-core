/**
 * EMET Protocol — BLS Signature Aggregation Tests
 *
 * Tests cover key generation, single-signer signing/verification,
 * multi-signer aggregation (3, 5, 10 signers), and failure modes
 * (wrong key, mismatched messages).
 */

const {
  generateBLSKeyPair,
  createPartialSignature,
  aggregateSignatures,
  verifyAggregate,
} = require('../../proofs/bls');

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Generate `n` independent key pairs. */
function generateKeyPairs(n) {
  return Array.from({ length: n }, () => generateBLSKeyPair());
}

/** Have every key pair sign `message` and return the signatures. */
async function signAll(message, keyPairs) {
  return Promise.all(
    keyPairs.map((kp) => createPartialSignature(message, kp.privateKey)),
  );
}

// ---------------------------------------------------------------------------
// Key generation
// ---------------------------------------------------------------------------

describe('generateBLSKeyPair()', () => {
  test('returns publicKey (48 bytes) and privateKey (32 bytes)', () => {
    const { publicKey, privateKey } = generateBLSKeyPair();
    expect(publicKey).toBeInstanceOf(Uint8Array);
    expect(privateKey).toBeInstanceOf(Uint8Array);
    expect(publicKey.length).toBe(48);
    expect(privateKey.length).toBe(32);
  });

  test('produces unique key pairs on successive calls', () => {
    const a = generateBLSKeyPair();
    const b = generateBLSKeyPair();
    expect(Buffer.from(a.privateKey).equals(Buffer.from(b.privateKey))).toBe(false);
    expect(Buffer.from(a.publicKey).equals(Buffer.from(b.publicKey))).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Single signature
// ---------------------------------------------------------------------------

describe('createPartialSignature()', () => {
  test('signs a Uint8Array message and produces a 96-byte signature', async () => {
    const { privateKey } = generateBLSKeyPair();
    const msg = new TextEncoder().encode('EMET single-signer test');
    const sig = await createPartialSignature(msg, privateKey);
    expect(sig).toBeInstanceOf(Uint8Array);
    expect(sig.length).toBe(96);
  });

  test('signs a string message (auto-encodes to UTF-8)', async () => {
    const { privateKey } = generateBLSKeyPair();
    const sig = await createPartialSignature('string message', privateKey);
    expect(sig).toBeInstanceOf(Uint8Array);
    expect(sig.length).toBe(96);
  });

  test('single signature verifies via verifyAggregate with one key', async () => {
    const { publicKey, privateKey } = generateBLSKeyPair();
    const msg = 'emet:claim:single-verify';
    const sig = await createPartialSignature(msg, privateKey);
    // A single signature is trivially an "aggregate of 1"
    const valid = await verifyAggregate(msg, sig, [publicKey]);
    expect(valid).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Aggregation — varying signer counts
// ---------------------------------------------------------------------------

describe('aggregateSignatures()', () => {
  test.each([3, 5, 10])(
    'aggregates %i signatures and verifies correctly',
    async (n) => {
      const msg = `emet:claim:aggregate-${n}`;
      const keyPairs = generateKeyPairs(n);
      const sigs = await signAll(msg, keyPairs);

      const aggSig = aggregateSignatures(sigs);
      expect(aggSig).toBeInstanceOf(Uint8Array);
      expect(aggSig.length).toBe(96);

      const pubKeys = keyPairs.map((kp) => kp.publicKey);
      const valid = await verifyAggregate(msg, aggSig, pubKeys);
      expect(valid).toBe(true);
    },
  );

  test('throws when given fewer than 2 signatures', () => {
    const { privateKey } = generateBLSKeyPair();
    // zero
    expect(() => aggregateSignatures([])).toThrow();
    // one — still too few
    return createPartialSignature('x', privateKey).then((sig) => {
      expect(() => aggregateSignatures([sig])).toThrow();
    });
  });
});

// ---------------------------------------------------------------------------
// Verification failure — wrong key
// ---------------------------------------------------------------------------

describe('verifyAggregate() — wrong key', () => {
  test('rejects aggregate when one public key is swapped', async () => {
    const msg = 'emet:claim:wrong-key-test';
    const keyPairs = generateKeyPairs(3);
    const sigs = await signAll(msg, keyPairs);
    const aggSig = aggregateSignatures(sigs);

    // Replace the last public key with a freshly generated one
    const impostor = generateBLSKeyPair();
    const badKeys = [
      keyPairs[0].publicKey,
      keyPairs[1].publicKey,
      impostor.publicKey, // wrong key
    ];

    const valid = await verifyAggregate(msg, aggSig, badKeys);
    expect(valid).toBe(false);
  });

  test('rejects single signature verified against the wrong key', async () => {
    const alice = generateBLSKeyPair();
    const bob = generateBLSKeyPair();
    const msg = 'emet:claim:alice-only';
    const sig = await createPartialSignature(msg, alice.privateKey);

    const valid = await verifyAggregate(msg, sig, [bob.publicKey]);
    expect(valid).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Verification failure — mismatched messages
// ---------------------------------------------------------------------------

describe('verifyAggregate() — mismatched messages', () => {
  test('rejects aggregate when signers signed different messages', async () => {
    const keyPairs = generateKeyPairs(3);

    // Each signer signs a DIFFERENT message
    const sig0 = await createPartialSignature('message-A', keyPairs[0].privateKey);
    const sig1 = await createPartialSignature('message-B', keyPairs[1].privateKey);
    const sig2 = await createPartialSignature('message-C', keyPairs[2].privateKey);

    const aggSig = aggregateSignatures([sig0, sig1, sig2]);
    const pubKeys = keyPairs.map((kp) => kp.publicKey);

    // Verify against any single message — should fail because the
    // aggregate was built from heterogeneous messages.
    const validA = await verifyAggregate('message-A', aggSig, pubKeys);
    const validB = await verifyAggregate('message-B', aggSig, pubKeys);
    const validC = await verifyAggregate('message-C', aggSig, pubKeys);
    expect(validA).toBe(false);
    expect(validB).toBe(false);
    expect(validC).toBe(false);
  });

  test('rejects when aggregate is verified against a completely different message', async () => {
    const msg = 'the-real-message';
    const keyPairs = generateKeyPairs(5);
    const sigs = await signAll(msg, keyPairs);
    const aggSig = aggregateSignatures(sigs);
    const pubKeys = keyPairs.map((kp) => kp.publicKey);

    const valid = await verifyAggregate('a-different-message', aggSig, pubKeys);
    expect(valid).toBe(false);
  });
});
