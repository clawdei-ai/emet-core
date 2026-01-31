/**
 * EMET Protocol - Merkle Tree Module
 * 
 * Implements Merkle trees for thread integrity proofs.
 * Allows verification that a specific claim was part of a conversation thread
 * without revealing other claims in the thread.
 * 
 * @module @emet-protocol/core/merkle
 * @version 1.0.0
 */

const { createHash } = require('crypto');

/**
 * Computes SHA-256 hash of data.
 * @private
 * @param {Buffer|string} data - Data to hash
 * @returns {Buffer} 32-byte hash
 */
function sha256(data) {
  return createHash('sha256').update(data).digest();
}

/**
 * Computes the hash of two child nodes.
 * Sorts hashes before concatenation to ensure consistent ordering.
 * @private
 * @param {Buffer} left - Left child hash
 * @param {Buffer} right - Right child hash
 * @returns {Buffer} Parent hash
 */
function hashPair(left, right) {
  // Sort to ensure consistent ordering regardless of input order
  const sorted = Buffer.compare(left, right) < 0 
    ? Buffer.concat([left, right])
    : Buffer.concat([right, left]);
  return sha256(sorted);
}

/**
 * Represents a node in the Merkle tree.
 * @typedef {Object} MerkleNode
 * @property {Buffer} hash - The hash value of this node
 * @property {MerkleNode|null} left - Left child node
 * @property {MerkleNode|null} right - Right child node
 * @property {number|null} index - Leaf index (only for leaf nodes)
 * @property {*} [data] - Original data (only for leaf nodes)
 */

/**
 * Represents a Merkle proof.
 * @typedef {Object} MerkleProof
 * @property {string} root - Hex-encoded root hash
 * @property {string} leaf - Hex-encoded leaf hash
 * @property {number} index - Index of the leaf in the tree
 * @property {Array<{hash: string, position: 'left'|'right'}>} siblings - Sibling hashes needed for verification
 */

/**
 * Represents a complete Merkle tree.
 * @typedef {Object} MerkleTree
 * @property {MerkleNode} root - Root node of the tree
 * @property {MerkleNode[]} leaves - Array of leaf nodes
 * @property {number} size - Number of leaves
 * @property {number} depth - Depth of the tree
 */

/**
 * Builds a Merkle tree from an array of data items.
 * 
 * Each data item is hashed to create a leaf node. The tree is then built
 * bottom-up by hashing pairs of nodes until a single root is obtained.
 * 
 * @param {Array<string|Buffer|Object>} data - Array of data items to include in the tree
 * @param {Object} [options] - Build options
 * @param {Function} [options.hashFn] - Custom hash function for leaves (default: SHA-256 of JSON)
 * @param {boolean} [options.preserveData=false] - Whether to store original data in leaf nodes
 * @returns {MerkleTree} The constructed Merkle tree
 * 
 * @throws {Error} If data array is empty
 * 
 * @example
 * // Build tree from claim hashes
 * const claims = [claim1, claim2, claim3];
 * const tree = buildTree(claims.map(c => hashClaim(c)));
 * console.log('Root:', tree.root.hash.toString('hex'));
 * 
 * @example
 * // Build tree with custom hash function
 * const tree = buildTree(items, {
 *   hashFn: (item) => sha256(item.id + item.content)
 * });
 */
function buildTree(data, options = {}) {
  if (!data || data.length === 0) {
    throw new Error('Cannot build Merkle tree from empty data');
  }
  
  const { hashFn, preserveData = false } = options;
  
  // Create leaf nodes
  const leaves = data.map((item, index) => {
    let hash;
    if (hashFn) {
      hash = hashFn(item);
      if (typeof hash === 'string') {
        hash = Buffer.from(hash, 'hex');
      }
    } else if (Buffer.isBuffer(item)) {
      hash = sha256(item);
    } else if (typeof item === 'string') {
      // If it looks like a hex hash, use it directly
      if (/^[0-9a-f]{64}$/i.test(item)) {
        hash = Buffer.from(item, 'hex');
      } else {
        hash = sha256(Buffer.from(item));
      }
    } else {
      hash = sha256(Buffer.from(JSON.stringify(item)));
    }
    
    return {
      hash,
      left: null,
      right: null,
      index,
      ...(preserveData && { data: item })
    };
  });
  
  // If odd number of leaves, duplicate the last one
  if (leaves.length % 2 === 1 && leaves.length > 1) {
    leaves.push({
      hash: leaves[leaves.length - 1].hash,
      left: null,
      right: null,
      index: leaves.length,
      duplicate: true
    });
  }
  
  // Build tree bottom-up
  let currentLevel = leaves;
  let depth = 0;
  
  while (currentLevel.length > 1) {
    const nextLevel = [];
    
    for (let i = 0; i < currentLevel.length; i += 2) {
      const left = currentLevel[i];
      const right = currentLevel[i + 1] || left; // Duplicate if odd
      
      nextLevel.push({
        hash: hashPair(left.hash, right.hash),
        left,
        right: currentLevel[i + 1] ? right : null,
        index: null
      });
    }
    
    currentLevel = nextLevel;
    depth++;
  }
  
  return {
    root: currentLevel[0],
    leaves: leaves.filter(l => !l.duplicate),
    size: data.length,
    depth
  };
}

/**
 * Generates a Merkle proof for a specific leaf.
 * 
 * The proof contains the sibling hashes needed to reconstruct the path
 * from the leaf to the root. This allows verification that the leaf
 * is part of the tree without revealing other leaves.
 * 
 * @param {MerkleTree} tree - The Merkle tree
 * @param {number} leafIndex - Index of the leaf to prove
 * @returns {MerkleProof} The Merkle proof
 * 
 * @throws {RangeError} If leaf index is out of bounds
 * 
 * @example
 * const tree = buildTree(claimHashes);
 * const proof = getProof(tree, 2); // Proof for third claim
 * 
 * // Proof can be serialized and shared
 * console.log(JSON.stringify(proof));
 */
function getProof(tree, leafIndex) {
  if (leafIndex < 0 || leafIndex >= tree.size) {
    throw new RangeError(`Leaf index ${leafIndex} out of bounds (0-${tree.size - 1})`);
  }
  
  const siblings = [];
  let currentIndex = leafIndex;
  
  // Handle duplicated last leaf for odd-sized trees
  const effectiveLeaves = [...tree.leaves];
  if (tree.leaves.length % 2 === 1 && tree.leaves.length > 1) {
    effectiveLeaves.push(tree.leaves[tree.leaves.length - 1]);
  }
  
  let currentLevel = effectiveLeaves;
  
  while (currentLevel.length > 1) {
    const siblingIndex = currentIndex % 2 === 0 ? currentIndex + 1 : currentIndex - 1;
    const position = currentIndex % 2 === 0 ? 'right' : 'left';
    
    // Get sibling (or self if at the end of odd-length level)
    const sibling = currentLevel[siblingIndex] || currentLevel[currentIndex];
    
    siblings.push({
      hash: sibling.hash.toString('hex'),
      position
    });
    
    // Move to parent level
    currentIndex = Math.floor(currentIndex / 2);
    
    // Build next level
    const nextLevel = [];
    for (let i = 0; i < currentLevel.length; i += 2) {
      const left = currentLevel[i];
      const right = currentLevel[i + 1] || left;
      nextLevel.push({
        hash: hashPair(left.hash, right.hash)
      });
    }
    currentLevel = nextLevel;
  }
  
  return {
    root: tree.root.hash.toString('hex'),
    leaf: tree.leaves[leafIndex].hash.toString('hex'),
    index: leafIndex,
    siblings
  };
}

/**
 * Verifies a Merkle proof.
 * 
 * Reconstructs the root hash from the leaf and sibling hashes,
 * then compares it to the expected root.
 * 
 * @param {MerkleProof} proof - The Merkle proof to verify
 * @param {Object} [options] - Verification options
 * @param {string} [options.expectedRoot] - Override root to verify against
 * @returns {Object} Verification result
 * @returns {boolean} returns.valid - Whether the proof is valid
 * @returns {string} returns.computedRoot - The computed root hash
 * @returns {string} [returns.error] - Error message if invalid
 * 
 * @example
 * const result = verifyProof(proof);
 * if (result.valid) {
 *   console.log('Claim is verified to be part of the thread');
 * }
 * 
 * @example
 * // Verify against a specific root
 * const result = verifyProof(proof, { expectedRoot: knownRoot });
 */
function verifyProof(proof, options = {}) {
  const { expectedRoot = proof.root } = options;
  
  const result = {
    valid: false,
    computedRoot: null
  };
  
  try {
    let currentHash = Buffer.from(proof.leaf, 'hex');
    
    for (const sibling of proof.siblings) {
      const siblingHash = Buffer.from(sibling.hash, 'hex');
      
      if (sibling.position === 'right') {
        currentHash = hashPair(currentHash, siblingHash);
      } else {
        currentHash = hashPair(siblingHash, currentHash);
      }
    }
    
    result.computedRoot = currentHash.toString('hex');
    result.valid = result.computedRoot === expectedRoot;
    
    if (!result.valid) {
      result.error = 'Computed root does not match expected root';
    }
  } catch (err) {
    result.error = `Verification error: ${err.message}`;
  }
  
  return result;
}

/**
 * Computes the root hash of a tree without building the full structure.
 * Useful for quick root computation when you don't need proofs.
 * 
 * @param {Array<string|Buffer>} hashes - Array of leaf hashes
 * @returns {string} Hex-encoded root hash
 * 
 * @example
 * const root = computeRoot(claimHashes);
 */
function computeRoot(hashes) {
  if (hashes.length === 0) {
    throw new Error('Cannot compute root from empty array');
  }
  
  let currentLevel = hashes.map(h => 
    typeof h === 'string' ? Buffer.from(h, 'hex') : h
  );
  
  // Duplicate last if odd
  if (currentLevel.length % 2 === 1 && currentLevel.length > 1) {
    currentLevel.push(currentLevel[currentLevel.length - 1]);
  }
  
  while (currentLevel.length > 1) {
    const nextLevel = [];
    for (let i = 0; i < currentLevel.length; i += 2) {
      const left = currentLevel[i];
      const right = currentLevel[i + 1] || left;
      nextLevel.push(hashPair(left, right));
    }
    currentLevel = nextLevel;
  }
  
  return currentLevel[0].toString('hex');
}

/**
 * Serializes a Merkle tree to JSON-compatible format.
 * 
 * @param {MerkleTree} tree - The tree to serialize
 * @returns {Object} Serialized tree data
 */
function serializeTree(tree) {
  return {
    root: tree.root.hash.toString('hex'),
    leaves: tree.leaves.map(l => ({
      hash: l.hash.toString('hex'),
      index: l.index
    })),
    size: tree.size,
    depth: tree.depth
  };
}

/**
 * Creates a Merkle tree from EMET claims.
 * Uses claim IDs and hashes for leaf computation.
 * 
 * @param {Object[]} claims - Array of EMET claims
 * @param {Function} hashClaim - The hashClaim function from claim.js
 * @returns {MerkleTree} The constructed tree
 * 
 * @example
 * const { hashClaim } = require('./claim');
 * const tree = buildTreeFromClaims(claims, hashClaim);
 */
function buildTreeFromClaims(claims, hashClaim) {
  const hashes = claims.map(claim => hashClaim(claim));
  return buildTree(hashes, { preserveData: false });
}

module.exports = {
  buildTree,
  getProof,
  verifyProof,
  computeRoot,
  serializeTree,
  buildTreeFromClaims,
  
  // Expose hash utilities
  sha256,
  hashPair
};
