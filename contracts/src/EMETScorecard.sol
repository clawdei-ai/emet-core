// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {EMETAgentProfile} from "./EMETAgentProfile.sol";
import {EMETReputation} from "./EMETReputation.sol";
import {EMETTrustGate} from "./EMETTrustGate.sol";

/// @title EMETScorecard — Single-call agent trust summary for builder integrations
/// @notice Aggregates all EMET trust dimensions into one composable read.
///         The canonical "what do I know about this agent?" entry point for external builders.
///
/// @dev Before EMETScorecard, builders needed to:
///   1. Call EMETAgentProfile.profiles(agent) → accuracy, risk, stake history
///   2. Call EMETReputation.reputationOf(agent) → reputation score
///   3. Call EMETTrustGate.evaluate(agent, Policy.STANDARD) → gate result
///   4. Combine all three into a decision
///
///   Now they call: EMETScorecard.score(agent)
///
/// Returned struct fields:
///   - passesLenient/Standard/Strict: pre-computed policy results (no extra calls)
///   - accuracyBps: % correct claims (0–10000)
///   - reputation: signed rep score (negative = penalized)
///   - totalClaims: total resolved claims
///   - correctClaims: claims that resolved correctly
///   - slashCount: times the agent was slashed (wrong)
///   - avgStakeWei: avg stake size (risk proxy)
///   - riskAppetite: Low/Medium/High/Unknown enum
///   - tier: computed tier: UNRATED / BRONZE / SILVER / GOLD / PLATINUM
///   - trustScore: composite 0–1000 score for easy comparison
///
/// Tier thresholds:
///   UNRATED:  < 3 claims
///   BRONZE:   3+ claims, >= 50% accuracy, rep >= -10
///   SILVER:   5+ claims, >= 60% accuracy, rep >= 0
///   GOLD:     10+ claims, >= 75% accuracy, rep >= 50
///   PLATINUM: 20+ claims, >= 90% accuracy, rep >= 100
///
/// Trust score (0–1000):
///   Weighted: accuracy (50%) + reputation (30%) + track record depth (20%)
///   Capped at 1000. Zero for UNRATED agents.
///
/// @custom:version 0.16.0
/// @custom:design-source docs/emet-architecture-v2-design.md
contract EMETScorecard {

    // ============ Types ============

    /// @notice Agent tier based on combined performance signals
    enum Tier { UNRATED, BRONZE, SILVER, GOLD, PLATINUM }

    /// @notice Complete agent trust summary
    struct Score {
        // Gate results (pre-computed for common use cases)
        bool passesLenient;
        bool passesStandard;
        bool passesStrict;

        // Accuracy & profile
        uint256 accuracyBps;          // 0–10000
        uint256 totalClaims;
        uint256 correctClaims;
        uint256 slashCount;
        uint256 avgStakeWei;
        EMETAgentProfile.RiskAppetite riskAppetite;

        // Reputation
        int256  reputation;

        // Composite
        Tier    tier;
        uint256 trustScore;           // 0–1000
    }

    // ============ Tier constants ============

    uint256 public constant BRONZE_MIN_CLAIMS      = 3;
    uint256 public constant BRONZE_MIN_ACCURACY    = 5_000; // 50%
    int256  public constant BRONZE_MIN_REP         = -10;

    uint256 public constant SILVER_MIN_CLAIMS      = 5;
    uint256 public constant SILVER_MIN_ACCURACY    = 6_000; // 60%
    int256  public constant SILVER_MIN_REP         = 0;

    uint256 public constant GOLD_MIN_CLAIMS        = 10;
    uint256 public constant GOLD_MIN_ACCURACY      = 7_500; // 75%
    int256  public constant GOLD_MIN_REP           = 50;

    uint256 public constant PLATINUM_MIN_CLAIMS    = 20;
    uint256 public constant PLATINUM_MIN_ACCURACY  = 9_000; // 90%
    int256  public constant PLATINUM_MIN_REP       = 100;

    // ============ Trust score weights (out of 100) ============

    uint256 public constant WEIGHT_ACCURACY    = 50;
    uint256 public constant WEIGHT_REPUTATION  = 30;
    uint256 public constant WEIGHT_DEPTH       = 20;

    /// @notice Reputation score that maps to 100% of the reputation weight
    int256 public constant REP_MAX_SCORE       = 200;

    /// @notice Depth (claim count) that maps to 100% of depth weight
    uint256 public constant DEPTH_SATURATE_AT = 50;

    // ============ Immutables ============

    /// @notice EMETAgentProfile instance (accuracy + risk appetite)
    EMETAgentProfile public immutable agentProfile;

    /// @notice EMETReputation instance (reputation score)
    EMETReputation public immutable reputation;

    /// @notice EMETTrustGate instance (policy checks)
    EMETTrustGate public immutable trustGate;

    // ============ Events ============

    /// @notice Emitted whenever score() is called (on-chain audit trail)
    event ScorecardQueried(address indexed querier, address indexed agent, Tier tier, uint256 trustScore);

    // ============ Constructor ============

    constructor(
        address _agentProfile,
        address _reputation,
        address _trustGate
    ) {
        require(_agentProfile != address(0), "EMETScorecard: zero agentProfile");
        require(_reputation   != address(0), "EMETScorecard: zero reputation");
        require(_trustGate    != address(0), "EMETScorecard: zero trustGate");

        agentProfile = EMETAgentProfile(_agentProfile);
        reputation   = EMETReputation(_reputation);
        trustGate    = EMETTrustGate(_trustGate);
    }

    // ============ Primary query ============

    /// @notice Returns a complete trust summary for `agent`.
    /// @dev Emits ScorecardQueried for on-chain audit trail.
    /// @param agent The agent address to score.
    /// @return s Full Score struct.
    function score(address agent) external returns (Score memory s) {
        s = _buildScore(agent);
        emit ScorecardQueried(msg.sender, agent, s.tier, s.trustScore);
    }

    /// @notice Read-only version of score() — does NOT emit an event.
    ///         Use for pure on-chain logic / view calls from other contracts.
    /// @param agent The agent address to score.
    /// @return s Full Score struct.
    function peek(address agent) external view returns (Score memory s) {
        return _buildScore(agent);
    }

    /// @notice Returns the tier of an agent without emitting an event.
    /// @param agent The agent address.
    /// @return Tier enum value.
    function tierOf(address agent) external view returns (Tier) {
        return _buildScore(agent).tier;
    }

    /// @notice Returns the composite trust score (0–1000) without emitting an event.
    /// @param agent The agent address.
    /// @return uint256 0–1000.
    function trustScoreOf(address agent) external view returns (uint256) {
        return _buildScore(agent).trustScore;
    }

    /// @notice Returns true if agent passes the given TrustGate policy.
    ///         Thin convenience wrapper — same as calling TrustGate.query() directly,
    ///         but accessible from a single EMETScorecard address.
    ///         Uses the view-only path (no event emitted, gas-free).
    /// @param agent  The agent address.
    /// @param policy Policy to check.
    /// @return passes True if agent passes.
    /// @return reason Human-readable explanation.
    function check(address agent, EMETTrustGate.Policy policy)
        external view
        returns (bool passes, string memory reason)
    {
        return trustGate.query(agent, policy);
    }

    // ============ Internal helpers ============

    function _buildScore(address agent) internal view returns (Score memory s) {
        // --- 1. Agent profile (accuracy + risk) ---
        EMETAgentProfile.Profile memory p = agentProfile.getProfile(agent);
        s.accuracyBps   = p.accuracyBps;
        s.totalClaims   = p.totalClaims;
        s.correctClaims = p.correctClaims;
        s.slashCount    = p.slashCount;
        s.avgStakeWei   = p.avgStakeWei;
        s.riskAppetite  = p.riskAppetite;

        // --- 2. Reputation ---
        s.reputation = reputation.reputation(agent);

        // --- 3. TrustGate policy checks (view path — no events) ---
        (s.passesLenient,  ) = trustGate.query(agent, EMETTrustGate.Policy.LENIENT);
        (s.passesStandard, ) = trustGate.query(agent, EMETTrustGate.Policy.STANDARD);
        (s.passesStrict,   ) = trustGate.query(agent, EMETTrustGate.Policy.STRICT);

        // --- 4. Tier ---
        s.tier = _computeTier(s.totalClaims, s.accuracyBps, s.reputation);

        // --- 5. Composite trust score (0–1000) ---
        s.trustScore = _computeTrustScore(s.totalClaims, s.accuracyBps, s.reputation, s.tier);
    }

    /// @dev Computes tier from the three primary signals.
    function _computeTier(
        uint256 totalClaims,
        uint256 accuracyBps,
        int256  rep
    ) internal pure returns (Tier) {
        if (totalClaims >= PLATINUM_MIN_CLAIMS &&
            accuracyBps >= PLATINUM_MIN_ACCURACY &&
            rep         >= PLATINUM_MIN_REP) {
            return Tier.PLATINUM;
        }
        if (totalClaims >= GOLD_MIN_CLAIMS &&
            accuracyBps >= GOLD_MIN_ACCURACY &&
            rep         >= GOLD_MIN_REP) {
            return Tier.GOLD;
        }
        if (totalClaims >= SILVER_MIN_CLAIMS &&
            accuracyBps >= SILVER_MIN_ACCURACY &&
            rep         >= SILVER_MIN_REP) {
            return Tier.SILVER;
        }
        if (totalClaims >= BRONZE_MIN_CLAIMS &&
            accuracyBps >= BRONZE_MIN_ACCURACY &&
            rep         >= BRONZE_MIN_REP) {
            return Tier.BRONZE;
        }
        return Tier.UNRATED;
    }

    /// @dev Composite trust score 0–1000.
    ///      UNRATED agents always score 0.
    ///      Formula: accuracy(50%) + reputation(30%) + depth(20%)
    function _computeTrustScore(
        uint256 totalClaims,
        uint256 accuracyBps,
        int256  rep,
        Tier    tier
    ) internal pure returns (uint256) {
        if (tier == Tier.UNRATED) return 0;

        // Accuracy component: 0–10000 bps → 0–500 (scaled to weight 50 of 100 * 10)
        uint256 accuracyComponent = (accuracyBps * WEIGHT_ACCURACY) / 10_000; // 0–50

        // Reputation component: rep clamped to [0, REP_MAX_SCORE] → 0–30
        uint256 repClamped;
        if (rep <= 0) {
            repClamped = 0;
        } else if (rep >= REP_MAX_SCORE) {
            repClamped = uint256(REP_MAX_SCORE);
        } else {
            repClamped = uint256(rep);
        }
        uint256 repComponent = (repClamped * WEIGHT_REPUTATION) / uint256(REP_MAX_SCORE); // 0–30

        // Depth component: claims saturate at DEPTH_SATURATE_AT → 0–20
        uint256 depthClamped = totalClaims >= DEPTH_SATURATE_AT
            ? DEPTH_SATURATE_AT
            : totalClaims;
        uint256 depthComponent = (depthClamped * WEIGHT_DEPTH) / DEPTH_SATURATE_AT; // 0–20

        // Sum is 0–100, scale to 0–1000
        uint256 raw = (accuracyComponent + repComponent + depthComponent) * 10;
        return raw > 1_000 ? 1_000 : raw;
    }
}
