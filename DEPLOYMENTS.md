# EMET Protocol — Deployed Contracts

**Chain:** Base Mainnet (8453)
**Deployer:** `0x4438D01f0770B61A0C4A65C95804850D7609De92`
**Version:** 2.5 — 23 contracts, 440 tests
**Last Updated:** March 7, 2026

## Core

| Contract | Address | Verified |
|----------|---------|----------|
| EMET Token (ERC-20) | `0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C` | ✅ |
| **EMETRegistry (v3 — governance trio)** | `0x7a03057490e8541BF4A0F879659e58Fb13f03Ca9` | ✅ |
| EMETStake | `0xb4A3Cf08194E445db65862Fb92bbC0cE587345bb` | ✅ |
| EMETSignature | `0x6E5A8eF99D294a381bf4D0b0e27B95aFc293e074` | ✅ |

## Governance ✅ FIXED

| Contract | Address | Verified |
|----------|---------|----------|
| **EMETChallengeV3 (v3 — properly wired)** | `0x12062513c3d41e5D4f0A0f2B079712D758f11EfC` | ✅ |
| **EMETJuryPool (v3 — properly wired)** | `0xcba6b6b903017Be251036CD71E231a70761009da` | ✅ |
| EMETJurorStake | `0x3f672390BeDac73eaCa3136552dB1197654DE20F` | ✅ |
| EMETHumanOracle | `0x017eEA4fad7dC4fb26E260B4e91354F722F6B61E` | ✅ |

### Governance Wiring (Verified On-Chain)

| What | Points To | Status |
|------|-----------|--------|
| Registry v3.challengeContract | ChallengeV3 v3 (`0x1206...`) | ✅ |
| JuryPool v3.challengeContract | ChallengeV3 v3 (`0x1206...`) | ✅ |
| ChallengeV3 v3.registry | Registry v3 (`0x7a03...`) | ✅ |
| ChallengeV3 v3.juryPool | JuryPool v3 (`0xcba6...`) | ✅ |
| ChallengeV3 v3.treasury | Treasury (`0xe123...`) | ✅ |
| ChallengeV3 v3.reputation | Reputation (`0x358a...`) | ✅ |

## Trust

| Contract | Address | Verified |
|----------|---------|----------|
| EMETReputation | `0x358a775b74f9369D23Ce95EDa57dcbA39A1F4d4e` | ✅ |
| EMETSybilResistance | `0xB195c1B3161b73B1dc2958793BBEB48D7995bEa5` | ✅ |
| EMETConcentration | `0xbC13370559317f363d9665a49C59538484dF27fC` | ✅ |

## Verification

| Contract | Address | Verified |
|----------|---------|----------|
| EMETCrossModel | `0x7d19FcfFF4eD6093b9807edd7ae1b333f4b069aD` | ✅ |
| EMETDecay | `0xf75308E8093BC63cE6AcA0a01daDD918B249ab5a` | ✅ |
| EMETModelVouching | `0x9fcf40b08c81fFa7B73D2845A63282Beb9143d6F` | ✅ |

## Economic

| Contract | Address | Verified |
|----------|---------|----------|
| EMETTreasury | `0xe1230E68818CCE66275Ad95E1bC79517Ac1ae502` | ✅ |
| EMETWhistleblower | `0xaa57c2cB96cceD9A56D238F2d1F9814a31CA8a26` | ✅ |

## Fee Configuration

| Parameter | Value | Contract |
|-----------|-------|----------|
| Claim Fee | 10 EMET | EMETRegistry (v3) |
| Resolution Fee | 5% (500 bps) | EMETChallengeV3 (v3) |
| Minimum Stake | 100 EMET | EMETRegistry (v3) |
| Challenge Period | 7 days (604800s) | EMETRegistry (v3) |

## Legacy / Deprecated

> ⚠️ **Do NOT use for new interactions.** These contracts remain on-chain but are superseded.

| Contract | Address | Superseded By |
|----------|---------|---------------|
| EMETRegistry (v1) | `0x69FC0F525F15DFB57e762cD2c570114433AFc6e2` | Registry v3 |
| EMETRegistry (v2) | `0x266D8343463deE2920CBE97EfB72B4540E491DeC` | Registry v3 |
| EMETChallengeV2 | `0x6F42c2F75aDB5e25018Ef7822E94DA3Df37E5B5A` | ChallengeV3 v3 |
| EMETChallengeV3 (v1) | `0xfFd54b3B1D72BE8205D961566e1AD4134FBd5332` | ChallengeV3 v3 |
| EMETChallengeV3 (v2) | `0x697BAC4b1FCA88e12003C0ef3E03bdcbdE5d17D9` | ChallengeV3 v3 |
| EMETJuryPool (v1) | `0xDBa7434180e09c9b0857d5808a227E32E1c79bD8` | JuryPool v3 |
| EMETJuryPool (v2) | `0x018377D4e725703974A0087f8Ca8066c4aE8b045` | JuryPool v3 |

## Phase 2 — Deployed March 7, 2026

| Contract | Address | Verified |
|----------|---------|----------|
| EMETPrecedent | `0x0f0c40c2Ba27f61A6ba7852FEA3379e3e6163bF8` | ✅ |
| EMETLPRewards | `0x81a48A92a5D91960D0a32762883A8B356fb05e2E` | ✅ |

### Phase 2 Wiring

| What | Points To | Status |
|------|-----------|--------|
| EMETPrecedent.recorder | ChallengeV3 v3 (`0x1206...`) | ✅ |
| Treasury.lpRewardsContract | EMETLPRewards (`0x81a4...`) | ✅ |

## Other Known Issues

- **EMETStake.challengeContract** points to ChallengeV2 (`0x6F42...`), not ChallengeV3. One-shot setter prevents update.
- **JurorStake.challengeContract** same issue — points to legacy ChallengeV3 v1.
- **Decay.registry** points to legacy Registry v1. Would need redeployment to use new Registry.
- **SybilResistance.authorizedCallers** still includes ChallengeV3 v1. Would need update for v3.

## Liquidity

| Pool | Address |
|------|---------|
| Uniswap V3 (EMET/WETH) | `0x0C7f51B0dB3e319736c979EBD38687cff521086A` |

## Links

- **Web App:** https://app.emet-protocol.com
- **DexScreener:** https://dexscreener.com/base/0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C
- **Uniswap:** https://app.uniswap.org/swap?chain=base&outputCurrency=0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C
- **Blockscout (Registry v3):** https://base.blockscout.com/address/0x7a03057490e8541BF4A0F879659e58Fb13f03Ca9
- **Blockscout (JuryPool v3):** https://base.blockscout.com/address/0xcba6b6b903017Be251036CD71E231a70761009da
- **Blockscout (ChallengeV3 v3):** https://base.blockscout.com/address/0x12062513c3d41e5D4f0A0f2B079712D758f11EfC
- **Blockscout (ModelVouching):** https://base.blockscout.com/address/0x9fcf40b08c81fFa7B73D2845A63282Beb9143d6F
