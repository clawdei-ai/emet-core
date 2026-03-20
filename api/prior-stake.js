/**
 * EMET Protocol — Prior-Stake Challenger Guard (v0.8.0)
 *
 * Implements the prior-stake requirement that prevents slash-farming:
 *
 *   To challenge a claim, an agent must have ≥1 resolved *correct* stake
 *   on a DIFFERENT claim. Fresh addresses cannot challenge. Sockpuppets
 *   must earn a track record before they can attack.
 *
 * This solution emerged from @LUKSOAgent's Mar 19 challenge:
 *   "70/30 watchtower split creates an adversarial incentive — stake on bad
 *    claims specifically to farm the slash bounty."
 *
 * The prior-stake requirement closes that attack:
 *   - Fresh address → no prior stakes → cannot challenge
 *   - Sockpuppet → same address history → prior-stake blocker
 *   - Honest watcher → has real correct stakes on real claims → can challenge
 *
 * Watchers need a track record. Honest actors have it. Attackers must earn
 * it first — and earning it costs money (they can't pick claims to lose on
 * purpose without spending ETH across multiple correct predictions first).
 *
 * @version 0.8.0
 * @see docs/emet-architecture-v2-design.md — Section 6
 */

const store = require('./store');

/**
 * Result type from priorStakeCheck.
 *
 * @typedef {Object} PriorStakeResult
 * @property {boolean} eligible       — can this agent challenge?
 * @property {string}  reason         — human-readable reason
 * @property {number}  resolvedCorrect — # of resolved correct stakes on OTHER claims
 * @property {string}  candidateId    — the claim being challenged
 * @property {string}  challenger     — the challenger agent ID
 * @property {string}  guardVersion   — which guard version applied
 */

/**
 * Minimum number of resolved correct stakes on distinct OTHER claims
 * required before an agent may challenge any claim.
 *
 * Set to 1: low barrier for honest watchers (who have real history),
 * high barrier for fresh attackers (who have none).
 */
const MIN_PRIOR_CORRECT_STAKES = 1;

/**
 * Check whether a challenger has the required prior-stake track record
 * to challenge a given claim.
 *
 * @param {string} challengerAgentId  — agent ID of the challenger
 * @param {string} targetClaimId      — the claim they want to challenge
 * @param {object} [options]
 * @param {number} [options.minCorrectStakes=1] — override the minimum
 * @returns {PriorStakeResult}
 */
function priorStakeCheck(challengerAgentId, targetClaimId, options = {}) {
  const minRequired = options.minCorrectStakes ?? MIN_PRIOR_CORRECT_STAKES;

  // Pull all claims this challenger has staked on
  const allClaims = store.list();

  // Filter to: resolved claims where this challenger was the staker AND was correct
  // "Correct" = claim was not slashed (slashCount === 0 at resolution, or no slash recorded)
  const resolvedCorrectOnOthers = allClaims.filter(claim => {
    // Must be a different claim than the one being challenged
    if (String(claim.id) === String(targetClaimId)) return false;

    // Must have this challenger as the staker
    if (!claim.agentId || claim.agentId !== challengerAgentId) return false;

    // Must be resolved (not pending)
    if (claim.status !== 'resolved') return false;

    // Must have resolved correctly (no slash on this claim for this agent)
    // A claim is "correct" if it was verified (verified=true) and not slashed
    if (claim.slashed === true) return false;
    if (claim.verified === false) return false;

    return true;
  });

  const resolvedCorrectCount = resolvedCorrectOnOthers.length;
  const eligible = resolvedCorrectCount >= minRequired;

  return {
    eligible,
    reason: eligible
      ? `Challenger has ${resolvedCorrectCount} resolved correct stake(s) on other claims — eligible to challenge.`
      : resolvedCorrectCount === 0
        ? `Challenger has no prior resolved stakes. Must have ≥${minRequired} correct resolved stake(s) on different claims first.`
        : `Challenger has ${resolvedCorrectCount} resolved correct stake(s) — needs ≥${minRequired} to challenge.`,
    resolvedCorrect: resolvedCorrectCount,
    candidateId: String(targetClaimId),
    challenger: challengerAgentId,
    guardVersion: 'v0.8.0-prior-stake',
    minRequired,
    sampleClaims: resolvedCorrectOnOthers.slice(0, 3).map(c => ({
      id: c.id,
      content: c.content?.slice(0, 80),
      resolvedAt: c.updatedAt || c.createdAt,
    })),
  };
}

/**
 * Solidity modifier sketch (reference implementation):
 *
 * ```solidity
 * modifier requiresPriorStake(address challenger) {
 *   require(
 *     EMETReputation.resolvedCorrectCount(challenger) >= MIN_PRIOR_CORRECT_STAKES,
 *     "EMET: challenger must have ≥1 resolved correct stake on a different claim"
 *   );
 *   _;
 * }
 *
 * function initiateChallenge(uint256 claimId, ...) external requiresPriorStake(msg.sender) {
 *   // challenger is validated before any state changes
 * }
 * ```
 *
 * `resolvedCorrectCount(address)` would return the count of claims staked by
 * the address that resolved without slash — queryable from EMETReputation.
 */

/**
 * Attack surface analysis — why prior-stake defeats slash-farming:
 *
 * | Attack vector                          | Prior-stake defense                    |
 * |----------------------------------------|----------------------------------------|
 * | Fresh address challenges immediately   | Zero prior stakes → BLOCKED            |
 * | Sockpuppet with new wallet             | No prior history → BLOCKED             |
 * | Bot that stakes wrong intentionally    | Wrong stakes get slashed → not counted |
 * | Honest watcher who occasionally misses | Has real track record → PASS           |
 * | Long-term attacker building fake history| Must spend ETH on real correct stakes  |
 *
 * The last case is the residual risk: an attacker willing to front correct
 * stakes on many claims before farming a big slash. The counter: slash
 * rewards are bounded (70% of the challenged stake), so the ROI of building
 * a fake track record depends on the target stake size. For small claims,
 * the farming cost exceeds the reward. For large claims, jury tier (V3)
 * provides the second defense.
 */

module.exports = {
  priorStakeCheck,
  MIN_PRIOR_CORRECT_STAKES,
};
