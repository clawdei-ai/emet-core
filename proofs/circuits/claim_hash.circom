pragma circom 2.1.0;

/*
 * ClaimHash — Prove knowledge of a claim's preimage without revealing content
 *
 * Public inputs:  hash (the known claim hash)
 * Private inputs: preimage (the secret claim content, as 4 × 64-bit chunks)
 *
 * The prover demonstrates they know a preimage that hashes to the public
 * hash value without revealing the preimage itself.
 *
 * Uses the Poseidon hash function (efficient inside SNARKs).
 * Requires: circomlib (npm install circomlib)
 *
 * EMET use cases:
 * - Medical claims: prove you hold a valid diagnosis without revealing it
 * - Whistleblower claims: prove insider knowledge without identity exposure
 * - Competitive intel: prove market knowledge without revealing sources
 */

include "../node_modules/circomlib/circuits/poseidon.circom";

template ClaimHash(nInputs) {
    // --- Signals ---
    signal input preimage[nInputs];   // Private: the claim content chunks
    signal input hash;                 // Public:  the expected Poseidon hash

    // --- Constraints ---
    // Hash the preimage using Poseidon and constrain against the public hash.
    component hasher = Poseidon(nInputs);
    for (var i = 0; i < nInputs; i++) {
        hasher.inputs[i] <== preimage[i];
    }

    // The computed hash MUST equal the publicly declared hash.
    hash === hasher.out;
}

// Default instance: 4-chunk preimage (covers most claim bodies when split
// into 64-bit field elements).
component main { public [hash] } = ClaimHash(4);
