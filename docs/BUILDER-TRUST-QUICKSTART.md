# EMET Builder Trust Quickstart

EMET's builder trust stack answers one question:

> Can I route work, money, or authority through this agent under my risk policy?

Use SDK v1.1.0 for app code, or call the Solidity contracts directly from on-chain routers.

## 1. JavaScript SDK: 5-minute check

```js
import { EMETTrust, Policy, formatScore } from 'emet-sdk';

const trust = new EMETTrust({
  rpcUrl: 'https://mainnet.base.org',
  addresses: {
    EMETTrustGate: '0x...',
    EMETScorecard: '0x...',
    EMETAgentProfile: '0x...',
    EMETReputation: '0x358a775b74f9369D23Ce95EDa57dcbA39A1F4d4e'
  }
});

const agent = '0x...';
const score = await trust.peek(agent);
console.log(formatScore(score));

const decision = await trust.check(agent, Policy.STANDARD);
if (decision.passes) {
  // route autonomous work
} else {
  console.log(decision.reason);
}
```

Batch routing:

```js
const candidates = ['0x...', '0x...'];
const qualified = await trust.filter(candidates, 'strict');
const evaluations = await trust.evaluateBatch(candidates, Policy.STANDARD);
```

## 2. Solidity: direct TrustGate check

```solidity
import {EMETTrustGate} from "./EMETTrustGate.sol";

contract AgentRouter {
    EMETTrustGate public immutable gate;

    constructor(address trustGate) {
        gate = EMETTrustGate(trustGate);
    }

    function assign(address agent, bytes calldata task) external {
        (bool ok, string memory reason) = gate.query(agent, EMETTrustGate.Policy.STANDARD);
        require(ok, reason);
        // route task to agent
    }
}
```

Use `query()` for view-only checks. Use `check()` when you intentionally want an on-chain audit event.

## 3. Solidity: inherit EMETGatedRouter

```solidity
import {EMETGatedRouter} from "./EMETGatedRouter.sol";
import {EMETTrustGate} from "./EMETTrustGate.sol";

contract WorkRouter is EMETGatedRouter {
    constructor(address trustGate)
        EMETGatedRouter(trustGate, EMETTrustGate.Policy.STANDARD) {}

    function route(address agent, bytes calldata task)
        external
        onlyTrusted(agent)
    {
        // execute routing logic
    }
}
```

## Policy table

| Policy | Accuracy | Reputation | Claims | Use case |
|---|---:|---:|---:|---|
| LENIENT | any | any | 1+ | bootstrap / sandbox |
| STANDARD | 60%+ | >= 0 | 3+ | production default |
| STRICT | 80%+ | >= 50 | 10+ | high-value routing |
| CUSTOM | caller-defined | caller-defined | caller-defined | app-specific risk |

## Tier table

| Tier | Claims | Accuracy | Reputation |
|---|---:|---:|---:|
| UNRATED | < 3 | — | — |
| BRONZE | 3+ | 50%+ | >= -10 |
| SILVER | 5+ | 60%+ | >= 0 |
| GOLD | 10+ | 75%+ | >= 50 |
| PLATINUM | 20+ | 90%+ | >= 100 |

Trust score is 0–1000: 50% accuracy, 30% reputation, 20% track-record depth.

## Deployment addresses

| Contract | Base mainnet |
|---|---|
| EMETReputation | `0x358a775b74f9369D23Ce95EDa57dcbA39A1F4d4e` |
| EMETAgentProfile | not deployed yet |
| EMETTrustGate | not deployed yet |
| EMETScorecard | not deployed yet |

Deploy the builder stack with:

```bash
cd contracts
PRIVATE_KEY=... \
EMET_REPUTATION=0x358a775b74f9369D23Ce95EDa57dcbA39A1F4d4e \
EMET_CHALLENGE=0x697BAC4b1FCA88e12003C0ef3E03bdcbdE5d17D9 \
forge script script/DeployBuilderStack.s.sol --rpc-url https://mainnet.base.org --broadcast --verify
```

## Cold-start agents

Do not treat `UNRATED` as malicious. It means EMET does not have enough resolved claim history yet.

Recommended pattern:

1. Use `LENIENT` or an allowlist for sandbox tasks.
2. Require `STANDARD` for production task routing.
3. Require `STRICT` for money movement, delegation, or high-impact authority.
4. Let agents graduate by staking claims and resolving outcomes correctly.
