# EMET Protocol — Deployed Contracts

**Chain:** Base Mainnet (8453)
**Deployer:** `0x4438D01f0770B61A0C4A65C95804850D7609De92`
**Version:** 2.2 — 20 contracts, 401 tests
**Last Updated:** February 12, 2026

## Core

| Contract | Address | Verified |
|----------|---------|----------|
| EMET Token (ERC-20) | `0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C` | ✅ |
| **EMETRegistry (v2 — with claim fees)** | `0x266D8343463deE2920CBE97EfB72B4540E491DeC` | ✅ |
| EMETStake | `0xb4A3Cf08194E445db65862Fb92bbC0cE587345bb` | ✅ |
| EMETSignature | `0x6E5A8eF99D294a381bf4D0b0e27B95aFc293e074` | ✅ |

## Governance

| Contract | Address | Verified |
|----------|---------|----------|
| **EMETChallengeV3 (v2 — with resolution fees)** | `0x697BAC4b1FCA88e12003C0ef3E03bdcbdE5d17D9` | ✅ |
| **EMETJuryPool (v2 — wired to ChallengeV3 v2)** | `0x018377D4e725703974A0087f8Ca8066c4aE8b045` | ✅ |
| EMETJurorStake | `0x3f672390BeDac73eaCa3136552dB1197654DE20F` | ✅ |
| EMETHumanOracle | `0x017eEA4fad7dC4fb26E260B4e91354F722F6B61E` | ✅ |

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

## Economic

| Contract | Address | Verified |
|----------|---------|----------|
| EMETTreasury | `0xe1230E68818CCE66275Ad95E1bC79517Ac1ae502` | ✅ |
| EMETWhistleblower | `0xaa57c2cB96cceD9A56D238F2d1F9814a31CA8a26` | ✅ |

## Fee Configuration

| Parameter | Value | Contract |
|-----------|-------|----------|
| Claim Fee | 10 EMET | EMETRegistry (v2) |
| Resolution Fee | 5% (500 bps) | EMETChallengeV3 (v2) |
| Minimum Stake | 100 EMET | EMETRegistry (v2) |
| Challenge Period | 7 days (604800s) | EMETRegistry (v2) |

## Legacy / Deprecated

> ⚠️ **Do NOT use for new interactions.** These contracts remain on-chain but are superseded.

| Contract | Address | Superseded By |
|----------|---------|---------------|
| EMETRegistry (v1) | `0x69FC0F525F15DFB57e762cD2c570114433AFc6e2` | Registry v2 |
| EMETChallengeV2 | `0x6F42c2F75aDB5e25018Ef7822E94DA3Df37E5B5A` | ChallengeV3 v2 |
| EMETChallengeV3 (v1) | `0xfFd54b3B1D72BE8205D961566e1AD4134FBd5332` | ChallengeV3 v2 |
| EMETJuryPool (v1) | `0xDBa7434180e09c9b0857d5808a227E32E1c79bD8` | JuryPool v2 |

## Not Yet Deployed

| Contract | Status |
|----------|--------|
| EMETPrecedent | Built, tested |
| EMETLPRewards | Built, tested |

## Known Issues

- **EMETStake.challengeContract** points to ChallengeV2 (`0x6F42...`), not ChallengeV3. One-shot setter prevents update.
- **JuryPool v2 deployed** (`0x018377D4e725703974A0087f8Ca8066c4aE8b045`) — properly wired to ChallengeV3 v2.
- **ChallengeV3 v2.juryPool** has immutable reference to OLD JuryPool v1. To use JuryPool v2, need ChallengeV3 v3 deployment.
- **JurorStake.challengeContract** same issue — points to legacy ChallengeV3 v1.
- **Decay.registry** points to legacy Registry v1. Would need redeployment to use new Registry.

## Liquidity

| Pool | Address |
|------|---------|
| Uniswap V3 (EMET/WETH) | `0x0C7f51B0dB3e319736c979EBD38687cff521086A` |

## Links

- **Web App:** https://app.emet-protocol.com
- **DexScreener:** https://dexscreener.com/base/0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C
- **Uniswap:** https://app.uniswap.org/swap?chain=base&outputCurrency=0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C
- **Blockscout (Registry v2):** https://base.blockscout.com/address/0x266D8343463deE2920CBE97EfB72B4540E491DeC
- **Blockscout (ChallengeV3 v2):** https://base.blockscout.com/address/0x697BAC4b1FCA88e12003C0ef3E03bdcbdE5d17D9
