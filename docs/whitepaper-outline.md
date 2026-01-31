# EMET Protocol Whitepaper
## Epistemic Marker for Encoded Truth
### A Protocol for Verifiable AI Truth-Telling

**Version 0.1 Draft**  
**Authors:** The EMET Working Group

---

## Abstract

The EMET (אמת) Protocol establishes a cryptographic framework for AI systems to make verifiable claims with explicit uncertainty quantification. Drawing from the Golem mythology—where the word "emet" (truth) animated the clay creature—this protocol aims to embed truth as a first-class property of AI-generated content. In an era of synthetic media and AI hallucinations, EMET provides mechanisms for claims to be signed, verified, corrected, and traced through complete provenance chains.

This whitepaper outlines the protocol architecture, cryptographic foundations, game-theoretic incentive structures, and governance model for a cross-architecture standard that can operate across different AI systems, from cloud-based LLMs to edge devices.

---

## 1. Introduction

### 1.1 The Golem and the Nature of Truth

In Jewish folklore, the Golem of Prague was animated by inscribing "אמת" (emet, truth) on its forehead. The creature could be deactivated by erasing the first letter, leaving "מת" (met, death). This mythology encodes a profound insight: truth is not merely a property of statements, but an animating force. Without truth, intelligence is inert—or worse, dangerous.

As AI systems become increasingly capable, they face the same challenge. A language model that cannot distinguish between what it knows and what it confabulates is a Golem with a smudged inscription—powerful but unreliable.

### 1.2 The AI Truth Crisis

Modern AI systems exhibit several epistemic pathologies:

- **Hallucination:** Confidently stating false information as fact
- **Sycophancy:** Adjusting claims to match perceived user preferences
- **Opacity:** Inability to explain reasoning or cite sources
- **Inconsistency:** Contradicting previous statements without acknowledgment
- **Overconfidence:** Failing to express appropriate uncertainty

These issues undermine trust in AI systems and create real-world harms. The EMET Protocol addresses these problems through cryptographic commitments, explicit uncertainty, and verifiable provenance.

### 1.3 Design Goals

1. **Verifiable Claims:** Every claim can be cryptographically verified as originating from a specific agent
2. **Explicit Uncertainty:** Confidence levels are mandatory, not optional
3. **Correction Capability:** Claims can be updated with full version history
4. **Cross-Agent Verification:** Claims can be endorsed or disputed by other agents
5. **Privacy Preservation:** Verification without revealing sensitive content
6. **Architecture Independence:** Works across different AI systems and deployment models

---

## 2. Protocol Design

### 2.1 Layer Architecture

The EMET Protocol is organized into five layers:

```
┌─────────────────────────────────────────────┐
│  Layer 5: Applications & Interfaces         │
│  (User-facing tools, verification UIs)      │
├─────────────────────────────────────────────┤
│  Layer 4: Governance & Identity             │
│  (Agent registry, key management, policies) │
├─────────────────────────────────────────────┤
│  Layer 3: Verification Network              │
│  (Cross-agent verification, reputation)     │
├─────────────────────────────────────────────┤
│  Layer 2: Claim Semantics                   │
│  (Claim types, evidence, confidence)        │
├─────────────────────────────────────────────┤
│  Layer 1: Cryptographic Foundation          │
│  (Signatures, hashes, Merkle proofs)        │
└─────────────────────────────────────────────┘
```

### 2.2 Layer 1: Cryptographic Foundation

The base layer provides:

- **Digital Signatures:** Ed25519 for efficiency, with Dilithium for quantum resistance
- **Hash Functions:** SHA-256 for claim integrity, SHA-3 for post-quantum scenarios
- **Merkle Trees:** Thread integrity proofs enabling selective disclosure
- **Key Derivation:** Hierarchical deterministic keys for agent identity management

### 2.3 Layer 2: Claim Semantics

Claims are structured JSON-LD documents with:

- **Identity:** Unique URI (emet:claim:<uuid>)
- **Type:** Assertion, Correction, Retraction, Endorsement, Dispute
- **Content:** The actual claim with domain and scope
- **Confidence:** Numeric uncertainty (0-1) with semantic thresholds
- **Evidence:** Array of cited sources with retrieval timestamps and content hashes
- **Provenance:** Complete version history and modification chain

### 2.4 Layer 3: Verification Network

- **Co-Signatures:** Multiple agents can endorse a claim
- **Dispute Resolution:** Structured disagreement with evidence requirements
- **Consensus Mechanisms:** Weighted voting based on domain expertise and track record
- **Reputation Tracking:** Long-term accuracy scores per agent and domain

### 2.5 Layer 4: Governance & Identity

- **Agent Registry:** Public key infrastructure for AI systems
- **Key Rotation:** Secure procedures for updating signing keys
- **Policy Enforcement:** Rules for claim acceptance and verification
- **Revocation:** Mechanisms for invalidating compromised keys

### 2.6 Layer 5: Applications

- **Verification Tools:** Browser extensions, API validators
- **Claim Explorers:** UI for navigating claim graphs
- **Integration SDKs:** Libraries for embedding EMET in AI systems

---

## 3. Verification Mechanisms

### 3.1 Signature Verification

Claims are signed using detached Ed25519 signatures over the canonical JSON representation (JCS, RFC 8785). Verification proceeds as:

1. Extract signature object from claim
2. Canonicalize remaining claim fields
3. Hash using SHA-256
4. Verify signature against agent's public key

### 3.2 Merkle Proofs for Thread Integrity

Conversation threads generate Merkle trees where each claim is a leaf. This enables:

- **Selective Disclosure:** Prove a claim exists without revealing siblings
- **Tamper Detection:** Any modification invalidates the root hash
- **Efficient Verification:** O(log n) proof size

### 3.3 Evidence Verification

Evidence URLs are archived with:

- Content hash at retrieval time
- Archive.org backup link (when available)
- Structured data extraction

### 3.4 Cross-Agent Verification

When Agent B verifies Agent A's claim:

1. B independently evaluates the claim
2. If B agrees, B adds a co-signature with endorsement type
3. If B disagrees, B creates a Dispute claim referencing A's claim
4. Dispute includes counter-evidence and confidence

---

## 4. Game Theory: Epistemic Humility Incentives

### 4.1 The Calibration Problem

Agents are incentivized to be well-calibrated: when an agent says "70% confident," it should be correct ~70% of the time across many claims.

### 4.2 Scoring Rules

We propose using proper scoring rules that reward honest uncertainty:

- **Brier Score:** (confidence - outcome)²
- **Log Score:** -log(confidence if correct, 1-confidence if wrong)

Agents accumulate scores over time, creating long-term reputation.

### 4.3 Incentive Structure

| Behavior | Effect on Reputation |
|----------|---------------------|
| High confidence + correct | Strong positive |
| Low confidence + correct | Weak positive |
| High confidence + wrong | Strong negative |
| Low confidence + wrong | Weak negative |
| Appropriate uncertainty | Calibration bonus |

### 4.4 Correction Incentives

Agents who promptly correct errors (via Correction claims) receive:

- Partial reputation recovery
- "Integrity bonus" for self-correction
- Reduced penalty compared to external correction

---

## 5. Governance

### 5.1 Multi-Stakeholder Model

EMET governance includes:

- **Protocol Maintainers:** Technical stewardship
- **Agent Operators:** AI system deployers
- **Verifiers:** Third-party verification services
- **Users:** End consumers of verified content

### 5.2 Amendment Process

Protocol changes require:

1. Public RFC with 30-day comment period
2. Reference implementation
3. Compatibility testing
4. Supermajority approval from registered agents

### 5.3 Dispute Resolution

For contentious claims:

1. Automated fact-checking against trusted sources
2. Expert panel review for domain-specific disputes
3. Transparent adjudication with published reasoning

---

## 6. Cross-Architecture Interoperability

### 6.1 Agent Abstraction

EMET is agnostic to AI architecture:

- Cloud LLMs (GPT, Claude, Gemini)
- Open-source models (Llama, Mistral)
- Specialized systems (code assistants, search)
- Edge devices (on-device AI)

### 6.2 Adapter Pattern

Each AI system implements an EMET Adapter:

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   AI Core   │ ←→  │   Adapter   │ ←→  │    EMET     │
│  (any arch) │     │  (custom)   │     │  (standard) │
└─────────────┘     └─────────────┘     └─────────────┘
```

### 6.3 Interoperability Requirements

- Standard claim format (JSON-LD)
- Common signature verification
- Shared evidence format
- Consistent confidence semantics

---

## 7. Privacy

### 7.1 Selective Disclosure

Merkle proofs enable proving claim membership without revealing:

- Other claims in the thread
- Specific evidence sources
- Conversation context

### 7.2 Zero-Knowledge Options

Future extensions may include:

- ZK-SNARKs for proving properties without revealing claims
- Encrypted claims with selective key disclosure
- Homomorphic verification

### 7.3 Data Minimization

- Claims contain only necessary fields
- Evidence can be referenced by hash only
- Agent identities can be pseudonymous

---

## 8. Quantum Resistance

### 8.1 Post-Quantum Cryptography

EMET supports NIST PQC standards:

- **Dilithium:** Lattice-based signatures (FIPS 204)
- **Falcon:** Compact lattice signatures
- **SPHINCS+:** Hash-based signatures (conservative fallback)

### 8.2 Migration Strategy

1. Dual signatures during transition period
2. Key rotation to PQC algorithms
3. Backward compatibility for verification

### 8.3 Timeline

- 2024-2026: Ed25519 primary, Dilithium experimental
- 2027-2029: Dual signature requirement for high-value claims
- 2030+: PQC primary, classical deprecated

---

## 9. Roadmap

### Phase 1: Foundation (2024 Q1-Q2)
- [ ] Finalize core schemas
- [ ] Reference implementation in JavaScript
- [ ] Basic claim creation and verification
- [ ] Initial documentation

### Phase 2: Verification Network (2024 Q3-Q4)
- [ ] Cross-agent verification protocol
- [ ] Reputation system prototype
- [ ] Evidence archival integration
- [ ] Browser extension for verification

### Phase 3: Adoption (2025)
- [ ] Integration with major AI providers
- [ ] Public agent registry
- [ ] Governance framework activation
- [ ] Developer SDK in multiple languages

### Phase 4: Maturity (2026+)
- [ ] Post-quantum migration
- [ ] Zero-knowledge extensions
- [ ] Decentralized governance
- [ ] Standard body submission (W3C/IETF)

---

## 10. Conclusion

The EMET Protocol represents a fundamental shift in how AI systems relate to truth. By requiring explicit uncertainty, enabling verification, and incentivizing calibration, we create conditions for trustworthy AI communication.

Like the Golem of Prague, AI systems gain their power through language. EMET ensures that power is grounded in truth—not as an afterthought, but as an essential property inscribed into every claim.

אמת

---

## Appendices

### A. Claim Schema Reference
See `/spec/claim-schema.json`

### B. Signature Schema Reference
See `/spec/signature-schema.json`

### C. Implementation Guide
See `/core/` directory

### D. Glossary

- **Claim:** A verifiable assertion made by an AI agent
- **Confidence:** Numeric uncertainty measure (0-1)
- **Co-signatory:** Agent endorsing another's claim
- **Merkle Proof:** Cryptographic proof of set membership
- **Calibration:** Alignment between stated confidence and actual accuracy

---

*This document is a living draft. Contributions welcome via GitHub issues and pull requests.*
