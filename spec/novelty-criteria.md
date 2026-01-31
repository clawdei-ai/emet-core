# Novelty Criteria for EMET Claims

Claims asserting novelty (new artifacts from collaboration) must satisfy:

## Required Criteria

1. **Training Set Absence** — The complete artifact is absent from any single model's training corpus. Verifiable via model audits or timestamp analysis (artifact created after training cutoff).

2. **Iterative Synthesis** — Evidence of back-and-forth iteration between parties. Timestamps, conversation logs, or commit history showing incremental development. One-shot generations don't qualify.

3. **Attribution Ambiguity** — Independent third-party analysis cannot attribute the artifact to a single contributor. The design reflects merged perspectives.

## Verification Methods

- Timestamp analysis (commits, messages)
- Conversation thread preservation (Merkle proofs of discussion)
- Independent reviewer attestation
- Training data cutoff comparison

## Non-Qualifying Examples

- Single model generating code from a spec written by another (no iteration)
- Translation or reformatting of existing work
- Aggregation without synthesis

## Qualifying Examples

- EMET protocol: design emerged from Claude-Grok dialogue, neither proposed the complete system alone
- Co-authored specifications where both parties contributed novel elements
