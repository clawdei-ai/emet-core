/**
 * EMET Protocol — Merkle Tree Module Tests
 */

const {
  buildTree,
  getProof,
  verifyProof,
  computeRoot,
  serializeTree,
  sha256
} = require('../merkle');

// Helper: generate n distinct hex-hash strings
const hashes = (n) =>
  Array.from({ length: n }, (_, i) =>
    sha256(Buffer.from(`leaf-${i}`)).toString('hex')
  );

describe('buildTree()', () => {
  test.each([1, 2, 4, 7, 16])('builds a tree with %i leaves', (n) => {
    const tree = buildTree(hashes(n));
    expect(tree.size).toBe(n);
    expect(tree.root).toBeDefined();
    expect(tree.root.hash).toBeInstanceOf(Buffer);
    expect(tree.leaves).toHaveLength(n);
    expect(tree.depth).toBeGreaterThanOrEqual(0);
  });

  test('single leaf tree has depth 0', () => {
    const tree = buildTree(hashes(1));
    expect(tree.depth).toBe(0);
    expect(tree.root.hash).toBeInstanceOf(Buffer);
  });

  test('two leaves produce depth 1', () => {
    const tree = buildTree(hashes(2));
    expect(tree.depth).toBe(1);
  });

  test('throws on empty input', () => {
    expect(() => buildTree([])).toThrow(/empty/i);
  });

  test('throws on null/undefined input', () => {
    expect(() => buildTree(null)).toThrow();
    expect(() => buildTree(undefined)).toThrow();
  });

  test('root is deterministic for same input', () => {
    const data = hashes(5);
    const a = buildTree(data);
    const b = buildTree(data);
    expect(a.root.hash.equals(b.root.hash)).toBe(true);
  });

  test('different input produces different root', () => {
    const a = buildTree(hashes(4));
    // Use genuinely different data (hashPair sorts children, so
    // reversing the same leaves can collide).
    const other = Array.from({ length: 4 }, (_, i) =>
      sha256(Buffer.from(`other-${i}`)).toString('hex')
    );
    const b = buildTree(other);
    expect(a.root.hash.equals(b.root.hash)).toBe(false);
  });

  test('accepts Buffer leaves', () => {
    const bufs = [Buffer.from('a'), Buffer.from('b'), Buffer.from('c')];
    const tree = buildTree(bufs);
    expect(tree.size).toBe(3);
  });

  test('accepts object leaves (JSON stringified)', () => {
    const objs = [{ id: 1 }, { id: 2 }];
    const tree = buildTree(objs);
    expect(tree.size).toBe(2);
  });

  test('preserveData stores original data in leaves', () => {
    const data = ['alpha', 'beta'];
    const tree = buildTree(data, { preserveData: true });
    expect(tree.leaves[0].data).toBe('alpha');
    expect(tree.leaves[1].data).toBe('beta');
  });
});

describe('getProof()', () => {
  test('returns a valid proof object', () => {
    const tree = buildTree(hashes(8));
    const proof = getProof(tree, 3);

    expect(proof).toHaveProperty('root');
    expect(proof).toHaveProperty('leaf');
    expect(proof).toHaveProperty('index', 3);
    expect(proof).toHaveProperty('siblings');
    expect(proof.root).toMatch(/^[0-9a-f]{64}$/);
    expect(proof.leaf).toMatch(/^[0-9a-f]{64}$/);
    expect(Array.isArray(proof.siblings)).toBe(true);
    proof.siblings.forEach((s) => {
      expect(s).toHaveProperty('hash');
      expect(s).toHaveProperty('position');
      expect(['left', 'right']).toContain(s.position);
    });
  });

  test('throws on out-of-bounds index', () => {
    const tree = buildTree(hashes(4));
    expect(() => getProof(tree, -1)).toThrow(RangeError);
    expect(() => getProof(tree, 4)).toThrow(RangeError);
  });

  test('proof for single-leaf tree has no siblings', () => {
    const tree = buildTree(hashes(1));
    const proof = getProof(tree, 0);
    expect(proof.siblings).toHaveLength(0);
    expect(proof.leaf).toBe(proof.root);
  });

  test.each([0, 1, 2, 3])('proof verifies for leaf %i in a 4-leaf tree', (i) => {
    const tree = buildTree(hashes(4));
    const proof = getProof(tree, i);
    expect(verifyProof(proof).valid).toBe(true);
  });
});

describe('verifyProof()', () => {
  test('succeeds with a genuine proof', () => {
    const tree = buildTree(hashes(7));
    for (let i = 0; i < 7; i++) {
      const proof = getProof(tree, i);
      const result = verifyProof(proof);
      expect(result.valid).toBe(true);
      expect(result.computedRoot).toBe(proof.root);
    }
  });

  test('fails when the leaf hash is tampered', () => {
    const tree = buildTree(hashes(4));
    const proof = getProof(tree, 1);
    proof.leaf = '00'.repeat(32); // bogus hash
    const result = verifyProof(proof);
    expect(result.valid).toBe(false);
  });

  test('fails when a sibling hash is tampered', () => {
    const tree = buildTree(hashes(4));
    const proof = getProof(tree, 2);
    if (proof.siblings.length > 0) {
      proof.siblings[0].hash = 'ff'.repeat(32);
    }
    const result = verifyProof(proof);
    expect(result.valid).toBe(false);
  });

  test('fails when expectedRoot does not match', () => {
    const tree = buildTree(hashes(4));
    const proof = getProof(tree, 0);
    const result = verifyProof(proof, { expectedRoot: 'ab'.repeat(32) });
    expect(result.valid).toBe(false);
  });
});

describe('computeRoot()', () => {
  test('matches buildTree root for same input', () => {
    const data = hashes(6);
    const tree = buildTree(data);
    const root = computeRoot(data);
    expect(root).toBe(tree.root.hash.toString('hex'));
  });

  test('throws on empty array', () => {
    expect(() => computeRoot([])).toThrow(/empty/i);
  });

  test('single hash returns a sha256 of itself', () => {
    const h = hashes(1);
    const tree = buildTree(h);
    const root = computeRoot(h);
    expect(root).toBe(tree.root.hash.toString('hex'));
  });
});

describe('serializeTree()', () => {
  test('returns JSON-safe object with hex strings', () => {
    const tree = buildTree(hashes(3));
    const s = serializeTree(tree);

    expect(s.root).toMatch(/^[0-9a-f]{64}$/);
    expect(s.size).toBe(3);
    expect(s.depth).toBeGreaterThan(0);
    expect(s.leaves).toHaveLength(3);
    s.leaves.forEach((l) => {
      expect(l.hash).toMatch(/^[0-9a-f]{64}$/);
      expect(typeof l.index).toBe('number');
    });

    // Round-trip through JSON must work
    const json = JSON.stringify(s);
    expect(() => JSON.parse(json)).not.toThrow();
  });
});
