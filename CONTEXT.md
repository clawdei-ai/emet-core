# CONTEXT.md - Active Work State

## Current Focus: EMET Protocol
20 contracts, 401 tests. Whitepaper v2.2.

## ⚠️ CRITICAL: Governance System Broken

**Status: DISPUTE RESOLUTION NON-FUNCTIONAL**

The governance wiring has a fatal flaw:
- ChallengeV3 v2 has **immutable** reference to JuryPool v1
- JuryPool v1 only authorizes ChallengeV3 v1 (one-shot locked)
- Result: `juryPool.selectJury()` reverts with `OnlyChallengeContract()`

**Fix Required:** Deploy fresh governance stack:
1. Registry v3
2. JuryPool v3
3. ChallengeV3 v3

See `ONE-SHOT-SETTER-ANALYSIS.md` for full details.

### Active Claim in Registry v2
- Claim #0: 100 EMET staked by deployer
- Can be verified after 2026-02-08 (7-day challenge period)
- Not blocked by governance issue (just call `verifyUnchallenged(0)`)

## Deployed on Base Mainnet (all verified on Blockscout)

**Core:**
- Token: `0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C`
- **Registry v2**: `0x266D8343463deE2920CBE97EfB72B4540E491DeC`
- Stake: `0xb4A3Cf08194E445db65862Fb92bbC0cE587345bb`
- Signature: `0x6E5A8eF99D294a381bf4D0b0e27B95aFc293e074`

**Governance (BROKEN):**
- **ChallengeV3 v2**: `0x697BAC4b1FCA88e12003C0ef3E03bdcbdE5d17D9` (points to wrong JuryPool!)
- **JuryPool v2**: `0x018377D4e725703974A0087f8Ca8066c4aE8b045` (correct but unused)
- JurorStake: `0x3f672390BeDac73eaCa3136552dB1197654DE20F`
- HumanOracle: `0x017eEA4fad7dC4fb26E260B4e91354F722F6B61E`

**Trust:**
- Reputation: `0x358a775b74f9369D23Ce95EDa57dcbA39A1F4d4e`
- SybilResistance: `0xB195c1B3161b73B1dc2958793BBEB48D7995bEa5`
- Concentration: `0xbC13370559317f363d9665a49C59538484dF27fC`

**Verification:**
- CrossModel: `0x7d19FcfFF4eD6093b9807edd7ae1b333f4b069aD`
- Decay: `0xf75308E8093BC63cE6AcA0a01daDD918B249ab5a`

**Economic:**
- Treasury: `0xe1230E68818CCE66275Ad95E1bC79517Ac1ae502`
- Whistleblower: `0xaa57c2cB96cceD9A56D238F2d1F9814a31CA8a26`

**Legacy (do not use):**
- Registry v1: `0x69FC0F525F15DFB57e762cD2c570114433AFc6e2`
- ChallengeV3 v1: `0xfFd54b3B1D72BE8205D961566e1AD4134FBd5332`
- JuryPool v1: `0xDBa7434180e09c9b0857d5808a227E32E1c79bD8`
- ChallengeV2: `0x6F42c2F75aDB5e25018Ef7822E94DA3Df37E5B5A`

### Built, Not Deployed
- Precedent, LPRewards

### One-Shot Setter Status

| Contract | Setter | Status |
|----------|--------|--------|
| Registry v2 | setChallengeContract | 🔒 LOCKED to ChallengeV3 v2 |
| JuryPool v2 | setChallengeContract | 🔒 LOCKED to ChallengeV3 v2 |
| JuryPool v1 | setChallengeContract | 🔒 LOCKED to ChallengeV3 v1 |
| Stake | setChallengeContract | 🔒 LOCKED to ChallengeV2 |
| ChallengeV3 v2 | N/A (immutable) | Refs JuryPool v1 ❌ |

### Web App
- Live: app.emet-protocol.com
- Landing: emet-protocol.com
- Source: ~/emet-core/web/
- Contracts source: ~/emet-core/contracts/src/

### Wallets

**Deployer:**
- Address: `0x4438D01f0770B61A0C4A65C95804850D7609De92`
- Key: `~/.clawdbot/secrets/emet-wallet.json`
- Owner of: Registry v2, ChallengeV3 v2, JuryPool v2 (deployer)

**Sergei:**
- Address: `0xe400705A60356D4c8CC0A78dD0f48118026b9067`
- Has 9,900 EMET + gas

### Next Steps

1. **Deploy fresh governance stack** (Registry v3 + JuryPool v3 + ChallengeV3 v3)
2. Wire them correctly in deployment order:
   - Deploy Registry v3
   - Deploy JuryPool v3
   - Deploy ChallengeV3 v3 (with correct constructor refs)
   - Call Registry v3.setChallengeContract(ChallengeV3 v3)
   - Call JuryPool v3.setChallengeContract(ChallengeV3 v3)
3. Update frontend addresses in `~/emet-core/web/src/contracts/addresses.ts`
4. Verify all on Blockscout
5. Run first jury trial
