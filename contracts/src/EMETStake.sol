// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {IEMET} from "./interfaces/IEMET.sol";
import {EMETRegistry} from "./EMETRegistry.sol";

/// @title EMETStake - Staking system for EMET Protocol claims
/// @notice Allows anyone to stake EMET tokens in support of existing claims
/// @dev Integrates with EMETRegistry and EMETChallenge for the full protocol
contract EMETStake {
    // ============ Constants ============

    /// @notice EMET token on Base mainnet
    IEMET public constant EMET = IEMET(0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C);

    /// @notice The claim registry
    EMETRegistry public immutable registry;

    // ============ Types ============

    struct StakeInfo {
        uint256 totalFor;      // Total stake supporting the claim
        uint256 totalAgainst;  // Total stake challenging the claim
    }

    // ============ State ============

    /// @notice Total stakes per claim (for/against)
    mapping(uint256 => StakeInfo) public claimStakes;

    /// @notice Individual stakes: claimId => staker => isFor => amount
    mapping(uint256 => mapping(address => mapping(bool => uint256))) public stakes;

    /// @notice Whether a staker has withdrawn from a claim
    mapping(uint256 => mapping(address => bool)) public hasWithdrawn;

    /// @notice Authorized challenge contract
    address public challengeContract;

    // ============ Events ============

    event Staked(
        uint256 indexed claimId,
        address indexed staker,
        uint256 amount,
        bool indexed isFor
    );

    event Withdrawn(
        uint256 indexed claimId,
        address indexed staker,
        uint256 amount,
        uint256 reward
    );

    event ChallengeContractSet(address indexed challengeContract);

    // ============ Errors ============

    error ClaimDoesNotExist(uint256 claimId);
    error ClaimNotActive(uint256 claimId);
    error ClaimNotResolved(uint256 claimId);
    error ZeroAmount();
    error TransferFailed();
    error AlreadyWithdrawn();
    error NoStakeToWithdraw();
    error NotOnWinningSide();
    error ChallengeContractAlreadySet();
    error OnlyChallengeContract();
    error ZeroAddress();
    error CannotStakeOnOwnClaim();

    // ============ Constructor ============

    /// @notice Deploy stake contract linked to registry
    /// @param _registry Address of the EMETRegistry contract
    constructor(address _registry) {
        if (_registry == address(0)) revert ZeroAddress();
        registry = EMETRegistry(_registry);
    }

    // ============ External Functions ============

    /// @notice Set the challenge contract address (can only be done once)
    /// @param _challengeContract Address of the EMETChallenge contract
    function setChallengeContract(address _challengeContract) external {
        if (challengeContract != address(0)) revert ChallengeContractAlreadySet();
        if (_challengeContract == address(0)) revert ZeroAddress();
        challengeContract = _challengeContract;
        emit ChallengeContractSet(_challengeContract);
    }

    /// @notice Stake EMET in support of a claim
    /// @dev Caller must have approved this contract to spend EMET
    /// @param claimId The claim to support
    /// @param amount Amount of EMET to stake
    function stakeFor(uint256 claimId, uint256 amount) external {
        _stake(claimId, amount, true);
    }

    /// @notice Stake EMET against a claim (challenge stake)
    /// @dev Only callable by the challenge contract
    /// @param claimId The claim to stake against
    /// @param staker The address staking
    /// @param amount Amount of EMET to stake
    function stakeAgainst(uint256 claimId, address staker, uint256 amount) external {
        if (msg.sender != challengeContract) revert OnlyChallengeContract();
        if (amount == 0) revert ZeroAmount();

        // Verify claim exists and is challenged
        EMETRegistry.Claim memory claim = registry.getClaim(claimId);
        if (claim.status != EMETRegistry.ClaimStatus.Challenged) {
            revert ClaimNotActive(claimId);
        }

        // Self-stake prevention (defense in depth)
        if (staker == claim.submitter) revert CannotStakeOnOwnClaim();

        // Update stakes
        stakes[claimId][staker][false] += amount;
        claimStakes[claimId].totalAgainst += amount;

        emit Staked(claimId, staker, amount, false);
    }

    /// @notice Withdraw stake and rewards after claim resolution
    /// @dev Winners get their stake back plus proportional share of losers' stake
    /// @param claimId The resolved claim
    function withdraw(uint256 claimId) external {
        if (hasWithdrawn[claimId][msg.sender]) revert AlreadyWithdrawn();

        EMETRegistry.Claim memory claim = registry.getClaim(claimId);
        
        // Must be resolved (Verified, Rejected, or Uncontested)
        if (claim.status != EMETRegistry.ClaimStatus.Verified && 
            claim.status != EMETRegistry.ClaimStatus.Rejected &&
            claim.status != EMETRegistry.ClaimStatus.Uncontested) {
            revert ClaimNotResolved(claimId);
        }

        bool claimVerified = (claim.status == EMETRegistry.ClaimStatus.Verified ||
                              claim.status == EMETRegistry.ClaimStatus.Uncontested);
        
        // Get user's stakes
        uint256 userStakeFor = stakes[claimId][msg.sender][true];
        uint256 userStakeAgainst = stakes[claimId][msg.sender][false];
        
        // Determine winning stake
        uint256 winningStake;
        if (claimVerified) {
            winningStake = userStakeFor;
        } else {
            winningStake = userStakeAgainst;
        }
        
        if (winningStake == 0) {
            // User might be the original submitter
            if (msg.sender == claim.submitter && claimVerified) {
                // Submitter gets their stake back (handled by challenge contract)
                revert NoStakeToWithdraw();
            }
            revert NotOnWinningSide();
        }

        hasWithdrawn[claimId][msg.sender] = true;

        // Calculate reward
        StakeInfo memory info = claimStakes[claimId];
        uint256 totalWinning = claimVerified ? info.totalFor : info.totalAgainst;
        uint256 totalLosing = claimVerified ? info.totalAgainst : info.totalFor;
        
        // Include original claim stake in the pool
        if (claimVerified) {
            // Claim verified: submitter's stake returned separately, 
            // supporters split challenger stakes
        } else {
            // Claim rejected: challengers split submitter's stake + supporter stakes
            totalLosing += claim.stake;
        }

        // Proportional reward from losing side
        uint256 reward = 0;
        if (totalWinning > 0 && totalLosing > 0) {
            reward = (winningStake * totalLosing) / totalWinning;
        }

        uint256 totalPayout = winningStake + reward;

        // Transfer
        bool success = EMET.transfer(msg.sender, totalPayout);
        if (!success) revert TransferFailed();

        emit Withdrawn(claimId, msg.sender, winningStake, reward);
    }

    // ============ Internal Functions ============

    function _stake(uint256 claimId, uint256 amount, bool isFor) internal {
        if (amount == 0) revert ZeroAmount();

        // Verify claim exists and is stakeable
        EMETRegistry.Claim memory claim = registry.getClaim(claimId);

        // Self-stake prevention: cannot stake on own claim
        if (msg.sender == claim.submitter) revert CannotStakeOnOwnClaim();
        
        // Can only stake FOR on active or challenged claims
        if (isFor) {
            if (claim.status != EMETRegistry.ClaimStatus.Active && 
                claim.status != EMETRegistry.ClaimStatus.Challenged) {
                revert ClaimNotActive(claimId);
            }
            // If challenged, check we're still in challenge period
            if (claim.status == EMETRegistry.ClaimStatus.Challenged) {
                if (block.timestamp > claim.challengeEnd) {
                    revert ClaimNotActive(claimId);
                }
            }
        }

        // Transfer tokens
        bool success = EMET.transferFrom(msg.sender, address(this), amount);
        if (!success) revert TransferFailed();

        // Update stakes
        stakes[claimId][msg.sender][isFor] += amount;
        if (isFor) {
            claimStakes[claimId].totalFor += amount;
        } else {
            claimStakes[claimId].totalAgainst += amount;
        }

        emit Staked(claimId, msg.sender, amount, isFor);
    }

    // ============ View Functions ============

    /// @notice Get stake totals for a claim
    /// @param claimId The claim ID
    /// @return totalFor Total stake supporting the claim
    /// @return totalAgainst Total stake challenging the claim
    function getStakeTotals(uint256 claimId) 
        external 
        view 
        returns (uint256 totalFor, uint256 totalAgainst) 
    {
        StakeInfo memory info = claimStakes[claimId];
        return (info.totalFor, info.totalAgainst);
    }

    /// @notice Get a user's stakes on a claim
    /// @param claimId The claim ID
    /// @param staker The staker address
    /// @return userStakeFor Amount staked in support
    /// @return userStakeAgainst Amount staked against
    function getUserStakes(uint256 claimId, address staker)
        external
        view
        returns (uint256 userStakeFor, uint256 userStakeAgainst)
    {
        return (
            stakes[claimId][staker][true],
            stakes[claimId][staker][false]
        );
    }

    /// @notice Calculate expected payout for a staker if claim resolves now
    /// @param claimId The claim ID
    /// @param staker The staker address
    /// @param assumeVerified Assume claim is verified (true) or rejected (false)
    /// @return payout Expected total payout
    function calculatePayout(uint256 claimId, address staker, bool assumeVerified)
        external
        view
        returns (uint256 payout)
    {
        uint256 stakerFor = stakes[claimId][staker][true];
        uint256 stakerAgainst = stakes[claimId][staker][false];
        
        uint256 winningStake = assumeVerified ? stakerFor : stakerAgainst;
        if (winningStake == 0) return 0;

        StakeInfo memory info = claimStakes[claimId];
        uint256 totalWinning = assumeVerified ? info.totalFor : info.totalAgainst;
        uint256 totalLosing = assumeVerified ? info.totalAgainst : info.totalFor;

        // Include claim stake if rejected
        if (!assumeVerified) {
            totalLosing += registry.getClaimStake(claimId);
        }

        uint256 reward = 0;
        if (totalWinning > 0 && totalLosing > 0) {
            reward = (winningStake * totalLosing) / totalWinning;
        }

        return winningStake + reward;
    }
}
