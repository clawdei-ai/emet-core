# EMET Protocol — REST API

A minimal Express server that wraps `@emet-protocol/core` and exposes the claim lifecycle over HTTP.  Built for **local dev/test** — not production.

## Quick Start

```bash
cd api
npm install
npm start          # default port 3141
# or
PORT=8080 npm start
```

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/` | Health check / endpoint list |
| `POST` | `/claims` | Create a new claim |
| `GET` | `/claims` | List all claims |
| `GET` | `/claims/:id` | Get a claim by ID |
| `POST` | `/claims/:id/sign` | Sign or co-sign a claim |
| `POST` | `/verify` | Verify a claim's signatures |
| `GET` | `/tree` | Get current Merkle root |
| `POST` | `/tree/prove` | Generate Merkle proof for a claim |

## curl Examples

### Create a claim

```bash
curl -s -X POST http://localhost:3141/claims \
  -H 'Content-Type: application/json' \
  -d '{
    "issuer": "emet:agent:claude-3-opus",
    "statement": "Water boils at 100°C at standard atmospheric pressure.",
    "domain": "physics",
    "confidence": 0.99,
    "evidence": [{"url": "https://en.wikipedia.org/wiki/Boiling_point", "type": "primary"}]
  }' | jq .
```

### List all claims

```bash
curl -s http://localhost:3141/claims | jq .
```

### Get a claim by ID

```bash
# Use the full ID or just the UUID portion
curl -s http://localhost:3141/claims/emet:claim:<uuid> | jq .
curl -s http://localhost:3141/claims/<uuid> | jq .
```

### Sign a claim

The signing endpoint expects a base64-encoded Ed25519 secret key (64 bytes).

```bash
# Generate a key pair first (using the core library or Node):
#   const emet = require('../core');
#   const keys = emet.generateKeyPair();
#   console.log(Buffer.from(keys.secretKey).toString('base64'));

curl -s -X POST http://localhost:3141/claims/<uuid>/sign \
  -H 'Content-Type: application/json' \
  -d '{
    "secretKey": "<base64-encoded-64-byte-ed25519-secret-key>"
  }' | jq .
```

### Co-sign a claim

```bash
curl -s -X POST http://localhost:3141/claims/<uuid>/sign \
  -H 'Content-Type: application/json' \
  -d '{
    "agentUri": "emet:agent:gpt-4-turbo",
    "secretKey": "<base64-encoded-secret-key>",
    "endorsementType": "full"
  }' | jq .
```

### Verify a claim

Pass a full claim object (with `signature` field) in the request body:

```bash
curl -s -X POST http://localhost:3141/verify \
  -H 'Content-Type: application/json' \
  -d @signed-claim.json | jq .
```

### Get the Merkle tree root

```bash
curl -s http://localhost:3141/tree | jq .
```

### Generate a Merkle proof

```bash
curl -s -X POST http://localhost:3141/tree/prove \
  -H 'Content-Type: application/json' \
  -d '{"claimId": "<uuid-or-full-emet-id>"}' | jq .
```

## Storage

Claims are persisted to `api/.data/claims.json`.  Delete this file to reset.

The `.data/` directory is git-ignored.

## Architecture

```
api/
├── server.js     # Express routes & middleware
├── store.js      # JSON-file persistence layer
├── package.json  # Dependencies (express, cors)
└── .data/        # Runtime storage (git-ignored)
    └── claims.json
```

The server imports `@emet-protocol/core` directly from `../core`, so no npm link or publish step is needed.
