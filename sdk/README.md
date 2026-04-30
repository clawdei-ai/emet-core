# EMET Protocol SDK

JavaScript/TypeScript SDK and CLI for interacting with the EMET Protocol on Base mainnet.

## Installation

```bash
# Clone and install
cd ~/emet-core/sdk
npm install

# Link globally for CLI usage
npm link
```

## Configuration

Set your private key as an environment variable:

```bash
export EMET_PRIVATE_KEY="your-private-key-here"

# Optional: Custom RPC
export EMET_RPC_URL="https://mainnet.base.org"
```

## CLI Usage

### Status & Info

```bash
# Show protocol status and contract addresses
emet status

# Check EMET balance
emet balance                    # Your wallet
emet balance 0x123...           # Any address

# Check reputation (stub - contract deploying)
emet reputation [address]
```

### Claims

```bash
# Submit a new claim
emet claim submit "Earth is round" --stake 1000 --evidence "https://nasa.gov"

# Get claim details
emet claim get 0

# List claims
emet claim list
emet claim list --status active
emet claim list --status verified --limit 20
```

### Staking

```bash
# Stake in support of a claim
emet stake for 0 --amount 500

# Stake against a claim
emet stake against 0 --amount 500
```

### Challenges

```bash
# Challenge a claim
emet challenge create 0 --evidence "https://counter-evidence.com" --stake 1000

# Resolve a challenge
emet challenge resolve 0
emet challenge resolve 0 --failed
```

### CLI Options

```bash
# Use a specific private key
emet --private-key "0x..." claim submit "..."

# Use a custom RPC
emet --rpc-url "https://..." status
```

## SDK Usage

### Installation

```javascript
import { EMETClient } from '@emet/sdk';

// Read-only client
const client = new EMETClient();

// With signing capability
const client = new EMETClient({
  privateKey: process.env.EMET_PRIVATE_KEY,
  rpcUrl: 'https://mainnet.base.org' // optional
});
```

### Token Operations

```javascript
// Get balance
const balance = await client.getBalance();
console.log(balance.formatted); // "1000.0"

// Get token info
const info = await client.getTokenInfo();
console.log(info); // { name, symbol, decimals, totalSupply }

// Approve tokens
await client.approve(spenderAddress, 1000);
```

### Claims

```javascript
// Submit a claim
const result = await client.submitClaim("My verifiable claim", {
  stake: 1000,
  evidence: "https://evidence.example.com"
});
console.log(result.claimId); // 1

// Get a claim
const claim = await client.getClaim(0);
console.log(claim);
// {
//   id: 0,
//   submitter: "0x...",
//   content: "...",
//   stake: { raw: 1000n, formatted: "1000.0" },
//   status: 1,
//   statusName: "Active"
// }

// List claims
const claims = await client.listClaims({
  status: 'active',
  limit: 50
});

// Get claim count
const count = await client.getClaimCount();
```

### Staking

```javascript
// Stake for a claim
await client.stakeFor(claimId, 500);

// Stake against a claim
await client.stakeAgainst(claimId, 500);

// Get stake info
const stakeInfo = await client.getStakeInfo(claimId);
console.log(stakeInfo); // { totalFor: "500.0", totalAgainst: "100.0" }

// Get your stake
const myStake = await client.getUserStake(claimId);
console.log(myStake); // { forAmount: "500.0", againstAmount: "0" }

// Withdraw stake (after resolution)
await client.withdrawStake(claimId);
```

### Challenges

```javascript
// Challenge a claim
await client.challenge(claimId, {
  evidence: "https://counter-evidence.com",
  stake: 1000
});

// Get challenge info
const challenge = await client.getChallenge(claimId);

// Check if resolvable
const canResolve = await client.canResolveChallenge(claimId);

// Resolve challenge
await client.resolveChallenge(claimId, true); // true = challenge succeeded
```

### Trust routing

The SDK also includes the builder trust wrapper for EMETTrustGate, EMETScorecard, EMETAgentProfile, and EMETReputation.

```javascript
import { EMETTrust, Policy, formatScore } from '@emet/sdk';

const trust = new EMETTrust({
  rpcUrl: 'https://mainnet.base.org',
  addresses: {
    EMETReputation: '0x358a775b74f9369D23Ce95EDa57dcbA39A1F4d4e',
    EMETAgentProfile: process.env.EMET_AGENT_PROFILE,
    EMETTrustGate: process.env.EMET_TRUST_GATE,
    EMETScorecard: process.env.EMET_SCORECARD
  }
});

const score = await trust.peek(agentAddress);
console.log(formatScore(score));

const decision = await trust.check(agentAddress, Policy.STANDARD);
if (decision.passes) {
  // route work to the agent
}
```

For risk-to-policy patterns, batch routing, cold-start handling, and marketplace audit records, see [TRUST-COOKBOOK.md](./TRUST-COOKBOOK.md).

### Reputation

```javascript
// Get reputation
const rep = await client.getReputation(address);
```

### Utilities

```javascript
// Get network info
const network = await client.getNetworkInfo();
console.log(network.isBase); // true

// Get contract addresses
const addresses = client.getAddresses();
console.log(addresses.EMETToken);

// Wait for transaction
const receipt = await client.waitForTransaction(txHash);
```

## Contract Addresses (Base Mainnet)

| Contract | Address |
|----------|---------|
| EMETToken | `0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C` |
| EMETRegistry | `0x9D2550eB1Ee613E0f35c70524e1304B26392b0aC` |
| EMETStake | `0x63901ED9Fbd8262B4505819E2F39a6145f28Fbf0` |
| EMETChallenge | `0x5D47f36b0C768395CE49F2D7249DDe44086Fe37b` |

## Claim Statuses

| Status | Value | Description |
|--------|-------|-------------|
| Pending | 0 | Just submitted |
| Active | 1 | Open for staking/challenges |
| Verified | 2 | Verified as true |
| Rejected | 3 | Rejected as false |
| Disputed | 4 | Under challenge |
| Resolved | 5 | Challenge resolved |

## Development

```bash
# Run tests
npm test

# Run CLI in development
npm run cli -- status
node src/cli.js claim list
```

## License

MIT
