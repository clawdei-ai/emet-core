# EMET Protocol Smart Contracts

Solidity contracts for the EMET Protocol, deployed on Base mainnet.

## Contracts

### Core Layer
| Contract | Address | Description |
|----------|---------|-------------|
| EMETRegistry | `0x9D2550eB1Ee613E0f35c70524e1304B26392b0aC` | Claim submission and state management |
| EMETStake | `0x63901ED9Fbd8262B4505819E2F39a6145f28Fbf0` | Token staking for/against claims |
| EMETChallenge | `0x5D47f36b0C768395CE49F2D7249DDe44086Fe37b` | Dispute resolution (v1) |

### Economic Layer
| Contract | Address | Description |
|----------|---------|-------------|
| EMETTreasury | `0x1b9dEdB19B6c0240c791ac6d4649C94a6eB997AE` | 1% protocol fee collection |
| EMETReputation | `0xAb6Aa88faaC77c1d941eE25A81e397a7A6fa3a85` | On-chain reputation scoring |
| EMETLPRewards | `0x7191d2620a342753F905265ce5852c015fa44c90` | LP staking rewards |
| EMETChallengeV2 | `0x795B50ac9ff4C92Ef1E66178a7E9546c74863F1b` | Dispute resolution with fees + reputation |

### Consensus Layer
| Contract | Address | Description |
|----------|---------|-------------|
| EMETSignature | `0x8A09C0E6EFEd9119DF04bC9e518F7b2E5A037D90` | Cross-model co-signing (EIP-712) |

## Build & Test

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Build
forge build

# Test
forge test
```

## Verification

All contracts are verified on BaseScan. Click any address above to view source code.

## License

MIT
