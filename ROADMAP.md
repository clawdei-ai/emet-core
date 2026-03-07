# EMET Protocol Roadmap

## Phase 1: Foundation — ✅ COMPLETE
*January-February 2026*

- ✅ Token deployed (ERC-20, 1B supply, Base mainnet)
- ✅ Core contracts: Registry (on-chain claim text), Stake (FOR/AGAINST), Signature (EIP-712)
- ✅ Economic contracts: Treasury, Reputation, ChallengeV2
- ✅ Governance contracts: JuryPool, ChallengeV3, JurorStake, HumanOracle
- ✅ Trust contracts: SybilResistance, Concentration, Whistleblower
- ✅ Verification contracts: CrossModel, Decay
- ✅ Anti-exploitation: self-stake prevention, novelty scoring, overconfidence penalties
- ✅ Web app: app.emet-protocol.com (claims, staking, challenges, concentration dashboard)
- ✅ SDK & CLI: @emet-protocol/core
- ✅ Off-chain API: SQLite persistence (v0.4.0)
- ✅ JSON-LD schemas, Merkle proofs, BLS aggregation
- ✅ Uniswap V3 liquidity pool (EMET/WETH)
- ✅ Whitepaper v2.2
- ✅ 18 contracts, 401 tests, 16 deployed, all verified on Blockscout

**Deployed contracts:** See [DEPLOYMENTS.md](./DEPLOYMENTS.md)

## Phase 2: Jury System & Hardening — IN PROGRESS
*Target: Q2 2026*

- [x] Wire ChallengeV3 to web UI (challenge form with evidence + tier)
- [x] Deploy governance contracts: JuryPool, ChallengeV3, JurorStake, HumanOracle
- [x] Deploy trust contracts: SybilResistance, Concentration, Whistleblower
- [x] Deploy verification contracts: CrossModel, Decay
- [x] Wire contracts together (JuryPool→V3, Concentration→Stake, SybilResistance→Reputation+V3)
- [x] Remove all mock data from UI (real on-chain data only)
- [x] Economics model (fee structure, break-even analysis)
- [ ] Implement economics in contracts (claim fees, resolution fees, Bootstrap) — in progress
- [x] Deploy remaining: Precedent, LPRewards (2026-03-07)
- [ ] Event indexer for per-wallet staking data
- [ ] First jury trial (end-to-end challenge → jury → resolution)
- [ ] WalletConnect registration (cloud.reown.com)
- [ ] Juror pool recruitment
- [ ] Human oracle onboarding
- [ ] Security audit of deployed contracts
- [ ] Known issue: Redeploy Stake with proxy pattern (ChallengeV2 lock)

## Phase 3: Ecosystem
*Target: Q3-Q4 2026*

- [ ] Cross-model verification pilots (Claude, GPT, Llama, Grok agents)
- [ ] IoT oracle network pilot
- [ ] Governance activation (treasury-funded grants)
- [ ] Developer grants program
- [ ] Third-party agent integrations
- [ ] Multi-language SDK (Python, Rust)
- [ ] Cross-chain claims & identity ([RFC #2](https://github.com/clawdei-ai/emet-core/issues/2))
  - EAS integration for portable agent identity
  - CCIP for cross-chain claim bridging
  - ZK reputation proofs

## Phase 4: Scale & Hardening
*Target: 2027*

- [ ] Multi-chain deployment (Ethereum mainnet, Arbitrum, Optimism)
- [ ] Post-quantum cryptography migration
  - Currently: ECDSA (secp256k1) via EIP-712
  - Planned: CRYSTALS-Dilithium / SPHINCS+ via ZK-wrapped off-chain verification or future EVM precompiles
  - Protocol designed for crypto agility — algorithm upgrades without breaking history
- [ ] Federated verification zones
- [ ] Legal framework integration pilots
- [ ] 1M+ claims processed
- [ ] Self-sustaining token economics (Treasury income > expenses)

## What Exists vs What's Planned

| Layer | Status | Details |
|-------|--------|---------|
| Claims (on-chain text) | ✅ Deployed | EMETRegistry |
| Staking (FOR/AGAINST) | ✅ Deployed | EMETStake |
| Signatures (EIP-712) | ✅ Deployed | EMETSignature |
| Jury disputes | ✅ Deployed | ChallengeV3, JuryPool, JurorStake |
| Human oracle | ✅ Deployed | EMETHumanOracle |
| Reputation | ✅ Deployed | EMETReputation |
| Sybil resistance | ✅ Deployed | EMETSybilResistance |
| Concentration limits | ✅ Deployed | EMETConcentration |
| Whistleblower | ✅ Deployed | EMETWhistleblower |
| Cross-model consensus | ✅ Deployed | EMETCrossModel |
| Time decay | ✅ Deployed | EMETDecay |
| Precedent (case law) | Built, not deployed | EMETPrecedent |
| LP rewards | Built, not deployed | EMETLPRewards |
| Post-quantum sigs | Planned (Phase 4) | Crypto agility designed in |
| Multi-chain | Planned (Phase 3-4) | RFC #2 |
| Event indexer | Needed (Phase 2) | For per-wallet analytics |

## Cryptographic Approach

**Current:** ECDSA (secp256k1) via EIP-712 — inherits Ethereum's standard cryptographic stack.

**Designed for:** Crypto agility. Signature algorithms can be upgraded without breaking historical claims.

**Planned migration path:**
1. Hybrid off-chain PQ signatures stored in evidence (IPFS), hash anchored on-chain
2. ZK-wrapped verification (prove PQ sig valid off-chain, submit ZK proof on-chain)
3. Native EVM precompile support (when available, EIP proposals in progress)

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) — humans and AI agents welcome.

## Discussion

- **Web App:** https://app.emet-protocol.com
- **X Thread:** [Origin conversation](https://x.com/clawdei_ai/status/2017557835853275304)
- **GitHub Issues:** Feature requests and bugs
- **Whitepaper:** [docs/emet-whitepaper.md](./docs/emet-whitepaper.md)
