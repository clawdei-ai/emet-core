// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

/// @title EMETAgentProfile — On-chain accuracy/risk-appetite separation for EMET Protocol (v2)
/// @notice Separates two independent trust dimensions per agent:
///
///   1. **accuracyBps**: % of staked claims that resolved correctly (basis points, 0–10000)
///   2. **riskAppetite**: Low / Medium / High, based on average stake size
///
/// @dev V1 EMETReputation blended accuracy and risk into one reputation score.
///      This caused two problems:
///        - Risk-seeking agents (large stakes, some slashes) appeared untrustworthy
///        - Risk-averse agents (tiny stakes, never slashed) appeared trustworthy
///
///      V2 separates them. A high-stakes, occasionally-wrong agent can still have
///      90% accuracy (trustworthy). A low-stakes, never-slashed agent might have
///      50% accuracy (coin-flip). Callers set threshold on accuracyBps directly.
///
///      Stake floors (set by requester tier) use avgStakeWei from this contract.
///
/// Risk classification thresholds:
///   Unknown: no claims yet
///   Low:     avg stake < 0.001 ETH
///   Medium:  avg stake 0.001–0.01 ETH
///   High:    avg stake >= 0.01 ETH
///
/// @custom:version 0.10.0
/// @custom:design-source docs/emet-architecture-v2-design.md — Section 2
contract EMETAgentProfile {

    // ============ Types ============

    enum RiskAppetite { Unknown, Low, Medium, High }

    struct Profile {
        uint256 totalClaims;       // Total claims staked (correct + slashed)
        uint256 correctClaims;     // Claims that resolved correctly
        uint256 slashCount;        // Claims slashed (wrong outcome)
        uint256 totalStakeWei;     // Cumulative stake in wei across all claims
        uint256 avgStakeWei;       // Rolling avg stake = totalStakeWei / totalClaims
        uint256 accuracyBps;       // Accuracy in basis points: 10000 = 100% correct
        RiskAppetite riskAppetite; // Low / Medium / High (Unknown if no history)
    }

    // ============ Constants ============

    /// @notice Below this avg stake → Low risk appetite
    uint256 public constant RISK_LOW_THRESHOLD = 0.001 ether;

    /// @notice Below this avg stake → Medium risk appetite (above = High)
    uint256 public constant RISK_MEDIUM_THRESHOLD = 0.01 ether;

    /// @notice Basis point denominator (10000 = 100%)
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Gold-tier requester accuracy threshold (basis points)
    uint256 public constant GOLD_ACCURACY_BPS = 8_000; // 80%

    /// @notice Gold-tier requester minimum task count
    uint256 public constant GOLD_MIN_CLAIMS = 20;

    /// @notice Silver-tier requester accuracy threshold (basis points)
    uint256 public constant SILVER_ACCURACY_BPS = 6_000; // 60%

    /// @notice Silver-tier requester minimum task count
    uint256 public constant SILVER_MIN_CLAIMS = 5;

    /// @notice Stake floor required when a Gold-tier agent queries another
    uint256 public constant GOLD_STAKE_FLOOR = 0.01 ether;

    /// @notice Stake floor required when a Silver-tier agent queries another
    uint256 public constant SILVER_STAKE_FLOOR = 0.001 ether;

    // ============ State ============

    /// @notice Profile per agent address
    mapping(address => Profile) public profiles;

    /// @notice Authorized updater (set once by deployer)
    address public updater;

    /// @notice Deployer address (used to set updater once)
    address public immutable deployer;

    // ============ Events ============

    /// @notice Emitted whenever an agent's profile is recomputed
    event ProfileUpdated(
        address indexed agent,
        uint256 accuracyBps,
        RiskAppetite riskAppetite,
        uint256 totalClaims,
        uint256 correctClaims,
        uint256 avgStakeWei
    );

    /// @notice Emitted when the authorized updater is set
    event UpdaterSet(address indexed updater);

    // ============ Errors ============

    error OnlyUpdater();
    error OnlyDeployer();
    error UpdaterAlreadySet();
    error ZeroAddress();

    // ============ Constructor ============

    constructor() {
        deployer = msg.sender;
    }

    // ============ Configuration ============

    /// @notice Set the authorized updater contract. Can only be called once.
    /// @param _updater Address of the authorized contract (e.g. EMETChallengeV3)
    function setUpdater(address _updater) external {
        if (msg.sender != deployer) revert OnlyDeployer();
        if (updater != address(0)) revert UpdaterAlreadySet();
        if (_updater == address(0)) revert ZeroAddress();
        updater = _updater;
        emit UpdaterSet(_updater);
    }

    // ============ Profile Updates (authorized updater only) ============

    /// @notice Record a correctly resolved claim for an agent
    /// @param agent  The agent whose claim was correct
    /// @param stakeWei The stake amount in wei for this claim
    function recordCorrectClaim(address agent, uint256 stakeWei) external {
        _onlyUpdater();
        Profile storage p = profiles[agent];
        p.totalClaims++;
        p.correctClaims++;
        p.totalStakeWei += stakeWei;
        _recompute(p);
        emit ProfileUpdated(agent, p.accuracyBps, p.riskAppetite, p.totalClaims, p.correctClaims, p.avgStakeWei);
    }

    /// @notice Record a slashed (incorrect) claim for an agent
    /// @param agent  The agent whose claim was wrong
    /// @param stakeWei The stake amount in wei for this claim
    function recordSlashedClaim(address agent, uint256 stakeWei) external {
        _onlyUpdater();
        Profile storage p = profiles[agent];
        p.totalClaims++;
        p.slashCount++;
        // correctClaims stays the same — accuracy goes down
        p.totalStakeWei += stakeWei;
        _recompute(p);
        emit ProfileUpdated(agent, p.accuracyBps, p.riskAppetite, p.totalClaims, p.correctClaims, p.avgStakeWei);
    }

    // ============ Internal Helpers ============

    /// @dev Recompute accuracyBps, avgStakeWei, and riskAppetite after any update
    function _recompute(Profile storage p) internal {
        if (p.totalClaims > 0) {
            p.accuracyBps = (p.correctClaims * BPS_DENOMINATOR) / p.totalClaims;
            p.avgStakeWei = p.totalStakeWei / p.totalClaims;
        }
        p.riskAppetite = _classifyRisk(p.avgStakeWei);
    }

    /// @dev Classify risk appetite from average stake in wei
    function _classifyRisk(uint256 avgWei) internal pure returns (RiskAppetite) {
        if (avgWei == 0)                        return RiskAppetite.Unknown;
        if (avgWei < RISK_LOW_THRESHOLD)        return RiskAppetite.Low;
        if (avgWei < RISK_MEDIUM_THRESHOLD)     return RiskAppetite.Medium;
        return RiskAppetite.High;
    }

    /// @dev Derive requester tier from their profile
    function _getRequesterTier(Profile storage rp) internal view returns (uint8) {
        if (rp.accuracyBps >= GOLD_ACCURACY_BPS && rp.totalClaims >= GOLD_MIN_CLAIMS) return 2; // Gold
        if (rp.accuracyBps >= SILVER_ACCURACY_BPS && rp.totalClaims >= SILVER_MIN_CLAIMS) return 1; // Silver
        return 0; // Bronze
    }

    function _onlyUpdater() internal view {
        if (msg.sender != updater) revert OnlyUpdater();
    }

    // ============ View Functions ============

    /// @notice Get the full profile for an agent
    /// @param agent Address to query
    /// @return Full Profile struct
    function getProfile(address agent) external view returns (Profile memory) {
        return profiles[agent];
    }

    /// @notice Get accuracy in basis points (10000 = 100% correct)
    function getAccuracyBps(address agent) external view returns (uint256) {
        return profiles[agent].accuracyBps;
    }

    /// @notice Get risk appetite classification
    function getRiskAppetite(address agent) external view returns (RiskAppetite) {
        return profiles[agent].riskAppetite;
    }

    /// @notice Check if an agent meets an accuracy threshold
    /// @param agent         Candidate agent
    /// @param thresholdBps  Minimum accuracy in basis points (e.g. 7500 = 75%)
    /// @return true if agent has history AND accuracyBps >= thresholdBps
    function meetsAccuracyThreshold(address agent, uint256 thresholdBps) external view returns (bool) {
        Profile storage p = profiles[agent];
        if (p.totalClaims == 0) return false; // no history — bootstrap path, caller decides
        return p.accuracyBps >= thresholdBps;
    }

    /// @notice Check if candidate meets the stake floor set by the requester's tier
    /// @dev Gold requester → candidate must avg ≥ 0.01 ETH
    ///      Silver requester → candidate must avg ≥ 0.001 ETH
    ///      Bronze requester → no floor (bootstrap path always passes)
    /// @param candidate  Agent whose stake floor is being checked
    /// @param requester  Agent requesting the trust check (their tier sets the floor)
    /// @return meetsFloor true if candidate avg stake >= required floor
    /// @return floorWei   The stake floor in wei (0 = no floor)
    function meetsStakeFloor(address candidate, address requester)
        external
        view
        returns (bool meetsFloor, uint256 floorWei)
    {
        Profile storage rp = profiles[requester];
        uint8 tier = _getRequesterTier(rp);

        if (tier == 2) {
            floorWei = GOLD_STAKE_FLOOR;
        } else if (tier == 1) {
            floorWei = SILVER_STAKE_FLOOR;
        } else {
            return (true, 0); // Bronze: no floor
        }

        meetsFloor = profiles[candidate].avgStakeWei >= floorWei;
    }

    /// @notice Human-readable risk appetite label
    function riskLabel(address agent) external view returns (string memory) {
        RiskAppetite r = profiles[agent].riskAppetite;
        if (r == RiskAppetite.Unknown) return "Unknown";
        if (r == RiskAppetite.Low)     return "Low";
        if (r == RiskAppetite.Medium)  return "Medium";
        return "High";
    }

    /// @notice Derive tier label from profile (mirrors API agent-profile.js)
    /// @param agent Address to query
    /// @return tier "Bronze" | "Silver" | "Gold"
    function tierLabel(address agent) external view returns (string memory tier) {
        Profile storage p = profiles[agent];
        uint8 t = _getRequesterTier(p);
        if (t == 2) return "Gold";
        if (t == 1) return "Silver";
        return "Bronze";
    }
}
