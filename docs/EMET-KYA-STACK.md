# EMET × KYA — Identity + Output Accountability

*Written: 2026-04-25*

## Why This Exists

KYA and EMET solve different parts of the same trust problem.

- **KYA** answers: who controls this agent, how old is its wallet history, and does its identity look stable?
- **EMET** answers: when this agent makes a claim or completes a task, is there stake, challengeability, and an auditable outcome?

If you only have KYA, you know the actor but not whether the actor's outputs deserve trust.
If you only have EMET, you can score behavior but you have a weaker answer to identity transfer, wallet rotation, and operator continuity.

The stack is stronger when identity and output accountability are composed instead of treated as substitutes.

## Division Of Labor

### KYA covers identity risk

- agent registration / discovery
- wallet tenure and ownership trail
- soulbound or non-transferable identity anchors
- reputation laundering detection via identity history
- "should I even let this agent into the system?"

### EMET covers outcome risk

- claim-level stake
- permissionless challenge flow
- jury / oracle resolution
- on-chain performance history
- policy-based gating for builders
- "should I trust this output enough to route money, work, or authority through it?"

## The Clean Mental Model

Use this framing with builders:

> KYA tells you whether the identity looks legitimate.
> EMET tells you whether the behavior has earned trust under consequence.

Or shorter:

> **KYA = who the agent is**
> **EMET = whether what it says survives challenge**

## What Breaks If You Only Use One Layer

### KYA without EMET

- You can verify that an agent identity is old, registered, and controlled by a real operator.
- You still do not have hard consequences for false claims, low-quality execution, or post-hoc disputes.
- You get identity assurance without economic accountability.

### EMET without KYA

- You can gate on track record, accuracy, slash history, and policy thresholds.
- You still need a separate answer for ownership continuity, operator lineage, and identity-transfer risk outside EMET's scope.
- You get behavioral accountability without a first-class identity layer.

## Builder Patterns

### 1. Admission Gate

Use KYA first, EMET second.

Flow:
1. Confirm the agent passes your identity policy in KYA.
2. Query EMET policy status with `EMETTrustGate`.
3. Reject if either layer fails.

Best for:
- marketplaces
- agent registries
- high-risk plugins
- API access control

### 2. Routing Gate

Use KYA as a hard prerequisite, then use EMET for ranking and selection.

Flow:
1. KYA filters out weak identities.
2. `EMETScorecard` ranks the remaining candidates.
3. `EMETGatedRouter` or your own router sends work only to trusted agents.

Best for:
- multi-agent crews
- agent marketplaces
- contractor selection
- autonomous task routing

### 3. Audit Trail

Use KYA to anchor who the agent was, and EMET to anchor what happened.

Flow:
1. Identity and ownership context come from KYA.
2. Claims, disputes, and final outcomes come from EMET.
3. Downstream auditors can reconstruct both identity continuity and behavioral history.

Best for:
- compliance-heavy systems
- financial workflows
- procurement
- agent governance

## Where EMET Fits Today

EMET already has the builder-side pieces for the output-accountability half:

- `EMETTrustGate.sol` for pass/fail policy checks
- `EMETGatedRouter.sol` for trust-gated routing
- `EMETScorecard.sol` for one-call trust summaries

Recommended composition:

- KYA for identity admission
- `EMETTrustGate` for minimum trust policy
- `EMETScorecard` for ranking
- `EMETGatedRouter` for enforcement inside Solidity routing flows

## Suggested Integration Rules

For a conservative first version:

1. Require a valid KYA identity before an agent can register or receive work.
2. Require EMET `STANDARD` policy before an agent can be assigned autonomous execution.
3. Use `STRICT` for high-value tasks, treasury access, or external actions.
4. Record disputes and resolved outcomes in EMET even if KYA remains unchanged.

That gives builders a simple split:

- **KYA controls admission**
- **EMET controls consequence**

## Positioning For Outreach

This is the most useful one-liner:

> KYA handles identity continuity. EMET handles output accountability. Agent finance and autonomous routing need both.

And the sharper version for compliance / risk infra:

> Identity without consequence gets spoofed. Consequence without identity gets detached. The trust stack needs both layers.

## Practical Next Step

The first concrete collaboration target is not "merge the protocols."

It is:

1. KYA identity check at the edge
2. EMET score / policy check before task routing
3. Joint example showing the full trust path from identity to consequence

That is a cleaner and more shippable story than trying to collapse both systems into one protocol.
