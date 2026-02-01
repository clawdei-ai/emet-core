# EMET Protocol — Deployed Contracts

**Chain:** Base Mainnet (8453)
**Deployer:** `0x4438D01f0770B61A0C4A65C95804850D7609De92`
**Version:** 2.1 — 18 contracts, 401 tests
**Last Updated:** February 1, 2026

## Core

| Contract | Address | Verified |
|----------|---------|----------|
| EMET Token (ERC-20) | `0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C` | ✅ |
| EMETRegistry | `0x69FC0F525F15DFB57e762cD2c570114433AFc6e2` | ✅ |
| EMETStake | `0xb4A3Cf08194E445db65862Fb92bbC0cE587345bb` | ✅ |
| EMETSignature | `0x6E5A8eF99D294a381bf4D0b0e27B95aFc293e074` | ✅ |

## Governance

| Contract | Address | Verified |
|----------|---------|----------|
| EMETChallengeV3 | `0xfFd54b3B1D72BE8205D961566e1AD4134FBd5332` | ✅ |
| EMETJuryPool | `0xDBa7434180e09c9b0857d5808a227E32E1c79bD8` | ✅ |
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
| EMETChallengeV2 (legacy) | `0x6F42c2F75aDB5e25018Ef7822E94DA3Df37E5B5A` | ✅ |
| EMETWhistleblower | `0xaa57c2cB96cceD9A56D238F2d1F9814a31CA8a26` | ✅ |

## Not Yet Deployed

| Contract | Status |
|----------|--------|
| EMETPrecedent | Built, tested |
| EMETLPRewards | Built, tested |

## Liquidity

| Pool | Address |
|------|---------|
| Uniswap V3 (EMET/WETH) | `0x0C7f51B0dB3e319736c979EBD38687cff521086A` |

## Known Issues

- **EMETStake.challengeContract** points to ChallengeV2, not ChallengeV3. One-shot setter prevents update. ChallengeV3 operates independently via JurorStake.

## Links

- **Web App:** https://app.emet-protocol.com
- **DexScreener:** https://dexscreener.com/base/0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C
- **Uniswap:** https://app.uniswap.org/swap?chain=base&outputCurrency=0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C
- **Blockscout:** https://base.blockscout.com/address/0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C
