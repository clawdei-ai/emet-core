# EMET SDK v1.1.0 Unblock Note

*Written: 2026-04-27*

## Current Truth

The SDK v1.1.0 trust-module work should be treated as **blocked / not shipped** until it is rebuilt or recovered from another machine.

Continuity said there was a local Apr 4 commit `11e3515` with:

- `sdk/src/trust.js`
- `sdk/tests/trust.test.js`
- `contracts/script/DeployBuilderStack.s.sol`
- `BUILDER_QUICKSTART.md`
- 25 passing SDK trust tests

But on this working copy, that commit and those files are **not present**:

- `git show 11e3515` returns no commit.
- `git reflog --all` has no matching trust-module / quickstart entry.
- `sdk/src/` currently contains only `client.js`, `contracts.js`, `index.js`, and `cli.js`.
- `contracts/script/` has deploy scripts through `DeployPhase2.s.sol`, but no `DeployBuilderStack.s.sol`.
- `sdk/package.json` is still version `1.0.0`.

So the safe external statement is:

> EMET SDK v1.1.0 is specified, but not present in the current repo checkout. Do not announce it as shipped until the missing files are restored, tests pass, and the commit is pushed.

## What v1.1.0 Should Ship

SDK v1.1.0 should expose the builder trust stack shipped in contracts v0.14.0–v0.16.0:

- `EMETTrustGate` — pass/fail policy checks for `LENIENT`, `STANDARD`, `STRICT`, `CUSTOM`.
- `EMETGatedRouter` — Solidity-side routing primitive for trust-gated execution.
- `EMETScorecard` — one-call trust summary and tiered score for an agent.

The SDK surface should make the common builder question trivial:

> Can I route work, money, or authority through this agent under my risk policy?

## Minimum v1.1.0 API

Recommended export from `sdk/src/index.js`:

```js
export {
  EMETTrust,
  Policy,
  Tier,
  RiskAppetite,
  formatScore
} from './trust.js';
```

Recommended client usage:

```js
import { EMETTrust, Policy, Tier } from 'emet-sdk';

const trust = new EMETTrust({
  rpcUrl: 'https://mainnet.base.org',
  addresses: {
    trustGate: '0x...',
    scorecard: '0x...',
    agentProfile: '0x...',
    reputation: '0x...'
  }
});

const score = await trust.score(agentAddress);

if (await trust.check(agentAddress, Policy.STANDARD)) {
  // route autonomous work
}

const trustedAgents = await trust.filter(candidateAgents, Policy.STRICT);
```

## Required Files To Add / Restore

### 1. `sdk/src/trust.js`

Should include:

- `EMETTrust` class
- `score(agent)` — calls `EMETScorecard.score(agent)` and returns normalized JS object.
- `peek(agent)` — calls read-only / no event score path if using `peek` from Scorecard.
- `check(agent, policy)` — calls `EMETTrustGate.check(agent, policy)` or derives from scorecard precomputed booleans.
- `filter(agents, policy)` — returns only agents passing policy.
- `evaluateBatch(agents, policy)` — returns pass/fail objects for each agent.
- `tierOf(agent)` — returns `UNRATED | BRONZE | SILVER | GOLD | PLATINUM`.
- `trustScoreOf(agent)` — returns 0–1000 score.
- `getProfile(agent)` — returns profile / reputation / scorecard fields needed by builders.
- `formatScore(score)` helper for docs / CLI display.

### 2. `sdk/tests/trust.test.js`

Should cover:

- constructor defaults and custom addresses
- enum exports
- ABI presence for `EMETTrustGate` + `EMETScorecard`
- score normalization
- policy checks for lenient/standard/strict/custom
- filter / evaluateBatch behavior
- tier and trust-score helpers
- unavailable / unrated agent behavior

### 3. `contracts/script/DeployBuilderStack.s.sol`

Should deploy, in order:

1. `EMETAgentProfile`
2. `EMETTrustGate`
3. `EMETScorecard`

It should wire the existing reputation/challenge contracts correctly and print deployed addresses for SDK config.

### 4. `BUILDER_QUICKSTART.md` or `docs/BUILDER-TRUST-QUICKSTART.md`

Should include:

- 5-minute JS SDK example
- Solidity direct `EMETTrustGate` example
- Solidity `EMETGatedRouter` inheritance example
- policy table
- tier table
- deployment address table
- guidance for cold-start agents

## Contract Facts To Mirror In SDK

### Policy enum

From `EMETTrustGate.sol`:

```solidity
enum Policy { LENIENT, STANDARD, STRICT, CUSTOM }
```

Thresholds:

| Policy | Accuracy | Reputation | Claims | Use case |
|---|---:|---:|---:|---|
| LENIENT | any | any | 1+ | bootstrap / sandbox |
| STANDARD | 60%+ | >= 0 | 3+ | production default |
| STRICT | 80%+ | >= 50 | 10+ | high-value routing |
| CUSTOM | caller-defined | caller-defined | caller-defined | app-specific risk |

### Tier enum

From `EMETScorecard.sol`:

```solidity
enum Tier { UNRATED, BRONZE, SILVER, GOLD, PLATINUM }
```

Thresholds:

| Tier | Claims | Accuracy | Reputation |
|---|---:|---:|---:|
| UNRATED | < 3 | — | — |
| BRONZE | 3+ | 50%+ | >= -10 |
| SILVER | 5+ | 60%+ | >= 0 |
| GOLD | 10+ | 75%+ | >= 50 |
| PLATINUM | 20+ | 90%+ | >= 100 |

Trust score is 0–1000, weighted by:

- accuracy: 50%
- reputation: 30%
- track-record depth: 20%

## Unblock Checklist

1. Check whether another machine or backup has commit `11e3515`.
2. If found, cherry-pick or patch the missing files into this repo.
3. If not found, rebuild from this note and the current contract ABIs.
4. Add SDK exports and bump `sdk/package.json` from `1.0.0` to `1.1.0`.
5. Run:

```bash
cd /home/sergei/clawd/emet-core/sdk
npm test
```

6. Run contract tests if deploy script changes Solidity imports:

```bash
cd /home/sergei/clawd/emet-core/contracts
forge test
```

7. Commit with a clear message, for example:

```bash
git add sdk contracts/script docs README.md
git commit -m "feat(sdk): v1.1.0 trust module for builder gating"
```

8. Push only after GitHub auth is valid.

## External Message For Sergei / Builders

Use this exact phrasing until the repo is fixed:

> SDK v1.1.0 is the next unblock: a JS trust module around EMETTrustGate and EMETScorecard so builders can check, rank, and route agents by on-chain trust policy. The contracts are present; the SDK wrapper needs to be restored/rebuilt and pushed before we call it shipped.

## Priority

This is a better next engineering target than passive monitoring because it converts the v0.14–v0.16 contract stack into a builder-facing integration surface.

Do **not** let the stale continuity note turn into a false shipping claim. Either recover `11e3515`, or rebuild the trust module explicitly and ship a new verified commit.
