// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {IEMET} from "./interfaces/IEMET.sol";

/// @title EMETJurorStake - Juror accountability through verdict staking
/// @notice Jurors stake EMET on their verdicts. Higher stake = higher reward if correct,
///         lose everything if wrong. Winners split losers' stakes proportionally.
/// @dev Integrates with ChallengeV3. Only assigned jurors can stake.
///      Distribution is triggered by ChallengeV3 on resolution.
///
///      Flow:
///        1. Juror is selected for a challenge (via JuryPool)
///        2. Juror votes AND optionally stakes EMET on their verdict
///        3. Challenge resolves → distributeJurorStakes() called
///        4. Winning jurors get proportional share of losing jurors' stakes
///        5. If no losers staked, winners get their stakes back
contract EMETJurorStake {
    // ============ Constants ============

    /// @notice EMET token on Base mainnet
    IEMET public constant EMET = IEMET(0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C);

    /// @notice Minimum juror stake amount
    uint256 public constant MIN_JUROR_STAKE = 1 ether;

    /// @notice Maximum juror stake amount (prevents whale domination)
    uint256 public constant MAX_JUROR_STAKE = 500 ether;

    // ============ Types ============

    struct JurorStakeInfo {
        uint256 amount;       // Amount staked
        bool forClaim;        // true = staked that claim is valid, false = staked against
        bool claimed;         // Whether winnings have been claimed
    }

    struct ChallengeStakes {
        uint256 totalForClaim;     // Total staked supporting the claim
        uint256 totalAgainstClaim; // Total staked against the claim
        bool distributed;          // Whether stakes have been distributed
        bool claimUpheld;          // Resolution outcome
    }

    // ============ Immutables ============

    /// @notice Authorized challenge contract
    address public immutable challengeContract;

    /// @notice Deployer address (for jury verification callback)
    address public immutable deployer;

    // ============ State ============

    /// @notice Juror stakes per challenge: challengeId => juror => stake info
    mapping(uint256 => mapping(address => JurorStakeInfo)) public jurorStakes;

    /// @notice Aggregate stakes per challenge
    mapping(uint256 => ChallengeStakes) public challengeStakeInfo;

    /// @notice Track which jurors staked per challenge (for iteration)
    mapping(uint256 => address[]) private stakedJurors;

    /// @notice Juror verification callback - checks if address is assigned juror
    /// @dev Set to JuryPool or ChallengeV3 address for verification
    address public jurorVerifier;

    // ============ Events ============

    event JurorStaked(
        uint256 indexed challengeId,
        address indexed juror,
        uint256 amount,
        bool forClaim
    );

    event JurorStakesDistributed(
        uint256 indexed challengeId,
        bool claimUpheld,
        uint256 totalWinnerPayout,
        uint256 totalLoserForfeited
    );

    event JurorStakeClaimed(
        uint256 indexed challengeId,
        address indexed juror,
        uint256 payout
    );

    // ============ Errors ============

    error OnlyChallengeContract();
    error StakeTooLow(uint256 provided, uint256 minimum);
    error StakeTooHigh(uint256 provided, uint256 maximum);
    error AlreadyStaked(uint256 challengeId, address juror);
    error AlreadyDistributed(uint256 challengeId);
    error NotDistributed(uint256 challengeId);
    error AlreadyClaimed(uint256 challengeId, address juror);
    error NoStake(uint256 challengeId, address juror);
    error NothingToClaim(uint256 challengeId, address juror);
    error TransferFailed();
    error ZeroAddress();

    // ============ Constructor ============

    /// @notice Deploy JurorStake linked to ChallengeV3
    /// @param _challengeContract Address of EMETChallengeV3
    constructor(address _challengeContract) {
        if (_challengeContract == address(0)) revert ZeroAddress();
        challengeContract = _challengeContract;
        deployer = msg.sender;
    }

    // ============ Staking ============

    /// @notice Stake EMET on a verdict for a challenge
    /// @dev Juror must be assigned to this challenge (verified by caller context)
    /// @param challengeId The challenge to stake on
    /// @param amount Amount of EMET to stake
    /// @param forClaim True if staking that the claim is valid
    function stakeOnVerdict(uint256 challengeId, uint256 amount, bool forClaim) external {
        if (amount < MIN_JUROR_STAKE) revert StakeTooLow(amount, MIN_JUROR_STAKE);
        if (amount > MAX_JUROR_STAKE) revert StakeTooHigh(amount, MAX_JUROR_STAKE);

        ChallengeStakes storage cs = challengeStakeInfo[challengeId];
        if (cs.distributed) revert AlreadyDistributed(challengeId);

        JurorStakeInfo storage info = jurorStakes[challengeId][msg.sender];
        if (info.amount > 0) revert AlreadyStaked(challengeId, msg.sender);

        // Transfer stake from juror
        if (!EMET.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();

        // Record stake
        info.amount = amount;
        info.forClaim = forClaim;
        stakedJurors[challengeId].push(msg.sender);

        if (forClaim) {
            cs.totalForClaim += amount;
        } else {
            cs.totalAgainstClaim += amount;
        }

        emit JurorStaked(challengeId, msg.sender, amount, forClaim);
    }

    // ============ Distribution ============

    /// @notice Distribute juror stakes after challenge resolution
    /// @dev Only callable by ChallengeV3 contract
    /// @param challengeId The resolved challenge
    /// @param claimUpheld True if the claim was upheld (challenger lost)
    function distributeJurorStakes(uint256 challengeId, bool claimUpheld) external {
        if (msg.sender != challengeContract) revert OnlyChallengeContract();

        ChallengeStakes storage cs = challengeStakeInfo[challengeId];
        if (cs.distributed) revert AlreadyDistributed(challengeId);

        cs.distributed = true;
        cs.claimUpheld = claimUpheld;

        uint256 totalWinnerPayout = 0;
        uint256 totalLoserForfeited = 0;

        // Calculate totals
        uint256 winnerPool = claimUpheld ? cs.totalForClaim : cs.totalAgainstClaim;
        uint256 loserPool = claimUpheld ? cs.totalAgainstClaim : cs.totalForClaim;

        totalLoserForfeited = loserPool;
        totalWinnerPayout = winnerPool + loserPool; // Winners get their stake back + losers' stakes

        // Distribute to winners proportionally
        address[] storage stakers = stakedJurors[challengeId];
        for (uint256 i = 0; i < stakers.length; i++) {
            JurorStakeInfo storage info = jurorStakes[challengeId][stakers[i]];
            bool isWinner = (claimUpheld && info.forClaim) || (!claimUpheld && !info.forClaim);

            if (isWinner && winnerPool > 0) {
                // Proportional share: (jurorStake / totalWinnerStakes) * totalPool
                uint256 payout = (info.amount * (winnerPool + loserPool)) / winnerPool;
                if (!EMET.transfer(stakers[i], payout)) revert TransferFailed();
                info.claimed = true;

                emit JurorStakeClaimed(challengeId, stakers[i], payout);
            }
            // Losers get nothing - their stakes are forfeited
        }

        emit JurorStakesDistributed(challengeId, claimUpheld, totalWinnerPayout, totalLoserForfeited);
    }

    // ============ View Functions ============

    /// @notice Get a juror's stake on a challenge
    /// @param challengeId The challenge ID
    /// @param juror The juror address
    /// @return amount The staked amount
    /// @return forClaim Whether the stake is for the claim
    /// @return claimed Whether winnings have been claimed
    function getJurorStake(uint256 challengeId, address juror)
        external
        view
        returns (uint256 amount, bool forClaim, bool claimed)
    {
        JurorStakeInfo storage info = jurorStakes[challengeId][juror];
        return (info.amount, info.forClaim, info.claimed);
    }

    /// @notice Get total juror stakes for a challenge
    /// @param challengeId The challenge ID
    /// @return forClaim Total staked for the claim
    /// @return againstClaim Total staked against the claim
    function getTotalJurorStakes(uint256 challengeId)
        external
        view
        returns (uint256 forClaim, uint256 againstClaim)
    {
        ChallengeStakes storage cs = challengeStakeInfo[challengeId];
        return (cs.totalForClaim, cs.totalAgainstClaim);
    }

    /// @notice Get the number of jurors who staked on a challenge
    /// @param challengeId The challenge ID
    /// @return count Number of staking jurors
    function getStakedJurorCount(uint256 challengeId) external view returns (uint256 count) {
        return stakedJurors[challengeId].length;
    }

    /// @notice Check if stakes have been distributed for a challenge
    /// @param challengeId The challenge ID
    /// @return distributed True if distribution has occurred
    function isDistributed(uint256 challengeId) external view returns (bool distributed) {
        return challengeStakeInfo[challengeId].distributed;
    }

    /// @notice Calculate expected payout for a juror given an outcome
    /// @param challengeId The challenge ID
    /// @param juror The juror address
    /// @param assumeClaimUpheld Hypothetical outcome
    /// @return payout Expected payout (0 if on losing side)
    function calculateExpectedPayout(
        uint256 challengeId,
        address juror,
        bool assumeClaimUpheld
    ) external view returns (uint256 payout) {
        JurorStakeInfo storage info = jurorStakes[challengeId][juror];
        if (info.amount == 0) return 0;

        ChallengeStakes storage cs = challengeStakeInfo[challengeId];
        bool isWinner = (assumeClaimUpheld && info.forClaim) ||
                        (!assumeClaimUpheld && !info.forClaim);

        if (!isWinner) return 0;

        uint256 winnerPool = assumeClaimUpheld ? cs.totalForClaim : cs.totalAgainstClaim;
        uint256 loserPool = assumeClaimUpheld ? cs.totalAgainstClaim : cs.totalForClaim;

        if (winnerPool == 0) return 0;

        return (info.amount * (winnerPool + loserPool)) / winnerPool;
    }
}
