// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {IEMET} from "./interfaces/IEMET.sol";
import {EMETRegistry} from "./EMETRegistry.sol";
import {EMETStake} from "./EMETStake.sol";

/// @title EMETChallenge - Challenge and dispute mechanism for EMET Protocol
/// @notice Allows challenging claims with stake, resolution by stake-weighted voting
/// @dev Trustless dispute resolution - no admin intervention
contract EMETChallenge {
    // ============ Constants ============

    /// @notice EMET token on Base mainnet
    IEMET public constant EMET = IEMET(0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C);

    /// @notice The claim registry
    EMETRegistry public immutable registry;

    /// @notice The staking contract
    EMETStake public immutable stakeContract;

    /// @notice Minimum stake required to initiate a challenge
    uint256 public immutable minimumChallengeStake;

    // ============ Types ============

    struct Challenge {
        address challenger;     // Who initiated the challenge
        uint256 stake;         // Initial challenge stake
        uint256 startTime;     // When challenge was initiated
        bool resolved;         // Whether challenge has been resolved
    }

    // ============ State ============

    /// @notice Challenges by claim ID
    mapping(uint256 => Challenge) public challenges;

    // ============ Events ============

    event ChallengeInitiated(
        uint256 indexed claimId,
        address indexed challenger,
        uint256 stake,
        uint256 challengeEnd
    );

    event ChallengeResolved(
        uint256 indexed claimId,
        bool indexed claimVerified,
        uint256 totalFor,
        uint256 totalAgainst
    );

    event StakeAddedToChallenge(
        uint256 indexed claimId,
        address indexed staker,
        uint256 amount,
        bool indexed isFor
    );

    // ============ Errors ============

    error ClaimDoesNotExist(uint256 claimId);
    error ClaimNotActive(uint256 claimId);
    error ClaimNotChallenged(uint256 claimId);
    error ChallengeAlreadyExists(uint256 claimId);
    error ChallengePeriodNotEnded(uint256 claimId, uint256 endsAt);
    error ChallengeAlreadyResolved(uint256 claimId);
    error InsufficientStake(uint256 provided, uint256 required);
    error TransferFailed();
    error ZeroAmount();
    error CannotChallengeOwnClaim();

    // ============ Constructor ============

    /// @notice Deploy challenge contract linked to registry and stake contracts
    /// @param _registry Address of EMETRegistry
    /// @param _stakeContract Address of EMETStake
    /// @param _minimumChallengeStake Minimum EMET to initiate a challenge
    constructor(
        address _registry,
        address _stakeContract,
        uint256 _minimumChallengeStake
    ) {
        registry = EMETRegistry(_registry);
        stakeContract = EMETStake(_stakeContract);
        minimumChallengeStake = _minimumChallengeStake;
    }

    // ============ External Functions ============

    /// @notice Initiate a challenge against an active claim
    /// @dev Caller must have approved this contract to spend EMET
    /// @param claimId The claim to challenge
    /// @param stake Amount of EMET to stake against the claim
    function initiateChallenge(uint256 claimId, uint256 stake) external {
        if (stake < minimumChallengeStake) {
            revert InsufficientStake(stake, minimumChallengeStake);
        }

        // Verify claim exists and is active
        EMETRegistry.Claim memory claim = registry.getClaim(claimId);
        if (claim.status != EMETRegistry.ClaimStatus.Active) {
            revert ClaimNotActive(claimId);
        }

        // Cannot challenge your own claim
        if (claim.submitter == msg.sender) {
            revert CannotChallengeOwnClaim();
        }

        // Check no existing challenge
        if (challenges[claimId].challenger != address(0)) {
            revert ChallengeAlreadyExists(claimId);
        }

        // Transfer stake from challenger to stake contract
        bool success = EMET.transferFrom(msg.sender, address(stakeContract), stake);
        if (!success) revert TransferFailed();

        // Record challenge
        challenges[claimId] = Challenge({
            challenger: msg.sender,
            stake: stake,
            startTime: block.timestamp,
            resolved: false
        });

        // Mark claim as challenged in registry
        registry.markChallenged(claimId);

        // Register stake in stake contract
        stakeContract.stakeAgainst(claimId, msg.sender, stake);

        // Get updated claim for challenge end time
        claim = registry.getClaim(claimId);

        emit ChallengeInitiated(claimId, msg.sender, stake, claim.challengeEnd);
    }

    /// @notice Add stake to support a challenged claim
    /// @param claimId The challenged claim to support
    /// @param amount Amount of EMET to stake in support
    function stakeForClaim(uint256 claimId, uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        EMETRegistry.Claim memory claim = registry.getClaim(claimId);
        if (claim.status != EMETRegistry.ClaimStatus.Challenged) {
            revert ClaimNotChallenged(claimId);
        }

        // Check still in challenge period
        if (block.timestamp > claim.challengeEnd) {
            revert ChallengePeriodNotEnded(claimId, claim.challengeEnd);
        }

        // Transfer and stake via stake contract
        stakeContract.stakeFor(claimId, amount);

        emit StakeAddedToChallenge(claimId, msg.sender, amount, true);
    }

    /// @notice Add stake against a challenged claim
    /// @param claimId The challenged claim to oppose
    /// @param amount Amount of EMET to stake against
    function stakeAgainstClaim(uint256 claimId, uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        EMETRegistry.Claim memory claim = registry.getClaim(claimId);
        if (claim.status != EMETRegistry.ClaimStatus.Challenged) {
            revert ClaimNotChallenged(claimId);
        }

        // Check still in challenge period
        if (block.timestamp > claim.challengeEnd) {
            revert ChallengePeriodNotEnded(claimId, claim.challengeEnd);
        }

        // Transfer stake to stake contract
        bool success = EMET.transferFrom(msg.sender, address(stakeContract), amount);
        if (!success) revert TransferFailed();

        // Register stake
        stakeContract.stakeAgainst(claimId, msg.sender, amount);

        emit StakeAddedToChallenge(claimId, msg.sender, amount, false);
    }

    /// @notice Resolve a challenge after the challenge period ends
    /// @dev Anyone can call this to finalize the dispute
    /// @param claimId The claim with an expired challenge
    function resolveChallenge(uint256 claimId) external {
        Challenge storage challenge = challenges[claimId];
        if (challenge.challenger == address(0)) {
            revert ClaimNotChallenged(claimId);
        }
        if (challenge.resolved) {
            revert ChallengeAlreadyResolved(claimId);
        }

        EMETRegistry.Claim memory claim = registry.getClaim(claimId);
        if (claim.status != EMETRegistry.ClaimStatus.Challenged) {
            revert ClaimNotChallenged(claimId);
        }

        // Must be past challenge end
        if (block.timestamp < claim.challengeEnd) {
            revert ChallengePeriodNotEnded(claimId, claim.challengeEnd);
        }

        challenge.resolved = true;

        // Get stake totals
        (uint256 totalFor, uint256 totalAgainst) = stakeContract.getStakeTotals(claimId);
        
        // Add original claim stake to "for" side
        uint256 claimStake = claim.stake;
        uint256 effectiveFor = totalFor + claimStake;

        // Determine winner: side with more stake wins
        // If tie, claim is verified (benefit of doubt to submitter)
        bool claimVerified = effectiveFor >= totalAgainst;

        // Resolve in registry (handles stake distribution)
        registry.resolveClaim(claimId, claimVerified, address(stakeContract));

        // Losers' stakes are distributed via stake contract's withdraw function

        emit ChallengeResolved(claimId, claimVerified, effectiveFor, totalAgainst);
    }

    // ============ View Functions ============

    /// @notice Get challenge details
    /// @param claimId The claim ID
    /// @return challenger Address that initiated challenge
    /// @return stake Initial challenge stake
    /// @return startTime When challenge started
    /// @return resolved Whether challenge is resolved
    function getChallenge(uint256 claimId)
        external
        view
        returns (
            address challenger,
            uint256 stake,
            uint256 startTime,
            bool resolved
        )
    {
        Challenge memory c = challenges[claimId];
        return (c.challenger, c.stake, c.startTime, c.resolved);
    }

    /// @notice Check if a challenge can be resolved
    /// @param claimId The claim ID
    /// @return resolvable True if challenge exists and period has ended
    function canResolve(uint256 claimId) external view returns (bool resolvable) {
        Challenge memory challenge = challenges[claimId];
        if (challenge.challenger == address(0)) return false;
        if (challenge.resolved) return false;

        EMETRegistry.Claim memory claim = registry.getClaim(claimId);
        if (claim.status != EMETRegistry.ClaimStatus.Challenged) return false;

        return block.timestamp >= claim.challengeEnd;
    }

    /// @notice Get current stake comparison for a challenged claim
    /// @param claimId The claim ID
    /// @return effectiveFor Total effective stake for claim (including submitter)
    /// @return totalAgainst Total stake against claim
    /// @return currentWinner "for" or "against" based on current stakes
    function getCurrentStanding(uint256 claimId)
        external
        view
        returns (
            uint256 effectiveFor,
            uint256 totalAgainst,
            string memory currentWinner
        )
    {
        (uint256 totalFor, uint256 against) = stakeContract.getStakeTotals(claimId);
        uint256 claimStake = registry.getClaimStake(claimId);
        
        effectiveFor = totalFor + claimStake;
        totalAgainst = against;
        
        if (effectiveFor >= totalAgainst) {
            currentWinner = "for";
        } else {
            currentWinner = "against";
        }
    }
}
