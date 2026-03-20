// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

/// @title EMETReputation - On-chain reputation tracking for EMET Protocol participants
/// @notice Tracks reputation scores based on claim outcomes. Higher reputation = better
///         reward multipliers. Scores are signed integers (can go negative).
/// @dev Only authorized updaters (ChallengeV2) can modify reputation. Read access is public.
///      Uses int256 for reputation so bad actors get penalized below zero.
///
///      Scoring rules:
///        Claim submitted & verified:    +10
///        Claim submitted & rejected:    -20
///        Successful challenge:          +15
///        Failed challenge:              -10
///        Co-signature on verified claim: +5
///
///      Multiplier: 1.0x at 0 reputation, scales linearly to 2.0x at 100+ reputation.
///      Negative reputation = 1.0x (no penalty below floor, just no bonus).
contract EMETReputation {
    // ============ Constants ============

    /// @notice Points for submitting a claim that gets verified
    int256 public constant CLAIM_VERIFIED_POINTS = 10;

    /// @notice Points for submitting a claim that gets rejected (negative)
    int256 public constant CLAIM_REJECTED_POINTS = -20;

    /// @notice Points for a successful challenge (claim rejected)
    int256 public constant CHALLENGE_SUCCESS_POINTS = 15;

    /// @notice Points for a failed challenge (claim verified despite challenge)
    int256 public constant CHALLENGE_FAILED_POINTS = -10;

    /// @notice Points for co-signing a claim that gets verified
    int256 public constant COSIGN_VERIFIED_POINTS = 5;

    /// @notice Reputation score at which maximum multiplier is reached
    int256 public constant MAX_REP_THRESHOLD = 100;

    /// @notice Multiplier precision (1e18 = 1.0x)
    uint256 public constant MULTIPLIER_PRECISION = 1e18;

    /// @notice Minimum multiplier (1.0x)
    uint256 public constant MIN_MULTIPLIER = 1e18;

    /// @notice Maximum multiplier (2.0x)
    uint256 public constant MAX_MULTIPLIER = 2e18;

    /// @notice Overconfidence penalty multiplier (2x loss for >95% confidence + wrong)
    int256 public constant OVERCONFIDENCE_PENALTY_MULTIPLIER = 2;

    /// @notice Overconfidence threshold in basis points (95% = 9500)
    uint256 public constant OVERCONFIDENCE_THRESHOLD_BPS = 9500;

    /// @notice Novelty score precision (basis points)
    uint256 public constant NOVELTY_PRECISION = 10_000;

    // ============ State ============

    /// @notice Reputation score per address (signed, can be negative)
    mapping(address => int256) public reputation;

    /// @notice Count of correctly resolved stakes per address (for prior-stake challenger guard)
    /// @dev Incremented on every successful challenge (challenge_success) outcome.
    ///      Used by ChallengeV3.requiresPriorStake to block slash-farming attacks.
    mapping(address => uint256) public resolvedCorrectCount;

    /// @notice Authorized updater (ChallengeV2 contract), set once
    address public updater;

    /// @notice Deployer, used only to set updater once
    address public immutable deployer;

    /// @notice Total reputation updates processed
    uint256 public totalUpdates;

    // ============ Events ============

    /// @notice Emitted when a user's reputation changes
    event ReputationUpdated(
        address indexed account,
        int256 oldScore,
        int256 newScore,
        int256 delta,
        string reason
    );

    /// @notice Emitted when the updater is set
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

    /// @notice Set the authorized updater contract. Can only be set once.
    /// @param _updater Address of EMETChallengeV2
    function setUpdater(address _updater) external {
        if (msg.sender != deployer) revert OnlyDeployer();
        if (updater != address(0)) revert UpdaterAlreadySet();
        if (_updater == address(0)) revert ZeroAddress();
        updater = _updater;
        emit UpdaterSet(_updater);
    }

    // ============ Reputation Updates (only by authorized updater) ============

    /// @notice Record reputation for a claim submitter when their claim is verified
    /// @param submitter The claim submitter address
    function recordClaimVerified(address submitter) external {
        _onlyUpdater();
        _updateReputation(submitter, CLAIM_VERIFIED_POINTS, "claim_verified");
    }

    /// @notice Record reputation for a claim submitter when their claim is rejected
    /// @param submitter The claim submitter address
    function recordClaimRejected(address submitter) external {
        _onlyUpdater();
        _updateReputation(submitter, CLAIM_REJECTED_POINTS, "claim_rejected");
    }

    /// @notice Record reputation for a successful challenger (claim was rejected)
    /// @param challenger The challenger address
    function recordChallengeSuccess(address challenger) external {
        _onlyUpdater();
        // Increment prior-stake counter: this challenger now qualifies for future challenges
        resolvedCorrectCount[challenger]++;
        _updateReputation(challenger, CHALLENGE_SUCCESS_POINTS, "challenge_success");
    }

    /// @notice Record reputation for a failed challenger (claim was verified)
    /// @param challenger The challenger address
    function recordChallengeFailed(address challenger) external {
        _onlyUpdater();
        _updateReputation(challenger, CHALLENGE_FAILED_POINTS, "challenge_failed");
    }

    /// @notice Record reputation for co-signers when the signed claim is verified
    /// @param cosigner The co-signer address
    function recordCosignVerified(address cosigner) external {
        _onlyUpdater();
        _updateReputation(cosigner, COSIGN_VERIFIED_POINTS, "cosign_verified");
    }

    /// @notice Batch update reputation for multiple co-signers
    /// @param cosigners Array of co-signer addresses
    function recordCosignVerifiedBatch(address[] calldata cosigners) external {
        _onlyUpdater();
        for (uint256 i = 0; i < cosigners.length; i++) {
            _updateReputation(cosigners[i], COSIGN_VERIFIED_POINTS, "cosign_verified");
        }
    }

    /// @notice Record no reputation change for an uncontested claim
    /// @dev Emits event for tracking but applies zero delta
    /// @param submitter The claim submitter address
    function recordClaimUncontested(address submitter) external {
        _onlyUpdater();
        int256 score = reputation[submitter];
        emit ReputationUpdated(submitter, score, score, 0, "claim_uncontested");
        totalUpdates++;
    }

    /// @notice Record reputation for a verified claim with novelty score multiplier
    /// @dev Novelty score amplifies the base reward: 10000 = 1x, 20000 = 2x, etc.
    /// @param submitter The claim submitter address
    /// @param noveltyBps Novelty score in basis points (10000 = 1.0x baseline)
    function recordClaimVerifiedWithNovelty(address submitter, uint256 noveltyBps) external {
        _onlyUpdater();
        int256 adjustedPoints = (CLAIM_VERIFIED_POINTS * int256(noveltyBps)) / int256(NOVELTY_PRECISION);
        if (adjustedPoints < 1) adjustedPoints = 1; // minimum 1 point
        _updateReputation(submitter, adjustedPoints, "claim_verified_novel");
    }

    /// @notice Apply overconfidence penalty (2x loss for >95% confidence + wrong)
    /// @dev Called when someone stakes with overwhelming confidence and loses
    /// @param account The penalized address
    function recordOverconfidencePenalty(address account) external {
        _onlyUpdater();
        int256 penalty = CLAIM_REJECTED_POINTS * OVERCONFIDENCE_PENALTY_MULTIPLIER;
        _updateReputation(account, penalty, "overconfidence_penalty");
    }

    /// @notice Check if a stake ratio constitutes overconfidence
    /// @param stakeAmount The individual's stake
    /// @param totalPool The total stake pool
    /// @return isOverconfident True if stake exceeds 95% of pool
    function isOverconfident(uint256 stakeAmount, uint256 totalPool) external pure returns (bool) {
        if (totalPool == 0) return false;
        return (stakeAmount * 10_000) / totalPool >= OVERCONFIDENCE_THRESHOLD_BPS;
    }

    // ============ Internal ============

    function _onlyUpdater() internal view {
        if (msg.sender != updater) revert OnlyUpdater();
    }

    function _updateReputation(address account, int256 delta, string memory reason) internal {
        int256 oldScore = reputation[account];
        int256 newScore = oldScore + delta;
        reputation[account] = newScore;
        totalUpdates++;

        emit ReputationUpdated(account, oldScore, newScore, delta, reason);
    }

    // ============ View Functions ============

    /// @notice Get the reputation score for an address
    /// @param account The address to query
    /// @return score The reputation score (can be negative)
    function getReputation(address account) external view returns (int256 score) {
        return reputation[account];
    }

    /// @notice Get the reward multiplier for an address based on reputation
    /// @dev Returns value in 1e18 precision. 1e18 = 1.0x, 2e18 = 2.0x
    ///      Linear scale: 0 rep → 1.0x, 100+ rep → 2.0x
    ///      Negative rep → 1.0x (floor, no penalty below minimum)
    /// @param account The address to query
    /// @return multiplier The reward multiplier (1e18 to 2e18)
    function getReputationMultiplier(address account) external view returns (uint256 multiplier) {
        int256 score = reputation[account];

        // Negative or zero reputation = minimum multiplier
        if (score <= 0) return MIN_MULTIPLIER;

        // Cap at MAX_REP_THRESHOLD
        if (score >= MAX_REP_THRESHOLD) return MAX_MULTIPLIER;

        // Linear interpolation: 1.0x + (score / 100) * 1.0x
        // In 1e18 precision: 1e18 + (score * 1e18) / 100
        uint256 bonus = (uint256(score) * MULTIPLIER_PRECISION) / uint256(MAX_REP_THRESHOLD);
        return MIN_MULTIPLIER + bonus;
    }

    /// @notice Check if an address has positive reputation
    /// @param account The address to check
    /// @return positive True if reputation > 0
    function hasPositiveReputation(address account) external view returns (bool positive) {
        return reputation[account] > 0;
    }

    /// @notice Get reputation tier label for display
    /// @param account The address to query
    /// @return tier The tier name
    function getReputationTier(address account) external view returns (string memory tier) {
        int256 score = reputation[account];
        if (score < 0) return "Untrusted";
        if (score == 0) return "Unknown";
        if (score < 25) return "Newcomer";
        if (score < 50) return "Contributor";
        if (score < 75) return "Trusted";
        if (score < 100) return "Expert";
        return "Authority";
    }
}
