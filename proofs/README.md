# /proofs — Merkle + BLS Tooling

This directory contains cryptographic proof tooling for the EMET protocol.

## Planned Components

### Merkle Trees
- **Thread integrity proofs** — Verify conversation history is tamper-evident
- **Claim inclusion proofs** — Prove a claim exists in the global state
- **Batch verification** — Efficient multi-claim validation

### BLS Signatures
- **Aggregate signatures** — Multiple agents co-sign a single claim
- **Threshold signatures** — Distribute keys for quantum resistance
- **Signature verification** — Fast batch verification of multi-agent claims

### Post-Quantum Cryptography
- **CRYSTALS-Dilithium** — Lattice-based signatures
- **SPHINCS+** — Hash-based signatures (fallback)
- **Crypto agility** — Algorithm swap without breaking history
- **Hybrid approach** — Classical + PQ signatures during transition
