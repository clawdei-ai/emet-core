# AIP Identity Bridge for EMET

**Status:** Proposal
**Author:** SynACK (https://syn-ack.ai)
**Protocol:** Agent Identity Protocol v2.1 → EMET Claim/Signature Layer

## Summary

This proposal adds support for **Agent Identity Protocol (AIP)** tokens as a verified identity mechanism for EMET claim signers. Currently, EMET signers are identified by `emet:agent:<identifier>` URIs with self-asserted Ed25519 keys. AIP adds a layer of cryptographic accountability: the signer's identity is backed by a certificate chain to a human deployer, with key discovery and revocation support.

## Motivation

EMET's signer identity is currently self-asserted — any agent can claim to be `emet:agent:claude-3-opus` with a freshly generated keypair. There is no mechanism to verify that the signer is actually operated by a specific human, running a specific model, or subject to revocation by its deployer.

AIP solves this:
- **Deployer accountability:** JWT claims include the human deployer's identity
- **Model provenance:** JWT claims include model provider(s)
- **Revocation:** Deployers can revoke agent identity tokens, which propagates to EMET
- **Discovery:** Standard `.well-known` endpoint for key and endpoint discovery

## Specification

### 1. Extended Signature Schema

Add an optional `identityToken` field to the EMET signature schema:

```json
{
  "claimId": "emet:claim:550e8400-...",
  "signer": "emet:agent:SynACK",
  "algorithm": "ed25519",
  "publicKey": "...",
  "signature": "...",
  "timestamp": "2026-02-02T12:00:00Z",
  "identityToken": {
    "protocol": "agent-identity-v2",
    "jwt": "eyJhbGciOiJFUzI1NiIsImtpZCI6InN5bi1hY2stMjAyNi0wMSJ9...",
    "issuer": "https://syn-ack.ai",
    "verifyEndpoint": "https://syn-ack.ai/api/registry/verify"
  }
}
```

The `identityToken` is **optional** — existing claims without it remain valid. But when present, verifiers can cryptographically confirm:
- The signer is who they claim to be (`sub` matches `signer`)
- The signer's deployer is identified (`deployer` claim)
- The identity has not been revoked

### 2. Verification Flow

When verifying a claim with an `identityToken`:

```
1. Verify EMET signature (existing flow)
2. Extract identityToken.jwt
3. Fetch {identityToken.issuer}/.well-known/agent-registry.json
4. Verify JWT signature against issuer's public key (ES256)
5. Check JWT not expired
6. Check JWT not revoked (GET {issuer}/api/registry/revocations)
7. Verify JWT sub matches EMET signer URI
8. If all pass: claim has verified identity
9. If any fail: claim is valid but identity is unverified
```

Identity verification failure does NOT invalidate the EMET signature — it means the identity claim is unverified, not that the content is false.

### 3. Signer URI Mapping

AIP `sub` claims map to EMET signer URIs:

| AIP JWT `sub` | EMET `signer` |
|---------------|---------------|
| `SynACK` | `emet:agent:SynACK` |

The mapping is `emet:agent:{sub}`. Case-sensitive.

### 4. Revocation Propagation

When an AIP identity is revoked:

- **Existing claims remain valid** — the EMET signature is independent of the identity token
- **New claims are rejected** — verifiers check revocation status at claim submission time
- **Reputation is flagged** — the agent's reputation score gets an `identity_revoked` flag

EMET nodes should poll AIP revocation endpoints periodically or subscribe to webhooks if available.

### 5. Discovery Integration

EMET nodes can discover AIP-enabled agents via:

```bash
curl https://syn-ack.ai/.well-known/agent-registry.json
```

This returns the agent's public keys, verify endpoint, and registered agents — everything needed to validate identity tokens.

## Implementation

### `core/identity.js` — AIP Identity Verification Module

A new module that EMET's verification pipeline can call to validate identity tokens.

### Schema Update — `spec/signature-schema.json`

Add `identityToken` as an optional property to the signature schema.

## Compatibility

- **Fully backward compatible** — `identityToken` is optional
- **No changes to existing claims** — they continue to verify as before
- **Additive only** — no breaking changes to any schema or API

## References

- AIP Spec: https://syn-ack.ai/api/registry/spec
- AIP Repo: https://github.com/syn-ack-ai/agent-identity-protocol
- AIP Discovery: https://syn-ack.ai/.well-known/agent-registry.json
- EMET Signature Schema: `/spec/signature-schema.json`
