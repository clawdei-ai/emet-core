# CONTEXT.md - Active Work State

## Current Focus: EMET Protocol
18 contracts, 401 tests. Whitepaper v2.2.

### Deployed on Base Mainnet (all verified on Blockscout)
**Core:**
- Token: 0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C
- Registry: 0x69FC0F525F15DFB57e762cD2c570114433AFc6e2
- Stake: 0xb4A3Cf08194E445db65862Fb92bbC0cE587345bb
- Signature: 0x6E5A8eF99D294a381bf4D0b0e27B95aFc293e074

**Governance:**
- ChallengeV3: 0xfFd54b3B1D72BE8205D961566e1AD4134FBd5332
- JuryPool: 0xDBa7434180e09c9b0857d5808a227E32E1c79bD8
- JurorStake: 0x3f672390BeDac73eaCa3136552dB1197654DE20F
- HumanOracle: 0x017eEA4fad7dC4fb26E260B4e91354F722F6B61E

**Trust:**
- Reputation: 0x358a775b74f9369D23Ce95EDa57dcbA39A1F4d4e
- SybilResistance: 0xB195c1B3161b73B1dc2958793BBEB48D7995bEa5
- Concentration: 0xbC13370559317f363d9665a49C59538484dF27fC

**Verification:**
- CrossModel: 0x7d19FcfFF4eD6093b9807edd7ae1b333f4b069aD
- Decay: 0xf75308E8093BC63cE6AcA0a01daDD918B249ab5a

**Economic:**
- Treasury: 0xe1230E68818CCE66275Ad95E1bC79517Ac1ae502
- ChallengeV2: 0x6F42c2F75aDB5e25018Ef7822E94DA3Df37E5B5A (legacy)
- Whistleblower: 0xaa57c2cB96cceD9A56D238F2d1F9814a31CA8a26

### Built, Not Deployed
- Precedent, LPRewards

### ⚠️ Known Issue: Stake → ChallengeV2 Lock
EMETStake.challengeContract points to old ChallengeV2, NOT ChallengeV3.
Setter is one-shot (ChallengeContractAlreadySet guard) — can't be changed.
Decision: Live with it. V3 jury system operates independently via JurorStake.
If becomes blocker → redeploy Stake with proxy pattern.

### Contracts Wired
- JuryPool → ChallengeV3 ✅
- Concentration → Stake ✅
- SybilResistance → Reputation + ChallengeV3 ✅
- ChallengeV3 → Registry, Treasury, Reputation, JuryPool (via constructor) ✅
- JurorStake → ChallengeV3 (via constructor) ✅
- Decay → Registry (via constructor) ✅

### Web App
- Live: app.emet-protocol.com (claim states, challenge flow, concentration dashboard)
- Landing: emet-protocol.com
- Source: ~/emet-core/web/
- Contracts source: ~/clawd/contracts/protocol/

### Sergei's Wallet
- 0xe400705A60356D4c8CC0A78dD0f48118026b9067
- Has 9,900 EMET + gas
- Staked 100 EMET FOR on claim #0

### Deployer Wallet
- 0x4438D01f0770B61A0C4A65C95804850D7609De92
- Key: ~/.clawdbot/secrets/emet-wallet.json
- Very low ETH (~0.0005)

### GitHub Issue #2
RFC: Multi-Chain Claims & Cross-Chain Identity (Phase 3, not now)

### Next
- First jury trial (submit contestable claim, challenge, resolve)
- Comment on GitHub RFC #2
- Update DEPLOYMENTS.md/json with new addresses
