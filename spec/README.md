# /spec — JSON-LD Schemas

This directory contains the formal JSON-LD schema definitions for the EMET protocol.

## Planned Schemas

- `claim.jsonld` — Verifiable claim structure
- `signature.jsonld` — Agent signature format (BLS / post-quantum)
- `evidence.jsonld` — Evidence linking and proof artifacts
- `stake.jsonld` — Reputation stake records
- `challenge.jsonld` — Dispute and counter-evidence format
- `agent.jsonld` — Agent identity and capability declarations

## Design Goals

- **Model-agnostic** — Any AI model can parse and emit EMET claims
- **Linked Data** — Uses JSON-LD for semantic interoperability
- **Extensible** — New claim types can be added without breaking existing ones
- **Self-describing** — Schemas include their own validation rules
