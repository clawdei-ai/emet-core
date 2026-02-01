// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {IEMET} from "./interfaces/IEMET.sol";

/// @title EMETRegistry - Trustless claim registry for the EMET Protocol
/// @notice Agents submit claims with evidence, staking EMET tokens as collateral
/// @dev Claims can be challenged via EMETChallenge contract. No admin functions.
contract EMETRegistry {
    // ============ Constants ============

    /// @notice EMET token on Base mainnet
    IEMET public constant EMET = IEMET(0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C);

    /// @notice Minimum stake required to submit a claim (immutable after deployment)
    uint256 public immutable minimumStake;

    /// @notice Challenge period duration (immutable after deployment)
    uint256 public immutable challengePeriod;

    // ============ Types ============

    enum ClaimStatus {
        Active,      // Open for challenges
        Challenged,  // Currently being disputed
        Verified,    // Resolved in favor of claim
        Rejected     // Resolved against claim
    }

    struct Claim {
        bytes32 claimHash;       // Hash of the claim content
        string evidenceURI;      // IPFS/Arweave URI to evidence
        address submitter;       // Address that submitted the claim
        uint256 timestamp;       // When claim was submitted
        uint256 stake;           // EMET staked by submitter
        uint256 challengeEnd;    // Timestamp when challenge period ends (0 if not challenged)
        ClaimStatus status;      // Current status
    }

    // ============ State ============

    /// @notice All claims indexed by unique ID
    mapping(uint256 => Claim) public claims;

    /// @notice Total number of claims
    uint256 public claimCount;

    /// @notice Authorized challenge contract (set once, immutable pattern)
    address public challengeContract;

    // ============ Events ============

    event ClaimSubmitted(
        uint256 indexed claimId,
        bytes32 indexed claimHash,
        address indexed submitter,
        string evidenceURI,
        uint256 stake,
        uint256 timestamp
    );

    event ClaimStatusChanged(
        uint256 indexed claimId,
        ClaimStatus indexed oldStatus,
        ClaimStatus indexed newStatus
    );

    event ChallengeContractSet(address indexed challengeContract);

    // ============ Errors ============

    error InsufficientStake(uint256 provided, uint256 required);
    error ClaimDoesNotExist(uint256 claimId);
    error InvalidStatus(uint256 claimId, ClaimStatus current, ClaimStatus required);
    error TransferFailed();
    error ChallengeContractAlreadySet();
    error OnlyChallengeContract();
    error ZeroAddress();

    // ============ Constructor ============

    /// @notice Deploy registry with immutable parameters
    /// @param _minimumStake Minimum EMET required to submit a claim
    /// @param _challengePeriod Duration of challenge period in seconds
    constructor(uint256 _minimumStake, uint256 _challengePeriod) {
        minimumStake = _minimumStake;
        challengePeriod = _challengePeriod;
    }

    // ============ External Functions ============

    /// @notice Set the challenge contract address (can only be done once)
    /// @dev This creates a trustless link between Registry and Challenge contracts
    /// @param _challengeContract Address of the EMETChallenge contract
    function setChallengeContract(address _challengeContract) external {
        if (challengeContract != address(0)) revert ChallengeContractAlreadySet();
        if (_challengeContract == address(0)) revert ZeroAddress();
        challengeContract = _challengeContract;
        emit ChallengeContractSet(_challengeContract);
    }

    /// @notice Submit a new claim with evidence
    /// @dev Caller must have approved this contract to spend at least `stake` EMET
    /// @param claimHash Keccak256 hash of the claim content
    /// @param evidenceURI URI pointing to evidence (IPFS, Arweave, etc.)
    /// @param stake Amount of EMET to stake (must be >= minimumStake)
    /// @return claimId The unique ID of the created claim
    function submitClaim(
        bytes32 claimHash,
        string calldata evidenceURI,
        uint256 stake
    ) external returns (uint256 claimId) {
        if (stake < minimumStake) {
            revert InsufficientStake(stake, minimumStake);
        }

        // Transfer stake from caller
        bool success = EMET.transferFrom(msg.sender, address(this), stake);
        if (!success) revert TransferFailed();

        // Create claim
        claimId = claimCount++;
        claims[claimId] = Claim({
            claimHash: claimHash,
            evidenceURI: evidenceURI,
            submitter: msg.sender,
            timestamp: block.timestamp,
            stake: stake,
            challengeEnd: 0,
            status: ClaimStatus.Active
        });

        emit ClaimSubmitted(
            claimId,
            claimHash,
            msg.sender,
            evidenceURI,
            stake,
            block.timestamp
        );
    }

    /// @notice Mark a claim as challenged (only callable by challenge contract)
    /// @param claimId The claim to mark as challenged
    function markChallenged(uint256 claimId) external {
        if (msg.sender != challengeContract) revert OnlyChallengeContract();
        
        Claim storage claim = claims[claimId];
        if (claim.submitter == address(0)) revert ClaimDoesNotExist(claimId);
        if (claim.status != ClaimStatus.Active) {
            revert InvalidStatus(claimId, claim.status, ClaimStatus.Active);
        }

        ClaimStatus oldStatus = claim.status;
        claim.status = ClaimStatus.Challenged;
        claim.challengeEnd = block.timestamp + challengePeriod;

        emit ClaimStatusChanged(claimId, oldStatus, ClaimStatus.Challenged);
    }

    /// @notice Resolve a claim (only callable by challenge contract)
    /// @param claimId The claim to resolve
    /// @param verified True if claim is verified, false if rejected
    /// @param stakeContract Address to send rejected claim stake to
    function resolveClaim(uint256 claimId, bool verified, address stakeContract) external {
        if (msg.sender != challengeContract) revert OnlyChallengeContract();
        
        Claim storage claim = claims[claimId];
        if (claim.submitter == address(0)) revert ClaimDoesNotExist(claimId);

        ClaimStatus oldStatus = claim.status;
        ClaimStatus newStatus = verified ? ClaimStatus.Verified : ClaimStatus.Rejected;
        claim.status = newStatus;

        // If verified, return stake to submitter
        // If rejected, stake goes to stake contract for challenger distribution
        if (verified) {
            bool success = EMET.transfer(claim.submitter, claim.stake);
            if (!success) revert TransferFailed();
        } else {
            bool success = EMET.transfer(stakeContract, claim.stake);
            if (!success) revert TransferFailed();
        }

        emit ClaimStatusChanged(claimId, oldStatus, newStatus);
    }

    /// @notice Verify an unchallenged claim after challenge period
    /// @dev Anyone can call this to finalize unchallenged claims
    /// @param claimId The claim to verify
    function verifyUnchallenged(uint256 claimId) external {
        Claim storage claim = claims[claimId];
        if (claim.submitter == address(0)) revert ClaimDoesNotExist(claimId);
        if (claim.status != ClaimStatus.Active) {
            revert InvalidStatus(claimId, claim.status, ClaimStatus.Active);
        }

        // Check if challenge period has passed without challenge
        if (block.timestamp < claim.timestamp + challengePeriod) {
            revert InvalidStatus(claimId, claim.status, ClaimStatus.Active);
        }

        ClaimStatus oldStatus = claim.status;
        claim.status = ClaimStatus.Verified;

        // Return stake to submitter
        bool success = EMET.transfer(claim.submitter, claim.stake);
        if (!success) revert TransferFailed();

        emit ClaimStatusChanged(claimId, oldStatus, ClaimStatus.Verified);
    }

    // ============ View Functions ============

    /// @notice Get full claim details
    /// @param claimId The claim ID to query
    /// @return claim The full claim struct
    function getClaim(uint256 claimId) external view returns (Claim memory claim) {
        claim = claims[claimId];
        if (claim.submitter == address(0)) revert ClaimDoesNotExist(claimId);
    }

    /// @notice Check if a claim can be verified (unchallenged and period passed)
    /// @param claimId The claim ID to check
    /// @return canVerify True if claim can be verified
    function canVerifyUnchallenged(uint256 claimId) external view returns (bool canVerify) {
        Claim storage claim = claims[claimId];
        if (claim.submitter == address(0)) return false;
        if (claim.status != ClaimStatus.Active) return false;
        return block.timestamp >= claim.timestamp + challengePeriod;
    }

    /// @notice Get the stake held for a claim
    /// @param claimId The claim ID
    /// @return stake The amount staked
    function getClaimStake(uint256 claimId) external view returns (uint256 stake) {
        return claims[claimId].stake;
    }

    /// @notice Get claim submitter
    /// @param claimId The claim ID
    /// @return submitter The submitter address
    function getClaimSubmitter(uint256 claimId) external view returns (address submitter) {
        return claims[claimId].submitter;
    }
}
