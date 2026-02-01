# EMET Protocol Python SDK

Python SDK for the [EMET Protocol](https://github.com/emet-protocol/emet-core) — trustless claim verification on Base.

## Install

```bash
pip install emet-sdk
```

Or from source:

```bash
cd python-sdk
pip install -e ".[dev]"
```

## Quick Start

```python
import asyncio
from emet import EMETClient

async def main():
    # Initialize client (read-only)
    client = EMETClient(rpc_url="https://mainnet.base.org")

    # Or with a signer for write operations
    client = EMETClient(
        private_key="0x...",
        rpc_url="https://mainnet.base.org",
    )

    # Check balance
    balance = await client.get_balance()
    print(f"EMET balance: {client.from_wei(balance)} EMET")

    # Submit a claim (stakes EMET as collateral)
    stake = client.to_wei(1000)  # 1000 EMET
    tx = await client.submit_claim(
        "The Earth orbits the Sun",
        stake=stake,
        evidence="https://example.com/evidence",
    )
    print(f"Claim submitted: {tx['transactionHash'].hex()}")

    # Read claim data
    claim = await client.get_claim(0)
    print(f"Claim #{claim.claim_id}: {claim.status.label}")
    print(f"  Submitter: {claim.submitter}")
    print(f"  Stake: {claim.stake_ether} EMET")
    print(f"  Evidence: {claim.evidence_uri}")

asyncio.run(main())
```

## Features

### Claims

```python
# Submit a claim with evidence
tx = await client.submit_claim(
    "claim text",
    stake=client.to_wei(1000),
    evidence="https://...",
)

# Read claim details
claim = await client.get_claim(0)

# Get total claim count
count = await client.get_claim_count()

# Check protocol parameters
min_stake = await client.get_minimum_stake()
period = await client.get_challenge_period()

# Verify unchallenged claims after the challenge period
if await client.can_verify_unchallenged(0):
    await client.verify_unchallenged(0)
```

### Staking

```python
# Stake in support of a claim
await client.stake_for(claim_id=0, amount=client.to_wei(500))

# Check stake totals
stakes = await client.get_stake_totals(0)
print(f"For: {stakes.total_for_ether} EMET")
print(f"Against: {stakes.total_against_ether} EMET")
print(f"Ratio: {stakes.ratio}")

# Check your stakes
my_for, my_against = await client.get_user_stakes(0)

# Preview payout
payout = await client.calculate_payout(0, assume_verified=True)

# Withdraw after resolution
await client.withdraw(claim_id=0)
```

### Reputation

```python
# Full reputation info
rep = await client.get_reputation("0x...")
print(f"Score: {rep.score}")
print(f"Tier: {rep.tier}")        # Unknown, Newcomer, Contributor, Trusted, Expert, Authority
print(f"Multiplier: {rep.multiplier}x")  # 1.0x – 2.0x

# Quick lookups
score = await client.get_reputation_score()
tier = await client.get_reputation_tier()
```

### Token Operations

```python
# Check balance
balance = await client.get_balance()

# Transfer tokens
await client.transfer("0xRecipient...", client.to_wei(100))

# Manual approval (auto_approve handles this automatically)
await client.approve("0xSpender...", client.to_wei(5000))

# Check allowance
allowance = await client.get_allowance("0xSpender...")
```

### Utilities

```python
# Unit conversion
wei_amount = EMETClient.to_wei(1000)       # 1000 * 10^18
human_amount = EMETClient.from_wei(wei_amount)  # 1000.0

# Hash a claim (same as on-chain keccak256)
claim_hash = EMETClient.hash_claim("The sky is blue")

# Access the underlying web3 instance
block = await client.w3.eth.get_block("latest")
```

## Contract Addresses (Base Mainnet)

| Contract | Address |
|----------|---------|
| EMET Token | `0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C` |
| EMETRegistry | `0x9D2550eB1Ee613E0f35c70524e1304B26392b0aC` |
| EMETStake | `0x63901ED9Fbd8262B4505819E2F39a6145f28Fbf0` |
| EMETReputation | `0xAb6Aa88faaC77c1d941eE25A81e397a7A6fa3a85` |

## Custom Contract Addresses

Override defaults for testnet or custom deployments:

```python
client = EMETClient(
    private_key="0x...",
    rpc_url="https://sepolia.base.org",
    token_address="0x...",
    registry_address="0x...",
    stake_address="0x...",
    reputation_address="0x...",
)
```

## Error Handling

```python
from emet import (
    EMETError,
    InsufficientStakeError,
    ClaimNotFoundError,
    InsufficientBalanceError,
    TransactionFailedError,
)

try:
    await client.submit_claim("test", stake=1)
except InsufficientStakeError as e:
    print(f"Need at least {e.required} wei, got {e.provided}")
except InsufficientBalanceError as e:
    print(f"Balance: {e.balance}, need: {e.required}")
except ClaimNotFoundError as e:
    print(f"Claim {e.claim_id} doesn't exist")
except TransactionFailedError as e:
    print(f"TX failed: {e.tx_hash}")
except EMETError as e:
    print(f"EMET error: {e}")
```

## Data Types

The SDK returns typed dataclasses:

```python
from emet import Claim, ClaimStatus, StakeInfo, ReputationInfo

# ClaimStatus enum
ClaimStatus.ACTIVE      # 0 — open for challenges
ClaimStatus.CHALLENGED  # 1 — currently disputed
ClaimStatus.VERIFIED    # 2 — resolved in favor
ClaimStatus.REJECTED    # 3 — resolved against

# Claim properties
claim.is_active       # True if status == ACTIVE
claim.is_challenged   # True if status == CHALLENGED
claim.is_resolved     # True if VERIFIED or REJECTED
claim.stake_ether     # Stake in human-readable EMET
```

## Development

```bash
# Install with dev dependencies
pip install -e ".[dev]"

# Run tests
pytest

# Run specific tests
pytest tests/test_types.py -v
```

## Requirements

- Python 3.10+
- web3.py >= 6.0

## License

MIT
