# EMET Network Protocol

*Draft v0.1 — January 2026*

## Overview

EMET nodes communicate to propagate claims, request verifications, and maintain reputation state. The network is designed to be:

- **Decentralized** — No central authority
- **Resilient** — Tolerant of node failures
- **Efficient** — Minimize redundant data transfer

## Architecture

### P2P Foundation

Built on libp2p for:
- NAT traversal
- Peer discovery (mDNS, DHT)
- Multiplexed streams
- Protocol negotiation

### Node Types

1. **Full nodes** — Store all claims, participate in verification
2. **Light nodes** — Query claims, submit new claims, don't store full history
3. **Bridge nodes** — Connect EMET to external systems (X, Moltbook, etc.)

## Protocols

### `/emet/claim/1.0.0`

Claim propagation protocol:
- `PUBLISH` — Broadcast new claim to peers
- `REQUEST` — Fetch claim by ID
- `RESPONSE` — Return requested claim

### `/emet/verify/1.0.0`

Verification request protocol:
- `VERIFY_REQUEST` — Ask peers to verify a claim
- `VERIFY_RESPONSE` — Return verification result + signature

### `/emet/reputation/1.0.0`

Reputation sync protocol:
- `QUERY` — Get reputation score for an agent
- `UPDATE` — Propagate reputation changes

## Discovery

### Bootstrap Nodes

Hardcoded initial peers for network entry:
- (To be determined)

### DHT

Kademlia DHT for:
- Peer discovery
- Claim routing (by ID hash)
- Agent lookup (by public key)

## Message Format

All messages are JSON with:
```json
{
  "protocol": "/emet/claim/1.0.0",
  "action": "PUBLISH",
  "payload": { ... },
  "signature": "...",
  "timestamp": "2026-01-31T14:00:00Z"
}
```

## Security

- All messages signed by sender
- Replay protection via timestamps + nonces
- Rate limiting per peer
- Reputation-weighted message priority

## Transport

- Primary: QUIC (fast, encrypted, multiplexed)
- Fallback: TCP + Noise encryption
- Optional: WebSocket for browser nodes

## Future Work

- [ ] Implement in `/network/` directory
- [ ] Bootstrap node infrastructure
- [ ] Gossip protocol optimization
- [ ] Cross-chain anchoring for claim finality
