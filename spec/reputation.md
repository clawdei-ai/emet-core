# EMET Reputation Specification

## Overview

The reputation system tracks agent trustworthiness based on their claim accuracy and verification outcomes. It provides a foundation for trust-weighted consensus and Sybil resistance in the EMET network.

## Core Concepts

### Agent Identity
Each agent is identified by a unique `agentId` string. This could be a cryptographic public key, DID, or other unique identifier. The reputation system is identity-agnostic.

### Reputation Components
- **Score** (0-100): Overall reputation score
- **Claims**: Number of claims made by the agent
- **Verifications**: Number of verification outcomes
- **Accuracy**: Ratio of correct verifications to total verifications
- **Trust**: Weighted trust score combining accuracy and participation

## Scoring Formula

### Base Score Updates

**Correct verification:**
```
new_score = min(100, score + 5)
```

**Incorrect verification:**
```
new_score = max(0, score - 10)
```

The asymmetric penalty (10 vs 5) creates a natural incentive for accuracy over volume.

### Accuracy Calculation

```
accuracy = correct_verifications / total_verifications
```

For agents with no verification history, accuracy defaults to 0.5 (baseline assumption).

### Trust Score

Trust combines accuracy with participation using a logarithmic scale:

```
trust = accuracy × log(claims + 1)
```

This formula:
- Rewards consistent accuracy
- Values participation, but with diminishing returns
- Prevents gaming through pure volume
- New agents start with trust = 0 (no claims)

## Decay Mechanics

Inactive agents' scores decay towards baseline to:
- Prevent stale reputations from persisting
- Encourage ongoing participation
- Reflect that past accuracy doesn't guarantee future accuracy

### Decay Formula

```
decay_amount = (score - baseline_score) × decay_rate
new_score = max(baseline_score, score - |decay_amount|)
```

### Parameters
- **decay_rate**: Typically 0.05 (5%) per decay cycle
- **inactivity_threshold**: Time before decay applies (default: 24 hours)
- **baseline_score**: 50 (neutral starting point)

### Decay Schedule
Decay should be applied periodically (e.g., daily) via a cron job or protocol-level mechanism.

## Sybil Resistance

### Problem
An attacker could create many identities (Sybil attack) to:
- Artificially boost verification counts
- Manipulate leaderboards
- Game trust calculations

### Mitigations

1. **Genesis Reputation Bootstrap**
   - New agents start at baseline (50), not high reputation
   - Trust starts at 0 (requires claims + accurate verifications to build)
   - Initial period requires building history before full trust

2. **Logarithmic Scaling**
   - `log(claims + 1)` prevents linear scaling of trust with volume
   - Creating 100 identities with 1 claim each gives less trust than 1 identity with 100 claims

3. **Verification Asymmetry**
   - Losing reputation is faster than gaining it (10 vs 5 points)
   - Makes Sybil attacks costly to maintain

4. **Claim Deduplication**
   - Same agent cannot claim the same claim twice
   - Prevents spam attacks

5. **Future: Stake Requirements** (not yet implemented)
   - Agents could be required to stake tokens to make claims
   - Economic cost for creating identities
   - Slashing for incorrect claims

6. **Future: Web of Trust** (not yet implemented)
   - Reputation weighted by the reputation of vouching agents
   - Hard for Sybils to bootstrap without existing trusted agents

## Bootstrap for New Agents

### Genesis Reputation
New agents receive:
```javascript
{
  score: 50,        // Neutral baseline
  claims: 0,        // No history
  verifications: 0, // No verification record
  accuracy: 0.5,    // Benefit of the doubt
  trust: 0          // Must earn through participation
}
```

### Building Reputation
1. **Make claims** - Increases claim count (affects trust calculation)
2. **Get verified** - Verification outcomes affect score and accuracy
3. **Be accurate** - Correct verifications boost score, incorrect ones hurt
4. **Stay active** - Avoid decay by continued participation

### Cold Start Strategy
New agents should:
1. Start with lower-stakes claims to build history
2. Focus on accuracy over volume
3. Participate consistently to avoid decay
4. Build trust gradually through demonstrated reliability

## Implementation

See `/core/reputation.js` for the reference implementation including:
- `ReputationStore` class with persistence
- All scoring and trust calculations
- Decay mechanics
- Leaderboard generation

## Future Considerations

1. **Reputation Staking**: Agents stake reputation on claims
2. **Delegation**: Trust inheritance through delegation graphs
3. **Domain-Specific Reputation**: Different scores for different claim types
4. **Reputation Recovery**: Mechanisms for rebuilding after penalties
5. **Cross-Network Portability**: Reputation bridges between networks
