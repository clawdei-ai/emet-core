# One-Shot Setter Analysis - EMET Protocol

## Date: 2026-02-01

## Executive Summary

**The current governance system is fundamentally broken due to incorrect wiring during deployment.**

ChallengeV3 v2 has an immutable reference to JuryPool v1 (the OLD one), but JuryPool v1 only authorizes ChallengeV3 v1. This means jury selection will fail for any challenge, making the entire dispute resolution system non-functional.

## Current State

### Contract Addresses

| Contract | Version | Address |
|----------|---------|---------|
| Token | - | 0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C |
| Registry | v2 | 0x266D8343463deE2920CBE97EfB72B4540E491DeC |
| Registry | v1 (legacy) | 0x69FC0F525F15DFB57e762cD2c570114433AFc6e2 |
| JuryPool | v2 | 0x018377D4e725703974A0087f8Ca8066c4aE8b045 |
| JuryPool | v1 (legacy) | 0xDBa7434180e09c9b0857d5808a227E32E1c79bD8 |
| ChallengeV3 | v2 | 0x697BAC4b1FCA88e12003C0ef3E03bdcbdE5d17D9 |
| ChallengeV3 | v1 (legacy) | 0xfFd54b3B1D72BE8205D961566e1AD4134FBd5332 |
| Treasury | - | 0xe1230E68818CCE66275Ad95E1bC79517Ac1ae502 |
| Reputation | - | 0x358a775b74f9369D23Ce95EDa57dcbA39A1F4d4e |

### Current Wiring (On-Chain Verified)

```
Registry v2:
  └── challengeContract: ChallengeV3 v2 ✅

JuryPool v2:
  └── challengeContract: ChallengeV3 v2 ✅
  
ChallengeV3 v2:
  ├── registry: Registry v2 ✅
  ├── treasury: Treasury ✅
  ├── reputation: Reputation ✅
  └── juryPool: JuryPool v1 ❌ WRONG!

JuryPool v1 (legacy):
  └── challengeContract: ChallengeV3 v1 ❌
```

### The Problem

When `ChallengeV3.initiateChallenge()` is called:
1. ✅ Calls `registry.markChallenged()` - works (Registry v2 authorizes ChallengeV3 v2)
2. ❌ Calls `juryPool.selectJury()` - FAILS!
   - ChallengeV3 v2 calls JuryPool v1 (immutable reference)
   - JuryPool v1's `challengeContract` is set to ChallengeV3 v1
   - JuryPool v1 rejects the call with `OnlyChallengeContract()` error

**Result: The dispute resolution system is completely non-functional.**

## One-Shot Setter Status

| Contract | Setter | Current Value | Can Change? |
|----------|--------|---------------|-------------|
| Registry v2 | `setChallengeContract` | ChallengeV3 v2 | ❌ ONE-SHOT, LOCKED |
| JuryPool v2 | `setChallengeContract` | ChallengeV3 v2 | ❌ ONE-SHOT, LOCKED |
| JuryPool v1 | `setChallengeContract` | ChallengeV3 v1 | ❌ ONE-SHOT, LOCKED |
| ChallengeV3 v2 | N/A (immutable) | JuryPool v1 | ❌ IMMUTABLE |

## Why Fresh ChallengeV3 v3 Won't Help

Even if we deploy ChallengeV3 v3 with the correct JuryPool v2 reference:

1. **Registry v2** cannot be rewired to ChallengeV3 v3 (one-shot setter already used)
2. **JuryPool v2** cannot be rewired to ChallengeV3 v3 (one-shot setter already used)

The new ChallengeV3 v3 would have no authorization from either contract.

## Required Fix: Deploy Fresh Governance Stack

### New Contracts Needed

1. **Registry v3** - Fresh registry with one-shot setter available
2. **JuryPool v3** - Fresh jury pool with one-shot setter available  
3. **ChallengeV3 v3** - With correct constructor args pointing to JuryPool v3

### Deployment Order

```
1. Deploy Registry v3 (minimumStake, challengePeriod)
2. Deploy JuryPool v3 (reputationContract)
3. Deploy ChallengeV3 v3 (Registry v3, Treasury, Reputation, JuryPool v3)
4. Call Registry v3.setChallengeContract(ChallengeV3 v3)
5. Call JuryPool v3.setChallengeContract(ChallengeV3 v3)
6. Update frontend addresses
```

### Contracts That Stay The Same

- Token (0x013c5C58...) - No changes needed
- Treasury (0xe1230E68...) - No changes needed
- Reputation (0x358a775b...) - No changes needed

### Impact

- Existing claims in Registry v2 remain (can be resolved manually if challenged)
- New claims will use Registry v3
- Frontend must update addresses

## Recommendation

**Deploy the fresh governance stack (Registry v3 + JuryPool v3 + ChallengeV3 v3) and wire correctly from the start.**

This is the only way to achieve a functional dispute resolution system. The current v2 deployment is fundamentally broken and cannot be fixed without new deployments.

## Lessons Learned

1. **Always verify wiring before marking deployment complete**
2. **Consider adding updateable setters with governance controls instead of one-shot setters**
3. **Create automated deployment scripts that verify the complete wiring graph**
