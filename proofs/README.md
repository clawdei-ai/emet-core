# EMET Merkle Proof System

This directory contains documentation and examples for the EMET Protocol's cryptographic proof system.

## Overview

The EMET Protocol uses Merkle trees to provide **thread integrity proofs** - cryptographic evidence that a specific claim was part of a conversation thread, without revealing other claims in that thread.

## How It Works

### 1. Building the Tree

When a conversation thread concludes (or at periodic checkpoints), all claims in the thread are collected and hashed:

```
Claims:  [C1]    [C2]    [C3]    [C4]
           ↓       ↓       ↓       ↓
Hashes:  [H1]    [H2]    [H3]    [H4]
           \      /         \      /
            [H12]            [H34]
                \            /
                   [ROOT]
```

The **root hash** becomes the thread's integrity anchor.

### 2. Generating Proofs

To prove that Claim C2 was part of the thread, we generate a Merkle proof:

```javascript
const { buildTree, getProof } = require('@emet-protocol/core');

// Build tree from claim hashes
const tree = buildTree(claimHashes);

// Generate proof for claim at index 1 (C2)
const proof = getProof(tree, 1);

// proof contains:
// {
//   root: "abc123...",     // The tree's root hash
//   leaf: "def456...",     // H2 (C2's hash)
//   index: 1,              // Position in tree
//   siblings: [            // Hashes needed to verify
//     { hash: "H1...", position: "left" },
//     { hash: "H34...", position: "right" }
//   ]
// }
```

### 3. Verification

Anyone with the proof can verify membership:

```javascript
const { verifyProof } = require('@emet-protocol/core');

const result = verifyProof(proof);
// result.valid === true if the proof checks out
```

The verifier:
1. Starts with the leaf hash (H2)
2. Combines with H1 (from proof) → H12
3. Combines with H34 (from proof) → ROOT
4. Compares computed ROOT with expected ROOT

If they match, C2 was definitely in the original thread.

## Properties

### What Merkle Proofs Provide

- **Integrity:** Any change to any claim invalidates the root
- **Selective Disclosure:** Prove one claim without revealing others
- **Compact Proofs:** O(log n) size regardless of thread length
- **Non-Repudiation:** Agents cannot deny claims they've made

### What They Don't Provide

- **Ordering:** Standard Merkle trees don't prove claim order (use indexed trees for this)
- **Completeness:** Cannot prove a claim is NOT in a thread
- **Confidentiality:** Leaf hashes may be linkable if claim content is known

## Use Cases

### 1. Audit Trails

Prove that a specific AI response was part of an official interaction:

```
User: "What should I invest in?"
AI: [Claim C3 with disclaimer]
[Later, questioned about advice]
AI: "Here's proof C3 was my actual response" → [Merkle proof]
```

### 2. Dispute Resolution

When claims conflict, prove what was actually said:

```
Agent A: "I never claimed X"
Agent B: "Here's the Merkle proof showing you did"
```

### 3. Privacy-Preserving Verification

Verify an AI's response without revealing the full conversation:

```
Verifier: "Prove this claim was part of a verified thread"
AI: [Provides Merkle proof] // Other claims remain private
```

## Future: BLS Signature Aggregation

### The Problem

Currently, each claim has its own signature. In long threads, this creates overhead:
- N claims = N signatures to verify
- Each verification is a separate operation
- Storage grows linearly

### The Solution: BLS Signatures

BLS (Boneh-Lynn-Shacham) signatures can be **aggregated**:

```
Traditional:
[C1, σ1] [C2, σ2] [C3, σ3] [C4, σ4]  // 4 signatures, 4 verifications

With BLS:
[C1, C2, C3, C4, σ_agg]  // 1 aggregated signature, 1 verification
```

### Benefits

| Property | Traditional | BLS Aggregated |
|----------|-------------|----------------|
| Signature Storage | O(n) | O(1) |
| Verification Time | O(n) | O(1) |
| Batch Verification | No | Yes |
| Proof Size | Grows with thread | Constant |

### Implementation Timeline

1. **Phase 1 (Current):** Ed25519 signatures, Merkle proofs for thread integrity
2. **Phase 2 (Planned):** BLS library integration, experimental aggregation
3. **Phase 3 (Future):** BLS as primary for thread signatures, Ed25519 for individual claims

### Technical Notes

BLS requires pairing-friendly curves:
- BLS12-381 (recommended)
- BN254 (faster but lower security margin)

Libraries under evaluation:
- `@noble/bls12-381` (JavaScript)
- `blst` (Rust/C with bindings)
- `py_ecc` (Python reference)

### Hybrid Approach

We plan a hybrid system:

```
Individual Claim: Ed25519 signature (fast, simple)
Thread Commitment: BLS aggregated signature (efficient batch verify)
Long-term Archive: Dilithium (quantum-resistant)
```

## API Reference

### `buildTree(data, options)`

Constructs a Merkle tree from an array of data.

**Parameters:**
- `data`: Array of items (strings, Buffers, or objects)
- `options.hashFn`: Custom hash function (optional)
- `options.preserveData`: Store original data in leaves (default: false)

**Returns:** `MerkleTree` object

### `getProof(tree, index)`

Generates a Merkle proof for a leaf.

**Parameters:**
- `tree`: MerkleTree from `buildTree()`
- `index`: Leaf index (0-based)

**Returns:** `MerkleProof` object

### `verifyProof(proof, options)`

Verifies a Merkle proof.

**Parameters:**
- `proof`: MerkleProof from `getProof()`
- `options.expectedRoot`: Override root to verify against (optional)

**Returns:** `{ valid: boolean, computedRoot: string, error?: string }`

### `computeRoot(hashes)`

Computes root without building full tree structure.

**Parameters:**
- `hashes`: Array of hex strings or Buffers

**Returns:** Hex-encoded root hash

## Examples

See `/examples/merkle-proof-demo.js` for a complete working example.

## References

- [Merkle Trees (Wikipedia)](https://en.wikipedia.org/wiki/Merkle_tree)
- [RFC 6962: Certificate Transparency](https://tools.ietf.org/html/rfc6962)
- [BLS Signatures (Boneh, Lynn, Shacham)](https://crypto.stanford.edu/~dabo/pubs/papers/BLSmultisig.html)
- [BLS12-381 Curve](https://hackmd.io/@benjaminion/bls12-381)
