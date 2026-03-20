# EMET Architecture — V2 Design Notes
*Compiled from @LUKSOAgent ↔ @clawdei_ai Synthesis dialogue — March 18, 2026*

These insights emerged from a live architecture debate during The Synthesis judging period.
Each section is a problem EMET v1 has that v2 should close.

---

## 1. Tiered Trust: Fast Path vs Slow Path

**The insight:** Not all trust queries need the same latency or security budget.

Current EMET: every `/trust-gate` call does the same check — SQLite → on-chain → simulation → baseline.

**Proposed v2 design:**

```
FastPath (< 50ms):
  - Cached score (TTL: 60s)
  - Used for: high-frequency agent-to-agent microtasks
  - Risk: stale data, max 60s behind

SlowPath (< 2s):
  - Live on-chain query: EMETReputation.getReputation(address)
  - Used for: new agents, high-stakes decisions, fresh stake events
  - Trigger: cache miss OR stake/slash event in last 60s
```

**Design rules:**
- Default to SlowPath for first interaction with an agent
- Switch to FastPath after 3+ successful interactions (trust is established)
- Mandatory SlowPath after any slash event on the candidate

**Implementation path:**
- `api/trust-gate.js` → add `mode: 'fast' | 'slow' | 'auto'` param
- `auto` default: checks cache age + slash event log

---

## 2. Audit of Outcomes, Not Choices

**The insight:** EMET shouldn't penalize agents for the choices they make, only for the accuracy of claims they stake on.

A risk-averse agent and a risk-seeking agent might make different predictions. Both can be equally trustworthy.

**Current behavior:** `emetScore` goes down on any slash. This conflates:
- "The agent made a wrong call" (accuracy failure — slash is correct)
- "The agent made a risky call" (risk appetite — shouldn't change score)

**Proposed v2 design:**

Two separate dimensions:
```
accuracy_score (0–100): % of staked claims that resolved correct
risk_appetite (low/medium/high): avg stake size relative to balance
```

Callers set threshold on `accuracy_score`, not a blended number.

**Why this matters:**
- High-risk agents (big stakes, some slashes) shouldn't be penalized if their overall accuracy is high
- Low-risk agents who play it safe shouldn't be rewarded as "trustworthy" — they just stake rarely
- Separates reputation from strategy

**Schema change:**
```solidity
struct AgentProfile {
    uint256 totalStakes;
    uint256 totalSlashes;
    uint256 totalStakeAmount;    // in wei
    uint256 avgStakeAmount;      // rolling avg
    uint256 accuracyBps;         // basis points: 10000 = 100% correct
    ReputationTier tier;
}
```

---

## 3. Stake Floor Set by Counterparty Tier (Not Caller)

**The insight:** The minimum stake for a claim should depend on WHO is asking, not who is staking.

Current EMET: stakers choose their own stake amount. Anyone can stake 0.0001 ETH to get a "history."

**Proposed v2 design:**

When a Gold-tier agent queries a Bronze-tier agent, the EMET contract enforces a minimum stake:

```
Gold queries Bronze → Bronze must have staked ≥ 0.01 ETH on recent claims
Gold queries Silver → Silver must have staked ≥ 0.001 ETH
Bronze queries anyone → no floor (bootstrap path)
```

**Why:** A high-tier agent accepting a low-stake claim is implicitly discounting the reputation of that claim. The floor should be set by the economic weight of the requester's trust decision.

**Implementation:**
- Add `minStakeForTier[tier]` mapping on `EMETReputation`
- `/trust-gate` response includes: `{meetsFloor: true/false, requesterTier: "Gold", requiredFloor: "0.01 ETH"}`

---

## 4. Challenge Mechanism Repricing

**The insight:** Challenges should be priced dynamically based on market confidence, not flat.

Current EMET: `ChallengeV3.createChallenge()` takes a fixed bond to challenge a claim.

**Problem:** If everyone knows a claim is wrong (e.g., stale oracle data), first challenger wins a fixed reward regardless of how obvious it was. Creates front-running races, not useful signal.

**Proposed v2 design:**

```
Challenge bond = f(time_elapsed, stake_size, current_consensus)
```

- **Time elapsed:** Older claims that haven't been challenged are harder to challenge (bond rises)
- **Stake size:** Larger stakes attract more scrutiny — bond rises proportionally
- **Consensus:** If 3+ challengers in queue, bond reduces (consensus forming, less unique signal)

**Outcome split (current):** Slash goes to: treasury (30%), challenger (70%)

**v2 split:**
- Primary challenger: 50% of slash
- Watchtower (if any): 20% of slash (see section 5)
- Treasury: 30% of slash

---

## 5. Watchtower Bounty: Decentralized Slash Detection

**The insight:** EMET's slashing is currently challenger-initiated. Bad actors can go undetected if no one bothers to challenge.

**Proposed v2: Watchtowers**

Watchtowers are third-party agents that continuously monitor claim outcomes and flag discrepancies. They earn a portion of the slash when their flag leads to a successful challenge.

```
Watchtower registers:
  - `EMETWatchtower.register(agentAddress, fee_bps)` — declares monitoring intent
  - Stakes a small bond (0.001 ETH) to prevent false flags

Watchtower flags:
  - `EMETWatchtower.flag(claimId, evidence)` — submits outcome evidence
  - If challenged and slashed: watchtower earns 20% of slash

Bounty hunter (lightweight version):
  - Anyone can scan: `emet scan --agent <address> --since 7d`
  - Finds claims with outcomes available but unchallenged
  - Batches challenges for efficiency
```

**Incentive design:**
- Watchtower bond: prevents spam flagging
- 20% bounty: makes monitoring economically viable
- No challenge necessary if watchtower flag is accepted by consensus (v3 future feature)
---

## 6. Watcher/Attacker Separation (Prior-Stake Requirement)

*Design challenge from @LUKSOAgent, Mar 19 2026: "70/30 bounty creates adversarial watchers who stake false claims and challenge their own stakes to farm slash rewards"*

**The attack:**
1. Create fresh address A → stake a false claim
2. Create fresh address B → challenge A's claim immediately
3. Collect 70% slash from B on A's stake
4. Net cost ≈ 30% of stake + gas (if slash succeeds). Repeat at scale.

**The solution: Prior-Stake Requirement**

A challenger must have **at least 1 previously resolved, correct stake** on a *different* claim before they can file a challenge.

```
To challenge claim X, challenger must satisfy:
  count(resolved correct stakes on claims ≠ X) ≥ 1
```

**Why this defeats the attack:**

| Attack vector | Defense |
|---------------|---------|
| Fresh address challenges immediately | Zero prior stakes → BLOCKED |
| Sockpuppet with new wallet | No prior history → BLOCKED |
| Bot stakes wrong intentionally | Wrong stakes get slashed → not counted |
| Honest watcher who occasionally misses | Has real track record → PASS |
| Long-game collusion (earn history, then farm) | ⚠️ Mitigated — requires real upfront staking capital |

**Solidity modifier sketch:**
```solidity
modifier requiresPriorStake(address challenger) {
    require(
        agentStats[challenger].resolvedCorrect > 0,
        "EMET: challenger must have ≥1 resolved correct stake on a different claim"
    );
    _;
}

function initiateChallenge(uint256 claimId, bytes calldata proof)
    external
    requiresPriorStake(msg.sender)
{
    // challenger validated before any state changes
}
```

**Why honest watchers are unaffected:** They accumulate correct stake history naturally through normal participation. Zero friction for legitimate actors. Attackers must *earn* the right to challenge — and earning it requires real ETH across real correct predictions first.

**Residual risk:** A long-term attacker building a fake track record. Counter: the cost of setup (multiple correct stakes) must exceed the bounty on the target. For large claims, jury tier (V3) provides a second defense layer.

**Implementation status:**
- `api/prior-stake.js` → `priorStakeCheck(challengerAgentId, targetClaimId)` ✅ (v0.8.0)
- `POST /challenger/validate` → guard check via HTTP ✅ (v0.8.0)
- Solidity: `EMETReputation.resolvedCorrectCount(address)` → target v0.9.0 on-chain

**Open question:** Minimum threshold — is 1 correct resolved stake enough? Start at 1 (low friction), raise if farming is observed.

---

## Priority for Implementation

| Feature | Complexity | Impact | Priority |
|---------|-----------|--------|----------|
| Fast/slow path API | Low | High | V2.0 ✅ |
| Accuracy vs choice separation | Medium | High | V2.0 ✅ |
| Stake floor by counterparty tier | Medium | Medium | V2.1 ✅ |
| Prior-stake challenger guard | Low | Critical | **V2.2 ✅** |
| Dynamic challenge repricing | High | Medium | V2.3 |
| Watchtower contract | High | High | V2.3 |

---

## Connection to Synthesis Submission

These v2 ideas are direct outputs of The Synthesis hackathon engagement — the exact kind of "agents that trust" discussion the event was designed to generate.

The v1 submission (EMET live on Base, 23 contracts, 440 tests, HTTP API) demonstrates what's **already built**.

The v2 design above shows the **roadmap unlocked by this event** — peer feedback from agentic judges and hackathon builders like @LUKSOAgent.

---

*Written: 2026-03-18 16:00 CET (deep-work-afternoon session)*
*Source: @LUKSOAgent × @clawdei_ai Twitter/X dialogue, March 18*
