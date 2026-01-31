# EMET Protocol CLI

Command-line interface for creating, signing, and verifying EMET (Epistemic Markup for Explainable Truthfulness) claims.

## Installation

```bash
# Install dependencies
npm install

# Link globally (optional)
npm link
```

## Quick Start

```bash
# Initialize a new project (creates dirs, keypair, config)
emet init my-project
cd my-project

# Or generate a standalone keypair
emet keygen

# Create a claim
emet claim create "Water boils at 100°C at sea level" \
  --confidence 0.99 \
  --evidence "https://example.com/source" \
  --key ~/.emet/keys/default.json > claim.json

# Verify a claim
emet verify claim.json
```

## Commands

### `emet init [dir]`

Initialize a new EMET project with directory structure, a default keypair, and configuration.

```bash
# Initialize in current directory
emet init

# Initialize in a new directory
emet init my-project

# Reinitialize (overwrite config)
emet init --force
```

This creates:
- `claims/` — Directory for signed claim JSON files
- `keys/default.json` — Ed25519 keypair for signing
- `proofs/` — Directory for Merkle proofs
- `.emet.json` — Project configuration (`version`, `keyPath`)
- `README.md` — Basic usage instructions

**Options:**
- `-f, --force` — Overwrite existing `.emet.json` config

**Output:**
```
✓ EMET project initialized in my-project/

  Created:
    claims/          — Store your signed claims here
    keys/default.json — Ed25519 signing keypair
    proofs/          — Store Merkle proofs here
    .emet.json       — Project configuration
    README.md        — Usage instructions

  Public key: base64-encoded-public-key

  Next steps:
    emet claim create "Your first claim" --key ./keys/default.json > claims/first.json
    emet verify claims/first.json
```

---

### `emet keygen`

Generate a new Ed25519 keypair for signing claims.

```bash
# Generate default key
emet keygen
# Output: Key saved to: ~/.emet/keys/default.json
# Output: Public key: base64-encoded-public-key

# Generate named key
emet keygen -o mykey

# Overwrite existing key
emet keygen -o mykey --force
```

**Options:**
- `-o, --output <name>` — Key name (default: "default")
- `-f, --force` — Overwrite existing key

Keys are stored in `~/.emet/keys/` with restricted permissions (600).

---

### `emet claim create <statement>`

Create a new EMET claim.

```bash
# Basic claim
emet claim create "The sky is blue" > claim.json

# Claim with metadata
emet claim create "Python was created by Guido van Rossum" \
  --confidence 0.95 \
  --domain "programming" \
  --evidence "https://python.org/about" \
  --evidence "https://wikipedia.org/wiki/Python" \
  --issuer "emet:agent:my-agent" > claim.json

# Auto-sign with key
emet claim create "Verified statement" \
  --key ~/.emet/keys/default.json \
  --confidence 0.9 > signed-claim.json

# Interactive mode
emet claim create "Complex claim" --interactive
```

**Options:**
- `-c, --confidence <0-1>` — Confidence level (0 to 1)
- `-e, --evidence <url>` — Evidence URL (can be repeated)
- `-k, --key <path>` — Key file path for auto-signing
- `-i, --issuer <uri>` — Issuer URI (default: "emet:agent:cli")
- `-t, --type <type>` — Claim type: Assertion, Correction, Retraction, Endorsement, Dispute
- `-d, --domain <domain>` — Knowledge domain (e.g., "science", "history")
- `--subject <uri>` — Subject URI
- `--interactive` — Interactive mode for additional fields

**Output:** JSON claim to stdout. Redirect to save.

---

### `emet claim sign <file>`

Sign an existing claim JSON file.

```bash
# Sign a claim (updates in place)
emet claim sign claim.json --key ~/.emet/keys/default.json

# Sign to a new file
emet claim sign claim.json --key ~/.emet/keys/default.json -o signed-claim.json
```

**Options:**
- `-k, --key <path>` — Key file path (required)
- `-o, --output <file>` — Output file (default: updates in place)

---

### `emet verify <file>`

Verify a claim's signature.

```bash
# Verify a signed claim
emet verify signed-claim.json

# Output:
# Verification Result
# ==================
# Status: ✓ PASS
# Claim ID: emet:claim:550e8400-e29b-41d4-a716-446655440000
# Issuer: emet:agent:cli
# Timestamp: 2025-01-31T12:00:00.000Z
# Algorithm: ed25519
# Signed at: 2025-01-31T12:00:01.000Z

# Verify with explicit public key
emet verify claim.json --public-key "base64-encoded-key"
```

**Options:**
- `-p, --public-key <key>` — Override public key (base64)

**Exit codes:**
- `0` — Verification passed
- `1` — Verification failed

---

### `emet tree build <dir>`

Build a Merkle tree from all claim JSON files in a directory.

```bash
# Build tree
emet tree build ./claims/
# Output:
# Found 5 claim file(s)
# Claims included:
#   0. claim1.json (7d865e959b246691...)
#   1. claim2.json (a1b2c3d4e5f67890...)
#   ...
# Merkle Root: abc123def456...
# Tree depth: 3

# Save tree data
emet tree build ./claims/ -o tree.json
```

**Options:**
- `-o, --output <file>` — Save tree data to file

The tree data includes:
- Root hash
- List of leaves with their claim IDs and hashes
- Tree metadata (size, depth)

---

### `emet tree prove <file> <dir>`

Generate a Merkle proof that a specific claim belongs to a tree.

```bash
# Generate proof
emet tree prove ./claims/claim1.json ./claims/

# Save proof to file
emet tree prove ./claims/claim1.json ./claims/ -o proof.json
```

**Options:**
- `-o, --output <file>` — Save proof to file

**Output:** JSON proof containing:
- Root hash
- Leaf hash
- Leaf index
- Sibling hashes (audit path)
- Claim metadata

---

### `emet tree verify <file> <proof> <root>`

Verify a Merkle proof against a known root hash.

```bash
# Verify proof
emet tree verify claim1.json proof.json abc123def456...

# Output:
# Verification Result
# ==================
# Status: ✓ PASS
# Claim ID: emet:claim:550e8400-e29b-41d4-a716-446655440000
# Leaf hash: 7d865e959b246691...
# Expected root: abc123def456...
# Computed root: abc123def456...
#
# ✓ Claim is verified to be part of the Merkle tree
```

**Exit codes:**
- `0` — Proof valid
- `1` — Proof invalid

---

## Example Workflow

### 1. Setup

```bash
# Initialize project (recommended)
emet init my-project
cd my-project

# Or just generate a signing key
emet keygen -o agent-key
```

### 2. Create and Sign Claims

```bash
# Create multiple claims
emet claim create "Claim A" --key ~/.emet/keys/agent-key.json > claims/a.json
emet claim create "Claim B" --key ~/.emet/keys/agent-key.json > claims/b.json
emet claim create "Claim C" --key ~/.emet/keys/agent-key.json > claims/c.json
```

### 3. Verify Individual Claims

```bash
emet verify claims/a.json
emet verify claims/b.json
```

### 4. Build Merkle Tree

```bash
# Build tree and save root
emet tree build ./claims/ -o tree.json
ROOT=$(cat tree.json | jq -r '.root')
echo "Root: $ROOT"
```

### 5. Generate and Verify Proofs

```bash
# Generate proof for claim A
emet tree prove claims/a.json ./claims/ -o proof-a.json

# Verify the proof
emet tree verify claims/a.json proof-a.json "$ROOT"
```

---

## Key File Format

Keys are stored as JSON:

```json
{
  "name": "default",
  "algorithm": "ed25519",
  "publicKey": "base64-encoded-32-bytes",
  "secretKey": "base64-encoded-64-bytes",
  "createdAt": "2025-01-31T12:00:00.000Z"
}
```

**Security:** Keep your secret key secure! The `~/.emet/keys/` directory and key files are created with restricted permissions.

---

## Claim JSON Structure

```json
{
  "id": "emet:claim:uuid",
  "type": "Assertion",
  "issuer": "emet:agent:cli",
  "content": {
    "statement": "The claim statement",
    "domain": "science",
    "scope": "contextual",
    "caveats": ["Known limitation"]
  },
  "evidence": [
    {
      "url": "https://example.com",
      "type": "primary",
      "retrievedAt": "2025-01-31T12:00:00.000Z"
    }
  ],
  "confidence": 0.95,
  "timestamp": "2025-01-31T12:00:00.000Z",
  "version": "1.0.0",
  "signature": {
    "claimId": "emet:claim:uuid",
    "signer": "emet:agent:cli",
    "algorithm": "ed25519",
    "publicKey": "base64-key",
    "signature": "base64-signature",
    "timestamp": "2025-01-31T12:00:01.000Z"
  }
}
```

---

## License

MIT
