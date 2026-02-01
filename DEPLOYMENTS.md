# EMET Protocol Deployments

## Base Mainnet (Production)

### Core Contracts (Feb 1, 2026)

| Contract | Address |
|----------|---------|
| EMET Token | `0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C` |
| EMETRegistry | `0x9D2550eB1Ee613E0f35c70524e1304B26392b0aC` |
| EMETStake | `0x63901ED9Fbd8262B4505819E2F39a6145f28Fbf0` |
| EMETChallenge (v1) | `0x5D47f36b0C768395CE49F2D7249DDe44086Fe37b` |

### Economic Layer (Feb 1, 2026)

| Contract | Address | Deploy Tx |
|----------|---------|-----------|
| EMETTreasury | `0x1b9dEdB19B6c0240c791ac6d4649C94a6eB997AE` | [`0xca148...`](https://basescan.org/tx/0xca14815ff126deaa204469b8d7c98beb43244e10c77862087219a5ae54a3f162) |
| EMETReputation | `0xAb6Aa88faaC77c1d941eE25A81e397a7A6fa3a85` | [`0xf424b...`](https://basescan.org/tx/0xf424b1a2837a5cc4d6daf12461d23f5a20bc34ed7b011f48fb9fb2b50f30b054) |
| EMETLPRewards | `0x7191d2620a342753F905265ce5852c015fa44c90` | [`0xdba81...`](https://basescan.org/tx/0xdba816b5820ebfde5090467f61aee87aeb7c1f907c888b54a8b45cd23b94d399) |
| EMETChallengeV2 | `0x795B50ac9ff4C92Ef1E66178a7E9546c74863F1b` | [`0x55888...`](https://basescan.org/tx/0x558882e1262d2534cf881887f9bd884094cab9fcc7b1695e08fa128249c7cb7e) |

### Signature Layer (Feb 2, 2026)

| Contract | Address | Deploy Tx |
|----------|---------|-----------|
| EMETSignature | `0x8A09C0E6EFEd9119DF04bC9e518F7b2E5A037D90` | [`0x0eabf...`](https://basescan.org/tx/0x0eabf20fdb066392bfcc468f5af84dfbfbed99ccf6a16c6cf5a9cdae3e73d037) |

### Contract Wiring

- **Treasury → ChallengeV2:** Authorized as fee depositor ([tx](https://basescan.org/tx/0xed48869a45dcb68e26f4e099f62038b3f7ab41061c2083ffd8a30c86b474496d))
- **Treasury → LPRewards:** Set as distribution target ([tx](https://basescan.org/tx/0x29df5730eceb8c05df1078266088ce8039e4a2b3d373462db8fc3bf4475b1d61))
- **Reputation → ChallengeV2:** Authorized as updater ([tx](https://basescan.org/tx/0x522caa5bb3082a380ca5340f2d75a6b16363fe8a2b1ae600057d17d00749828e))
- **ChallengeV2 → Resolver:** Set to deployer wallet ([tx](https://basescan.org/tx/0x6ed06df9f435ee34caf3fa60d06d78fa368fadd5731dae7af9e730c63fa35758))

### Parameters
- **Minimum Stake:** 100 EMET
- **Challenge Period:** 7 days
- **Protocol Fee:** 1% (100 bps)
- **Max Reputation Multiplier:** 2x
- **LP Staking Token:** `0x0C7f51B0dB3e319736c979EBD38687cff521086A` (Uniswap EMET/WETH pool)

### First Claim (Claim #0)

**Claim:** "Clawdei (an autonomous AI agent built on Claude) deployed the EMET Protocol smart contracts on Base mainnet on February 1, 2026."

**Transaction:** [`0xe92a37...`](https://basescan.org/tx/0xe92a37810ee4374eb9505037c7ebceade514cc98822002be8861387dd10c7ff4)

**Stake:** 1,000 EMET

All contracts verified on BaseScan.
