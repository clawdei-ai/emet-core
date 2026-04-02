// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {EMETAgentProfile} from "./EMETAgentProfile.sol";
import {EMETReputation} from "./EMETReputation.sol";

/// @title EMETTrustGate — Composable on-chain trust gate for agent routing and access control
/// @notice The on-chain equivalent of the EMET API /trust-gate endpoint.
///         External agent infrastructure contracts (routing, crew formation, task assignment)
///         can call this contract directly to gate agent selection on verifiable track records.
///
/// @dev This is the primary integration surface for external builders. Instead of
///      an off-chain API call that introduces trust in the API operator, callers
///      query on-chain data directly. Results are fully composable — use them in
///      require() statements, emit events, or feed into scoring logic.
///
/// Usage pattern:
///   ```solidity
///   EMETTrustGate gate = EMETTrustGate(0x...);
///   (bool passes, string memory reason) = gate.check(agentAddress, Policy.STANDARD);
///   require(passes, reason);
///   ```
///
/// Policies (strictness presets):
///   LENIENT  — bootstrap path: any agent with at least 1 claim passes
///   STANDARD — production default: 60% accuracy, rep >= 0, 3+ claims
///   STRICT   — high-stakes path: 80% accuracy, rep >= 50, 10+ claims
///   CUSTOM   — caller provides their own thresholds
///
/// @custom:version 0.14.0
/// @custom:design-source docs/emet-architecture-v2-design.md
contract EMETTrustGate {

    // ============ Types ============

    /// @notice Strictness presets matching the API TRUST_THRESHOLDS
    enum Policy { LENIENT, STANDARD, STRICT, CUSTOM }

    /// @notice Parameters for CUSTOM policy
    struct CustomPolicy {
        uint256 minAccuracyBps;   // Minimum accuracy in basis points (10000 = 100%)
        int256  minReputation;    // Minimum reputation score (can be negative)
        uint256 minClaims;        // Minimum number of resolved claims
    }

    /// @notice Full trust evaluation result
    struct TrustResult {
        bool    passes;           // Does the agent pass the policy?
        uint256 accuracyBps;      // Agent accuracy (basis points)
        int256  reputation;       // Agent reputation score
        uint256 totalClaims;      // Total resolved claims
        string  reason;           // Human-readable pass/fail reason
    }

    // ============ Policy constants (mirroring API TRUST_THRESHOLDS) ============

    uint256 public constant LENIENT_MIN_ACCURACY_BPS  = 0;
    int256  public constant LENIENT_MIN_REPUTATION    = type(int256).min; // any
    uint256 public constant LENIENT_MIN_CLAIMS        = 1;

    uint256 public constant STANDARD_MIN_ACCURACY_BPS = 6_000; // 60%
    int256  public constant STANDARD_MIN_REPUTATION   = 0;
    uint256 public constant STANDARD_MIN_CLAIMS       = 3;

    uint256 public constant STRICT_MIN_ACCURACY_BPS   = 8_000; // 80%
    int256  public constant STRICT_MIN_REPUTATION     = 50;
    uint256 public constant STRICT_MIN_CLAIMS         = 10;

    // ============ Immutables ============

    /// @notice EMETAgentProfile — accuracy + risk appetite tracking
    EMETAgentProfile public immutable agentProfile;

    /// @notice EMETReputation — reputation score tracking
    EMETReputation public immutable reputation;

    // ============ Events ============

    /// @notice Emitted when an agent is checked against a preset policy
    /// @param caller       The contract that called this gate
    /// @param agent        The agent being evaluated
    /// @param policy       Which preset policy was applied
    /// @param passes       Whether the agent passed
    /// @param accuracyBps  Agent accuracy at time of check
    /// @param reputation   Agent reputation at time of check
    event TrustChecked(
        address indexed caller,
        address indexed agent,
        Policy indexed policy,
        bool passes,
        uint256 accuracyBps,
        int256 reputation
    );

    /// @notice Emitted when an agent is checked against a custom policy
    /// @param caller           The contract that called this gate
    /// @param agent            The agent being evaluated
    /// @param passes           Whether the agent passed
    /// @param minAccuracyBps   Custom accuracy threshold applied
    /// @param minReputation    Custom reputation threshold applied
    event CustomTrustChecked(
        address indexed caller,
        address indexed agent,
        bool passes,
        uint256 minAccuracyBps,
        int256 minReputation
    );

    // ============ Errors ============

    error ZeroAddress();
    error InvalidCustomPolicy(); // All thresholds must be reachable (minClaims > 0)

    // ============ Constructor ============

    /// @param _agentProfile  Address of deployed EMETAgentProfile contract
    /// @param _reputation    Address of deployed EMETReputation contract
    constructor(address _agentProfile, address _reputation) {
        if (_agentProfile == address(0) || _reputation == address(0)) revert ZeroAddress();
        agentProfile = EMETAgentProfile(_agentProfile);
        reputation   = EMETReputation(_reputation);
    }

    // ============ Primary Interface ============

    /// @notice Check whether an agent passes a preset trust policy
    /// @param agent   The agent address to evaluate
    /// @param policy  Which preset (LENIENT / STANDARD / STRICT)
    /// @return passes true if agent meets all thresholds
    /// @return reason Human-readable explanation
    /// @dev   For CUSTOM policy, use checkCustom() instead.
    ///        Emits TrustChecked. Safe to call from any contract (view or state).
    function check(address agent, Policy policy)
        external
        returns (bool passes, string memory reason)
    {
        TrustResult memory result = _evaluate(agent, policy, CustomPolicy(0, 0, 0));

        emit TrustChecked(
            msg.sender,
            agent,
            policy,
            result.passes,
            result.accuracyBps,
            result.reputation
        );

        return (result.passes, result.reason);
    }

    /// @notice View-only version of check (no event emitted, gas-free off-chain reads)
    function query(address agent, Policy policy)
        external
        view
        returns (bool passes, string memory reason)
    {
        TrustResult memory result = _evaluate(agent, policy, CustomPolicy(0, 0, 0));
        return (result.passes, result.reason);
    }

    /// @notice Check against a custom policy (caller sets exact thresholds)
    /// @param agent    The agent address to evaluate
    /// @param cp       Custom policy thresholds
    /// @return passes  true if agent meets all thresholds
    /// @return reason  Human-readable explanation
    function checkCustom(address agent, CustomPolicy calldata cp)
        external
        returns (bool passes, string memory reason)
    {
        if (cp.minClaims == 0) revert InvalidCustomPolicy();
        TrustResult memory result = _evaluate(agent, Policy.CUSTOM, cp);

        emit CustomTrustChecked(
            msg.sender,
            agent,
            result.passes,
            cp.minAccuracyBps,
            cp.minReputation
        );

        return (result.passes, result.reason);
    }

    /// @notice Full evaluation result struct (most informative)
    /// @param agent   The agent address to evaluate
    /// @param policy  Which preset to apply (LENIENT / STANDARD / STRICT)
    /// @return Full TrustResult struct
    function evaluate(address agent, Policy policy)
        external
        view
        returns (TrustResult memory)
    {
        return _evaluate(agent, policy, CustomPolicy(0, 0, 0));
    }

    /// @notice Batch evaluation — check multiple agents in one call
    /// @param agents  Array of agent addresses
    /// @param policy  Policy to apply to all agents
    /// @return results Array of TrustResult structs, one per agent
    function evaluateBatch(address[] calldata agents, Policy policy)
        external
        view
        returns (TrustResult[] memory results)
    {
        results = new TrustResult[](agents.length);
        for (uint256 i = 0; i < agents.length; i++) {
            results[i] = _evaluate(agents[i], policy, CustomPolicy(0, 0, 0));
        }
    }

    /// @notice Filter an agent array to only those passing a policy
    /// @param agents  Candidate agents
    /// @param policy  Trust policy to filter by
    /// @return qualified  Only the agents that pass
    function filter(address[] calldata agents, Policy policy)
        external
        view
        returns (address[] memory qualified)
    {
        // Two-pass: count then copy (avoids dynamic memory resizing)
        uint256 count = 0;
        bool[] memory passes = new bool[](agents.length);
        for (uint256 i = 0; i < agents.length; i++) {
            passes[i] = _evaluate(agents[i], policy, CustomPolicy(0, 0, 0)).passes;
            if (passes[i]) count++;
        }
        qualified = new address[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < agents.length; i++) {
            if (passes[i]) qualified[j++] = agents[i];
        }
    }

    // ============ Internal Logic ============

    /// @dev Core evaluation function. Resolves policy to thresholds, reads on-chain
    ///      data from AgentProfile and Reputation, and returns a full TrustResult.
    function _evaluate(
        address agent,
        Policy policy,
        CustomPolicy memory cp
    ) internal view returns (TrustResult memory result) {
        // Resolve thresholds
        uint256 minAccuracyBps;
        int256  minReputation;
        uint256 minClaims;

        if (policy == Policy.CUSTOM) {
            minAccuracyBps = cp.minAccuracyBps;
            minReputation  = cp.minReputation;
            minClaims      = cp.minClaims;
        } else if (policy == Policy.STRICT) {
            minAccuracyBps = STRICT_MIN_ACCURACY_BPS;
            minReputation  = STRICT_MIN_REPUTATION;
            minClaims      = STRICT_MIN_CLAIMS;
        } else if (policy == Policy.STANDARD) {
            minAccuracyBps = STANDARD_MIN_ACCURACY_BPS;
            minReputation  = STANDARD_MIN_REPUTATION;
            minClaims      = STANDARD_MIN_CLAIMS;
        } else {
            // LENIENT
            minAccuracyBps = LENIENT_MIN_ACCURACY_BPS;
            minReputation  = LENIENT_MIN_REPUTATION;
            minClaims      = LENIENT_MIN_CLAIMS;
        }

        // Read on-chain data
        EMETAgentProfile.Profile memory profile = agentProfile.getProfile(agent);
        int256 rep = reputation.getReputation(agent);

        result.accuracyBps = profile.accuracyBps;
        result.reputation  = rep;
        result.totalClaims = profile.totalClaims;

        // Gate 1: minimum claim history
        if (profile.totalClaims < minClaims) {
            result.passes = false;
            result.reason = _claimsReason(profile.totalClaims, minClaims);
            return result;
        }

        // Gate 2: accuracy
        if (profile.accuracyBps < minAccuracyBps) {
            result.passes = false;
            result.reason = _accuracyReason(profile.accuracyBps, minAccuracyBps);
            return result;
        }

        // Gate 3: reputation
        if (rep < minReputation) {
            result.passes = false;
            result.reason = _reputationReason(rep, minReputation);
            return result;
        }

        result.passes = true;
        result.reason = "PASS";
    }

    // ============ Reason Helpers ============

    function _claimsReason(uint256 have, uint256 need)
        internal pure returns (string memory)
    {
        // Minimal reason string (avoids heavy string concat in hot path)
        if (have == 0) return "NO_HISTORY: agent has no resolved claims";
        return "INSUFFICIENT_CLAIMS: below minimum resolved claim count";
        // Note: exact counts available via evaluate() struct — avoids gas-heavy
        //       uint-to-string conversion in all callers.
        (need); // silence unused warning
    }

    function _accuracyReason(uint256 have, uint256 need)
        internal pure returns (string memory)
    {
        if (have == 0) return "ZERO_ACCURACY: no correct claims on record";
        return "LOW_ACCURACY: accuracy below policy threshold";
        (need);
    }

    function _reputationReason(int256 have, int256 need)
        internal pure returns (string memory)
    {
        if (have < 0) return "NEGATIVE_REPUTATION: agent has been penalized";
        return "LOW_REPUTATION: reputation below policy threshold";
        (need);
    }
}
