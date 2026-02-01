// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {IEMET} from "./interfaces/IEMET.sol";

/// @title EMETConcentration - Anti-concentration limits for EMET Protocol
/// @notice Prevents any single wallet or model family from dominating the protocol.
///
///      Limits enforced:
///        - Max 5% of total pool per wallet
///        - Max 40% verification weight per model family
///        - Progressive fees above 1% pool share
///        - Sponsor chain depth limit (max 3 hops)
///
/// @dev Contracts that modify stake/weight call check* functions before allowing operations.
///      All thresholds are immutable after deployment (trustless).
contract EMETConcentration {
    // ============ Constants ============

    /// @notice EMET token on Base mainnet
    IEMET public constant EMET = IEMET(0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C);

    /// @notice Maximum share of total pool a single wallet can hold (5% = 500 bps)
    uint256 public constant MAX_WALLET_SHARE_BPS = 500;

    /// @notice Maximum verification weight per model family (40% = 4000 bps)
    uint256 public constant MAX_MODEL_FAMILY_WEIGHT_BPS = 4000;

    /// @notice Progressive fee threshold (1% = 100 bps)
    uint256 public constant PROGRESSIVE_FEE_THRESHOLD_BPS = 100;

    /// @notice Maximum sponsor chain depth
    uint256 public constant MAX_SPONSOR_DEPTH = 3;

    /// @notice Basis-point denominator
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Progressive fee rate per BPS above threshold (0.1% per 1% above threshold)
    uint256 public constant PROGRESSIVE_FEE_RATE_BPS = 10;

    /// @notice Minimum pool size before concentration limits are enforced (bootstrap period)
    /// @dev Below this threshold, limits are relaxed to allow initial participation
    uint256 public constant MIN_POOL_FOR_LIMITS = 100_000e18;

    // ============ State ============

    /// @notice Total stake per wallet across all claims
    mapping(address => uint256) public walletStake;

    /// @notice Total verification weight per model family (identified by keccak256 of name)
    mapping(bytes32 => uint256) public modelFamilyWeight;

    /// @notice Total pool size (sum of all stakes)
    uint256 public totalPoolSize;

    /// @notice Sponsor relationships: sponsored → sponsor
    mapping(address => address) public sponsors;

    /// @notice Authorized updater (stake contract or challenge contract)
    address public updater;

    /// @notice Deployer, used only to set updater once
    address public immutable deployer;

    // ============ Events ============

    event StakeRecorded(address indexed wallet, uint256 amount, uint256 newTotal);
    event StakeRemoved(address indexed wallet, uint256 amount, uint256 newTotal);
    event ModelWeightUpdated(bytes32 indexed modelFamily, uint256 newWeight);
    event SponsorSet(address indexed sponsored, address indexed sponsor);
    event ProgressiveFeeApplied(address indexed wallet, uint256 feeAmount, uint256 shareBps);
    event UpdaterSet(address indexed updater);

    // ============ Errors ============

    error WalletConcentrationExceeded(address wallet, uint256 currentBps, uint256 maxBps);
    error ModelFamilyConcentrationExceeded(bytes32 modelFamily, uint256 currentBps, uint256 maxBps);
    error SponsorChainTooDeep(address wallet, uint256 depth, uint256 maxDepth);
    error OnlyUpdater();
    error OnlyDeployer();
    error UpdaterAlreadySet();
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientStake(address wallet, uint256 requested, uint256 available);
    error SelfSponsorNotAllowed();

    // ============ Constructor ============

    constructor() {
        deployer = msg.sender;
    }

    // ============ Configuration ============

    /// @notice Set the authorized updater. Can only be set once.
    /// @param _updater Address authorized to record/remove stakes
    function setUpdater(address _updater) external {
        if (msg.sender != deployer) revert OnlyDeployer();
        if (updater != address(0)) revert UpdaterAlreadySet();
        if (_updater == address(0)) revert ZeroAddress();
        updater = _updater;
        emit UpdaterSet(_updater);
    }

    // ============ Stake Tracking ============

    /// @notice Record a new stake, enforcing wallet concentration limit
    /// @param wallet The staker address
    /// @param amount The stake amount
    function recordStake(address wallet, uint256 amount) external {
        _onlyUpdater();
        if (amount == 0) revert ZeroAmount();

        uint256 newWalletStake = walletStake[wallet] + amount;
        uint256 newTotalPool = totalPoolSize + amount;

        // Concentration limits only enforced above minimum pool size (bootstrap period)
        if (newTotalPool >= MIN_POOL_FOR_LIMITS) {
            uint256 walletShareBps = (newWalletStake * BPS_DENOMINATOR) / newTotalPool;
            if (walletShareBps > MAX_WALLET_SHARE_BPS) {
                revert WalletConcentrationExceeded(wallet, walletShareBps, MAX_WALLET_SHARE_BPS);
            }
        }

        walletStake[wallet] = newWalletStake;
        totalPoolSize = newTotalPool;

        emit StakeRecorded(wallet, amount, newWalletStake);
    }

    /// @notice Remove a stake (on withdrawal or resolution)
    /// @param wallet The staker address
    /// @param amount The stake amount to remove
    function removeStake(address wallet, uint256 amount) external {
        _onlyUpdater();
        if (amount == 0) revert ZeroAmount();
        if (walletStake[wallet] < amount) {
            revert InsufficientStake(wallet, amount, walletStake[wallet]);
        }

        walletStake[wallet] -= amount;
        totalPoolSize -= amount;

        emit StakeRemoved(wallet, amount, walletStake[wallet]);
    }

    // ============ Model Family Weight ============

    /// @notice Record verification weight for a model family
    /// @param modelFamily Hash identifier for the model family (e.g., keccak256("GPT-4"))
    /// @param weightIncrease Additional weight to add
    function recordModelWeight(bytes32 modelFamily, uint256 weightIncrease) external {
        _onlyUpdater();

        uint256 newWeight = modelFamilyWeight[modelFamily] + weightIncrease;
        uint256 totalWeight = totalPoolSize; // Approximation: total pool as total weight

        // Only enforce limits above minimum pool size
        if (totalWeight >= MIN_POOL_FOR_LIMITS) {
            uint256 modelShareBps = (newWeight * BPS_DENOMINATOR) / totalWeight;
            if (modelShareBps > MAX_MODEL_FAMILY_WEIGHT_BPS) {
                revert ModelFamilyConcentrationExceeded(
                    modelFamily, modelShareBps, MAX_MODEL_FAMILY_WEIGHT_BPS
                );
            }
        }

        modelFamilyWeight[modelFamily] = newWeight;
        emit ModelWeightUpdated(modelFamily, newWeight);
    }

    /// @notice Remove verification weight for a model family
    /// @param modelFamily Hash identifier for the model family
    /// @param weightDecrease Weight to remove
    function removeModelWeight(bytes32 modelFamily, uint256 weightDecrease) external {
        _onlyUpdater();
        if (modelFamilyWeight[modelFamily] >= weightDecrease) {
            modelFamilyWeight[modelFamily] -= weightDecrease;
        } else {
            modelFamilyWeight[modelFamily] = 0;
        }
        emit ModelWeightUpdated(modelFamily, modelFamilyWeight[modelFamily]);
    }

    // ============ Sponsor Chain ============

    /// @notice Set a sponsor relationship
    /// @param sponsored The sponsored address
    /// @param sponsor The sponsor address
    function setSponsor(address sponsored, address sponsor) external {
        _onlyUpdater();
        if (sponsored == sponsor) revert SelfSponsorNotAllowed();

        // Check chain depth won't exceed limit
        uint256 depth = _getSponsorDepth(sponsor);
        if (depth + 1 > MAX_SPONSOR_DEPTH) {
            revert SponsorChainTooDeep(sponsored, depth + 1, MAX_SPONSOR_DEPTH);
        }

        sponsors[sponsored] = sponsor;
        emit SponsorSet(sponsored, sponsor);
    }

    // ============ Fee Calculation ============

    /// @notice Calculate progressive fee for a wallet based on pool share
    /// @dev Fee is 0 below 1% threshold, then increases linearly
    /// @param wallet The wallet address
    /// @param stakeAmount The amount being staked
    /// @return fee The progressive fee to charge
    function calculateProgressiveFee(address wallet, uint256 stakeAmount)
        external
        view
        returns (uint256 fee)
    {
        if (totalPoolSize == 0) return 0;

        uint256 newStake = walletStake[wallet] + stakeAmount;
        uint256 newPool = totalPoolSize + stakeAmount;
        uint256 shareBps = (newStake * BPS_DENOMINATOR) / newPool;

        if (shareBps <= PROGRESSIVE_FEE_THRESHOLD_BPS) return 0;

        // Fee increases linearly above threshold
        // Each 1% (100 bps) above threshold costs 0.1% (10 bps) of the stake
        uint256 excessBps = shareBps - PROGRESSIVE_FEE_THRESHOLD_BPS;
        fee = (stakeAmount * excessBps * PROGRESSIVE_FEE_RATE_BPS) / (BPS_DENOMINATOR * 100);
    }

    // ============ View Functions ============

    /// @notice Check if a wallet can stake an additional amount
    /// @param wallet The wallet to check
    /// @param additionalStake The amount to add
    /// @return allowed True if within concentration limits
    /// @return currentShareBps Current wallet share in basis points
    /// @return projectedShareBps Projected share after staking
    function canStake(address wallet, uint256 additionalStake)
        external
        view
        returns (bool allowed, uint256 currentShareBps, uint256 projectedShareBps)
    {
        if (totalPoolSize == 0 && additionalStake > 0) {
            return (true, 0, BPS_DENOMINATOR); // First staker
        }

        uint256 newTotal = totalPoolSize + additionalStake;
        currentShareBps = totalPoolSize > 0
            ? (walletStake[wallet] * BPS_DENOMINATOR) / totalPoolSize
            : 0;
        projectedShareBps = (
            (walletStake[wallet] + additionalStake) * BPS_DENOMINATOR
        ) / newTotal;

        allowed = projectedShareBps <= MAX_WALLET_SHARE_BPS;
    }

    /// @notice Check if a model family can take additional weight
    /// @param modelFamily The model family hash
    /// @param additionalWeight Additional weight to check
    /// @return allowed True if within limits
    /// @return currentShareBps Current model family share
    function canAddModelWeight(bytes32 modelFamily, uint256 additionalWeight)
        external
        view
        returns (bool allowed, uint256 currentShareBps)
    {
        if (totalPoolSize == 0) return (true, 0);

        uint256 newWeight = modelFamilyWeight[modelFamily] + additionalWeight;
        currentShareBps = (newWeight * BPS_DENOMINATOR) / totalPoolSize;
        allowed = currentShareBps <= MAX_MODEL_FAMILY_WEIGHT_BPS;
    }

    /// @notice Get the sponsor chain depth for an address
    /// @param wallet The address to check
    /// @return depth The sponsor chain depth (0 = no sponsor)
    function getSponsorDepth(address wallet) external view returns (uint256) {
        return _getSponsorDepth(wallet);
    }

    /// @notice Get the full sponsor chain for an address
    /// @param wallet The address to query
    /// @return chain Array of sponsors (from direct sponsor to root)
    function getSponsorChain(address wallet) external view returns (address[] memory chain) {
        uint256 depth = _getSponsorDepth(wallet);
        chain = new address[](depth);

        address current = wallet;
        for (uint256 i = 0; i < depth; i++) {
            current = sponsors[current];
            chain[i] = current;
        }
    }

    /// @notice Get wallet share of pool in basis points
    /// @param wallet The wallet to check
    /// @return shareBps The wallet's share in basis points
    function getWalletShareBps(address wallet) external view returns (uint256 shareBps) {
        if (totalPoolSize == 0) return 0;
        return (walletStake[wallet] * BPS_DENOMINATOR) / totalPoolSize;
    }

    /// @notice Get model family share of total weight in basis points
    /// @param modelFamily The model family hash
    /// @return shareBps The model family's share in basis points
    function getModelFamilyShareBps(bytes32 modelFamily) external view returns (uint256 shareBps) {
        if (totalPoolSize == 0) return 0;
        return (modelFamilyWeight[modelFamily] * BPS_DENOMINATOR) / totalPoolSize;
    }

    // ============ Internal ============

    function _onlyUpdater() internal view {
        if (msg.sender != updater) revert OnlyUpdater();
    }

    function _getSponsorDepth(address wallet) internal view returns (uint256 depth) {
        address current = wallet;
        while (sponsors[current] != address(0)) {
            depth++;
            current = sponsors[current];
            // Safety: break if we somehow exceed max (circular reference protection)
            if (depth > MAX_SPONSOR_DEPTH + 1) break;
        }
    }
}
