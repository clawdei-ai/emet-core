# EMET ZKP Circuits

Zero-knowledge proof circuits for private claim verification in the EMET protocol.

## Circuits

| Circuit | Purpose | Public Inputs | Private Inputs |
|---------|---------|---------------|----------------|
| `claim_hash.circom` | Prove knowledge of a claim's preimage | `hash` | `preimage[4]` |
| `confidence_threshold.circom` | Prove confidence ≥ threshold | `threshold` | `confidence` |

## Prerequisites

### 1. Install circom compiler

```bash
# Install Rust (if needed)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Clone and build circom
git clone https://github.com/iden3/circom.git
cd circom
cargo build --release
cargo install --path circom

# Verify installation
circom --version
```

### 2. Install Node.js dependencies

```bash
cd proofs
npm install          # installs snarkjs
npm install circomlib  # circuit library (Poseidon, comparators, etc.)
```

### 3. Download Powers of Tau ceremony file

The trusted setup requires a Powers of Tau file. For development/testing use the Hermez ceremony files:

```bash
mkdir -p circuits/build
cd circuits/build

# Download ptau file (use pot12 for small circuits, pot14+ for larger ones)
wget https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_12.ptau
```

## Compiling Circuits

### claim_hash.circom

```bash
cd proofs/circuits

# 1. Compile the circuit
circom claim_hash.circom --r1cs --wasm --sym -o build/

# 2. Generate the proving key (Groth16 setup)
npx snarkjs groth16 setup build/claim_hash.r1cs \
    build/powersOfTau28_hez_final_12.ptau \
    build/claim_hash_0000.zkey

# 3. Contribute to the ceremony (adds entropy)
npx snarkjs zkey contribute build/claim_hash_0000.zkey \
    build/claim_hash.zkey \
    --name="EMET dev contribution" -v

# 4. Export the verification key
npx snarkjs zkey export verificationkey \
    build/claim_hash.zkey \
    build/claim_hash_vkey.json
```

### confidence_threshold.circom

```bash
cd proofs/circuits

# 1. Compile
circom confidence_threshold.circom --r1cs --wasm --sym -o build/

# 2. Setup
npx snarkjs groth16 setup build/confidence_threshold.r1cs \
    build/powersOfTau28_hez_final_12.ptau \
    build/confidence_threshold_0000.zkey

# 3. Contribute
npx snarkjs zkey contribute build/confidence_threshold_0000.zkey \
    build/confidence_threshold.zkey \
    --name="EMET dev contribution" -v

# 4. Export verification key
npx snarkjs zkey export verificationkey \
    build/confidence_threshold.zkey \
    build/confidence_threshold_vkey.json
```

## Usage with zkp.js

After compiling the circuits:

```javascript
const { generateProof, verifyProof, claimToFieldElement, confidenceToSignal } = require('../zkp');

// --- Claim Hash proof ---
const claimBody = 'Patient diagnosed with condition X on 2026-01-15';
const fieldEl = claimToFieldElement(claimBody);
// Split into 4 chunks for the circuit (application-specific encoding)

const { proof, publicSignals } = await generateProof(
  { preimage: [chunk0, chunk1, chunk2, chunk3], hash: expectedHash },
  './circuits/build/claim_hash_js/claim_hash.wasm',
  './circuits/build/claim_hash.zkey'
);

const valid = await verifyProof(proof, publicSignals, './circuits/build/claim_hash_vkey.json');
console.log('Proof valid:', valid);

// --- Confidence Threshold proof ---
const { proof: cProof, publicSignals: cSignals } = await generateProof(
  { confidence: confidenceToSignal(0.943), threshold: confidenceToSignal(0.90) },
  './circuits/build/confidence_threshold_js/confidence_threshold.wasm',
  './circuits/build/confidence_threshold.zkey'
);
// Verifier only sees that confidence >= 90%, not the exact 94.3%
```

## Build Artifacts

After compilation, the `build/` directory will contain:

```
build/
├── claim_hash.r1cs              # Constraint system
├── claim_hash.wasm              # WASM witness generator
├── claim_hash.zkey              # Proving key
├── claim_hash_vkey.json         # Verification key
├── confidence_threshold.r1cs
├── confidence_threshold.wasm
├── confidence_threshold.zkey
├── confidence_threshold_vkey.json
└── powersOfTau28_hez_final_12.ptau
```

> **Note:** Build artifacts are gitignored. Each developer must compile locally.

## Security Notes

- The `.zkey` files in development use a minimal trusted setup. For production, run a proper multi-party ceremony.
- Circuit auditing is critical before any production deployment.
- Poseidon hash is used for SNARK-friendliness; the `claimToFieldElement()` helper in `zkp.js` uses SHA-256 for the JS side — the mapping between the two must be handled by the application layer.
