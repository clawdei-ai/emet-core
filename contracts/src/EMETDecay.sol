// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {IEMET} from "./interfaces/IEMET.sol";
import {EMETRegistry} from "./EMETRegistry.sol";

/// @title EMETDecay - Time-based decay for claim validity
/// @notice Claims lose weight over time if not refreshed. Fresh claims = 100 weight,
///         decays linearly to 10 (minimum) over 365 days. Anyone can refresh a claim
///         by adding stake, which resets the decay timer.
///
/// @dev Weight calculation:
///   - First 90 days: weight = 100 (no decay)
///   - 90-365 days: linear decay from 100 to 10
///   - After 365 days: weight = 10 (minimum floor)
///
///   Refreshing:
///   - Resets decay timer to current timestamp
///   - Requires additional stake (min 10% of original claim stake)
///   - Anyone can refresh (incentivized to maintain important claims)
///
///   Stale claim bounties:
///   - Anyone can report stale claims (decayed > 50%)
///   - Reporter gets STALE_REPORT_REWARD from contract balance
///   - Claim gets flagged for review
contract EMETDecay {
    // ============ Constants ============

    /// @notice EMET token on Base mainnet
    IEMET public constant EMET = IEMET(0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C);

    /// @notice Grace period before decay starts (90 days)
    uint256 public constant DECAY_PERIOD = 90 days;

    /// @notice Full decay period (365 days from submission)
    uint256 public constant FULL_DECAY_PERIOD = 365 days;

    /// @notice Maximum weight (fresh claim)
    uint256 public constant MAX_WEIGHT = 100;

    /// @notice Minimum weight (fully decayed, 10%)
    uint256 public constant MIN_WEIGHT = 10;

    /// @notice Minimum refresh stake (10% of original, in BPS)
    uint256 public constant MIN_REFRESH_STAKE_BPS = 1000;

    /// @notice BPS denominator
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Reward for reporting stale claims
    uint256 public constant STALE_REPORT_REWARD = 5 ether;

    /// @notice Decay threshold for stale reporting (weight must be below this)
    uint256 public constant STALE_THRESHOLD = 50;

    // ============ Immutables ============

    EMETRegistry public immutable registry;

    // ============ State ============

    /// @notice Last refresh timestamp per claim (0 = use original claim timestamp)
    mapping(uint256 => uint256) public lastRefreshTime;

    /// @notice Total additional stake added through refreshes
    mapping(uint256 => uint256) public refreshStakes;

    /// @notice Number of times a claim has been refreshed
    mapping(uint256 => uint256) public refreshCount;

    /// @notice Whether a claim has been flagged as stale
    mapping(uint256 => bool) public flaggedStale;

    /// @notice Who flagged the claim as stale
    mapping(uint256 => address) public staleReporter;

    /// @notice Deployer for funding
    address public immutable deployer;

    // ============ Events ============

    event ClaimRefreshed(
        uint256 indexed claimId,
        address indexed refresher,
        uint256 additionalStake,
        uint256 newWeight
    );

    event StaleClaimReported(
        uint256 indexed claimId,
        address indexed reporter,
        uint256 currentWeight,
        uint256 reward
    );

    event StaleClaimFlagCleared(uint256 indexed claimId);

    // ============ Errors ============

    error ClaimDoesNotExist(uint256 claimId);
    error ClaimNotActive(uint256 claimId);
    error InsufficientRefreshStake(uint256 provided, uint256 required);
    error ClaimNotStale(uint256 claimId, uint256 currentWeight);
    error AlreadyFlaggedStale(uint256 claimId);
    error InsufficientRewardBalance();
    error TransferFailed();

    // ============ Constructor ============

    constructor(address _registry) {
        if (_registry == address(0)) revert ClaimDoesNotExist(0);
        registry = EMETRegistry(_registry);
        deployer = msg.sender;
    }

    // ============ Weight Calculation ============

    /// @notice Get current weight of a claim (100 = full, decays to 10)
    /// @param claimId The claim to check
    /// @return weight Current weight (10-100)
    function getClaimWeight(uint256 claimId) external view returns (uint256 weight) {
        return _calculateWeight(claimId);
    }

    /// @notice Check if a claim needs refresh (weight below 50)
    /// @param claimId The claim to check
    /// @return needsIt True if claim weight is below 50
    function needsRefresh(uint256 claimId) external view returns (bool needsIt) {
        uint256 weight = _calculateWeight(claimId);
        return weight < STALE_THRESHOLD;
    }

    /// @notice Get time until claim starts decaying
    /// @param claimId The claim to check
    /// @return seconds_ Seconds until decay starts (0 if already decaying)
    function timeUntilDecay(uint256 claimId) external view returns (uint256 seconds_) {
        uint256 baseTime = _getBaseTime(claimId);
        uint256 decayStart = baseTime + DECAY_PERIOD;

        if (block.timestamp >= decayStart) return 0;
        return decayStart - block.timestamp;
    }

    /// @notice Get time until claim reaches minimum weight
    /// @param claimId The claim to check
    /// @return seconds_ Seconds until full decay (0 if fully decayed)
    function timeUntilFullDecay(uint256 claimId) external view returns (uint256 seconds_) {
        uint256 baseTime = _getBaseTime(claimId);
        uint256 fullDecay = baseTime + FULL_DECAY_PERIOD;

        if (block.timestamp >= fullDecay) return 0;
        return fullDecay - block.timestamp;
    }

    // ============ Refresh ============

    /// @notice Refresh a claim by adding stake, resetting the decay timer
    /// @dev Anyone can refresh. Requires min 10% of original claim stake.
    /// @param claimId The claim to refresh
    /// @param additionalStake Amount of additional EMET to stake
    function refreshClaim(uint256 claimId, uint256 additionalStake) external {
        EMETRegistry.Claim memory claim = registry.getClaim(claimId);

        // Only active or verified claims can be refreshed
        if (claim.status != EMETRegistry.ClaimStatus.Active &&
            claim.status != EMETRegistry.ClaimStatus.Verified) {
            revert ClaimNotActive(claimId);
        }

        // Minimum refresh stake: 10% of original claim stake
        uint256 minRefresh = (claim.stake * MIN_REFRESH_STAKE_BPS) / BPS_DENOMINATOR;
        if (minRefresh == 0) minRefresh = 1 ether; // Floor of 1 EMET
        if (additionalStake < minRefresh) {
            revert InsufficientRefreshStake(additionalStake, minRefresh);
        }

        // Transfer additional stake to registry (claim gets stronger)
        if (!EMET.transferFrom(msg.sender, address(registry), additionalStake)) {
            revert TransferFailed();
        }

        // Reset decay timer
        lastRefreshTime[claimId] = block.timestamp;
        refreshStakes[claimId] += additionalStake;
        refreshCount[claimId]++;

        // Clear stale flag if it was set
        if (flaggedStale[claimId]) {
            flaggedStale[claimId] = false;
            emit StaleClaimFlagCleared(claimId);
        }

        uint256 newWeight = _calculateWeight(claimId);
        emit ClaimRefreshed(claimId, msg.sender, additionalStake, newWeight);
    }

    // ============ Stale Reporting ============

    /// @notice Report a stale claim for a bounty
    /// @dev Claim must have decayed below STALE_THRESHOLD (50%)
    /// @param claimId The stale claim to report
    function reportStaleClaim(uint256 claimId) external {
        if (flaggedStale[claimId]) revert AlreadyFlaggedStale(claimId);

        uint256 weight = _calculateWeight(claimId);
        if (weight >= STALE_THRESHOLD) {
            revert ClaimNotStale(claimId, weight);
        }

        // Flag as stale
        flaggedStale[claimId] = true;
        staleReporter[claimId] = msg.sender;

        // Pay bounty if contract has funds
        uint256 reward = 0;
        uint256 contractBalance = EMET.balanceOf(address(this));
        if (contractBalance >= STALE_REPORT_REWARD) {
            reward = STALE_REPORT_REWARD;
            if (!EMET.transfer(msg.sender, reward)) revert TransferFailed();
        }

        emit StaleClaimReported(claimId, msg.sender, weight, reward);
    }

    // ============ Internal Functions ============

    /// @notice Calculate current weight of a claim
    /// @dev Linear decay from MAX_WEIGHT to MIN_WEIGHT between DECAY_PERIOD and FULL_DECAY_PERIOD
    function _calculateWeight(uint256 claimId) internal view returns (uint256) {
        uint256 baseTime = _getBaseTime(claimId);
        uint256 elapsed = block.timestamp - baseTime;

        // Before decay period: full weight
        if (elapsed <= DECAY_PERIOD) {
            return MAX_WEIGHT;
        }

        // After full decay: minimum weight
        if (elapsed >= FULL_DECAY_PERIOD) {
            return MIN_WEIGHT;
        }

        // Linear decay between DECAY_PERIOD and FULL_DECAY_PERIOD
        // Weight range: MAX_WEIGHT → MIN_WEIGHT (100 → 10, range = 90)
        // Time range: DECAY_PERIOD → FULL_DECAY_PERIOD (90d → 365d, range = 275d)
        uint256 decayElapsed = elapsed - DECAY_PERIOD;
        uint256 decayRange = FULL_DECAY_PERIOD - DECAY_PERIOD;
        uint256 weightRange = MAX_WEIGHT - MIN_WEIGHT;

        uint256 decayed = (decayElapsed * weightRange) / decayRange;
        return MAX_WEIGHT - decayed;
    }

    /// @notice Get the base time for decay calculation
    /// @dev Uses lastRefreshTime if available, otherwise claim submission time
    function _getBaseTime(uint256 claimId) internal view returns (uint256) {
        uint256 refreshTime = lastRefreshTime[claimId];
        if (refreshTime != 0) {
            return refreshTime;
        }

        // Use claim submission timestamp from registry
        EMETRegistry.Claim memory claim = registry.getClaim(claimId);
        return claim.timestamp;
    }

    // ============ View Functions ============

    /// @notice Get comprehensive decay info for a claim
    /// @param claimId The claim to query
    /// @return weight Current weight (10-100)
    /// @return isStale Whether flagged as stale
    /// @return totalRefreshStake Total additional stake from refreshes
    /// @return numRefreshes Number of times refreshed
    function getDecayInfo(uint256 claimId)
        external
        view
        returns (
            uint256 weight,
            bool isStale,
            uint256 totalRefreshStake,
            uint256 numRefreshes
        )
    {
        return (
            _calculateWeight(claimId),
            flaggedStale[claimId],
            refreshStakes[claimId],
            refreshCount[claimId]
        );
    }

    /// @notice Get the base timestamp for decay calculation
    /// @param claimId The claim to query
    /// @return baseTime The timestamp used for decay
    function getBaseTime(uint256 claimId) external view returns (uint256 baseTime) {
        return _getBaseTime(claimId);
    }
}
