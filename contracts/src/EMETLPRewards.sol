// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {IEMET} from "./interfaces/IEMET.sol";
import {INonfungiblePositionManager, IERC721Receiver} from "./interfaces/IUniswapV3.sol";

/// @title EMETLPRewards - Reward Uniswap V3 LP providers for EMET/ETH liquidity
/// @notice Stake your Uniswap V3 LP NFTs to earn EMET rewards from protocol fees.
///         Rewards are distributed proportionally based on liquidity share.
/// @dev Uses a "reward per share" accumulator pattern for gas-efficient distribution.
///      Only positions for the correct EMET/WETH pool and fee tier are accepted.
///
///      Flow:
///      1. Treasury sends EMET to this contract via distributeRewards()
///      2. LP providers stake their Uni V3 NFTs via stake(tokenId)
///      3. Rewards accrue proportionally to liquidity
///      4. LP providers claim() accumulated rewards anytime
///      5. LP providers unstake() to get their NFT back
contract EMETLPRewards is IERC721Receiver {
    // ============ Constants ============

    /// @notice EMET token
    IEMET public constant EMET = IEMET(0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C);

    /// @notice Precision for reward-per-share accumulator
    uint256 public constant PRECISION = 1e36;

    // ============ Immutables ============

    /// @notice Uniswap V3 NonfungiblePositionManager
    INonfungiblePositionManager public immutable positionManager;

    /// @notice EMET token address (for pool validation)
    address public immutable emetToken;

    /// @notice WETH address on Base (for pool validation)
    address public immutable weth;

    /// @notice Required fee tier for accepted positions (e.g. 3000 = 0.3%)
    uint24 public immutable requiredFeeTier;

    /// @notice Treasury contract that distributes rewards
    address public immutable treasury;

    // ============ Types ============

    struct StakedPosition {
        address owner;       // Original depositor
        uint128 liquidity;   // Liquidity snapshot at stake time
        uint256 rewardDebt;  // Reward debt for accumulator pattern
    }

    // ============ State ============

    /// @notice Staked position data by token ID
    mapping(uint256 => StakedPosition) public stakedPositions;

    /// @notice Token IDs staked by each address
    mapping(address => uint256[]) internal _userTokenIds;

    /// @notice Accumulated reward per unit of liquidity (scaled by PRECISION)
    uint256 public accRewardPerShare;

    /// @notice Total liquidity staked across all positions
    uint256 public totalLiquidity;

    /// @notice Total rewards ever distributed
    uint256 public totalRewardsDistributed;

    /// @notice Pending rewards per user (accumulated but not yet claimed)
    mapping(address => uint256) public pendingRewards;

    // ============ Events ============

    /// @notice LP NFT staked
    event Staked(address indexed owner, uint256 indexed tokenId, uint128 liquidity);

    /// @notice LP NFT unstaked
    event Unstaked(address indexed owner, uint256 indexed tokenId, uint128 liquidity);

    /// @notice Rewards claimed by user
    event RewardsClaimed(address indexed user, uint256 amount);

    /// @notice New rewards distributed to the pool
    event RewardsDistributed(uint256 amount, uint256 newAccRewardPerShare);

    // ============ Errors ============

    error NotPositionOwner(uint256 tokenId, address caller);
    error PositionNotStaked(uint256 tokenId);
    error InvalidPool(address token0, address token1, uint24 fee);
    error ZeroLiquidity(uint256 tokenId);
    error NoRewardsToClaim();
    error OnlyTreasury();
    error TransferFailed();
    error ZeroAmount();

    // ============ Constructor ============

    /// @notice Deploy LP rewards contract
    /// @param _positionManager Uniswap V3 NonfungiblePositionManager address
    /// @param _emetToken EMET token address (for pool validation)
    /// @param _weth WETH address on Base
    /// @param _feeTier Required Uniswap V3 fee tier (e.g. 3000 for 0.3%)
    /// @param _treasury EMETTreasury address (authorized reward distributor)
    constructor(
        address _positionManager,
        address _emetToken,
        address _weth,
        uint24 _feeTier,
        address _treasury
    ) {
        positionManager = INonfungiblePositionManager(_positionManager);
        emetToken = _emetToken;
        weth = _weth;
        requiredFeeTier = _feeTier;
        treasury = _treasury;
    }

    // ============ ERC721 Receiver ============

    /// @notice Required to receive Uniswap V3 NFTs via safeTransferFrom
    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }

    // ============ Staking ============

    /// @notice Stake a Uniswap V3 LP NFT to earn EMET rewards
    /// @dev Caller must own the NFT and approve this contract first.
    ///      Only positions for the correct EMET/WETH pool are accepted.
    /// @param tokenId The Uniswap V3 NFT token ID
    function stake(uint256 tokenId) external {
        // Validate the position is for the correct pool
        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            ,
            ,
            uint128 liquidity,
            ,
            ,
            ,
        ) = positionManager.positions(tokenId);

        // Check pool matches EMET/WETH (tokens could be in either order)
        bool validPool = (
            (token0 == emetToken && token1 == weth)
                || (token0 == weth && token1 == emetToken)
        ) && fee == requiredFeeTier;

        if (!validPool) revert InvalidPool(token0, token1, fee);
        if (liquidity == 0) revert ZeroLiquidity(tokenId);

        // Transfer NFT from caller to this contract
        positionManager.transferFrom(msg.sender, address(this), tokenId);

        // Update pending rewards for existing positions before changing liquidity
        _updatePendingRewards(msg.sender);

        // Record the staked position
        stakedPositions[tokenId] = StakedPosition({
            owner: msg.sender,
            liquidity: liquidity,
            rewardDebt: (uint256(liquidity) * accRewardPerShare) / PRECISION
        });

        _userTokenIds[msg.sender].push(tokenId);
        totalLiquidity += uint256(liquidity);

        emit Staked(msg.sender, tokenId, liquidity);
    }

    /// @notice Unstake a Uniswap V3 LP NFT and collect pending rewards
    /// @param tokenId The staked NFT token ID
    function unstake(uint256 tokenId) external {
        StakedPosition memory pos = stakedPositions[tokenId];
        if (pos.owner != msg.sender) revert NotPositionOwner(tokenId, msg.sender);

        // Update pending rewards
        _updatePendingRewards(msg.sender);

        // Remove from total liquidity
        totalLiquidity -= uint256(pos.liquidity);

        // Remove from user's token list
        _removeTokenId(msg.sender, tokenId);

        // Clear position data
        delete stakedPositions[tokenId];

        // Transfer NFT back to owner
        positionManager.transferFrom(address(this), msg.sender, tokenId);

        emit Unstaked(msg.sender, tokenId, pos.liquidity);
    }

    /// @notice Claim all accumulated EMET rewards
    function claim() external {
        _updatePendingRewards(msg.sender);

        uint256 reward = pendingRewards[msg.sender];
        if (reward == 0) revert NoRewardsToClaim();

        pendingRewards[msg.sender] = 0;

        bool success = EMET.transfer(msg.sender, reward);
        if (!success) revert TransferFailed();

        emit RewardsClaimed(msg.sender, reward);
    }

    // ============ Reward Distribution ============

    /// @notice Distribute EMET rewards to the staking pool
    /// @dev Called by treasury. EMET must already be transferred to this contract.
    /// @param amount Amount of EMET to distribute
    function distributeRewards(uint256 amount) external {
        if (msg.sender != treasury) revert OnlyTreasury();
        if (amount == 0) revert ZeroAmount();

        if (totalLiquidity > 0) {
            accRewardPerShare += (amount * PRECISION) / totalLiquidity;
        }
        // If no liquidity staked, rewards stay in contract for future stakers

        totalRewardsDistributed += amount;

        emit RewardsDistributed(amount, accRewardPerShare);
    }

    // ============ Internal ============

    /// @notice Update pending rewards for a user based on their current positions
    function _updatePendingRewards(address user) internal {
        uint256[] storage tokenIds = _userTokenIds[user];
        uint256 pending = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            StakedPosition storage pos = stakedPositions[tokenIds[i]];
            uint256 accumulated = (uint256(pos.liquidity) * accRewardPerShare) / PRECISION;
            if (accumulated > pos.rewardDebt) {
                pending += accumulated - pos.rewardDebt;
            }
            pos.rewardDebt = accumulated;
        }

        pendingRewards[user] += pending;
    }

    /// @notice Remove a token ID from a user's list
    function _removeTokenId(address user, uint256 tokenId) internal {
        uint256[] storage ids = _userTokenIds[user];
        for (uint256 i = 0; i < ids.length; i++) {
            if (ids[i] == tokenId) {
                ids[i] = ids[ids.length - 1];
                ids.pop();
                return;
            }
        }
    }

    // ============ View Functions ============

    /// @notice Get all staked token IDs for a user
    /// @param user The user address
    /// @return tokenIds Array of staked NFT token IDs
    function getUserStakedTokens(address user)
        external
        view
        returns (uint256[] memory tokenIds)
    {
        return _userTokenIds[user];
    }

    /// @notice Get total liquidity staked by a user
    /// @param user The user address
    /// @return liquidity Total liquidity across all staked positions
    function getUserLiquidity(address user) external view returns (uint256 liquidity) {
        uint256[] storage tokenIds = _userTokenIds[user];
        for (uint256 i = 0; i < tokenIds.length; i++) {
            liquidity += uint256(stakedPositions[tokenIds[i]].liquidity);
        }
    }

    /// @notice Calculate claimable rewards for a user
    /// @param user The user address
    /// @return reward Claimable EMET amount
    function claimableRewards(address user) external view returns (uint256 reward) {
        reward = pendingRewards[user];
        uint256[] storage tokenIds = _userTokenIds[user];

        for (uint256 i = 0; i < tokenIds.length; i++) {
            StakedPosition storage pos = stakedPositions[tokenIds[i]];
            uint256 accumulated = (uint256(pos.liquidity) * accRewardPerShare) / PRECISION;
            if (accumulated > pos.rewardDebt) {
                reward += accumulated - pos.rewardDebt;
            }
        }
    }

    /// @notice Number of staked positions
    /// @param user The user address
    /// @return count Number of staked NFTs
    function stakedPositionCount(address user) external view returns (uint256 count) {
        return _userTokenIds[user].length;
    }
}
