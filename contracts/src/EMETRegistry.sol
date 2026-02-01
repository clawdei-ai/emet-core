// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {IEMET} from "./interfaces/IEMET.sol";

/// @title EMETRegistry - Trustless claim registry for the EMET Protocol
/// @notice Agents submit claims with evidence, staking EMET tokens as collateral
/// @dev Claims can be challenged via EMETChallenge contract.
contract EMETRegistry {
    // ============ Constants ============

    /// @notice EMET token on Base mainnet
    IEMET public constant EMET = IEMET(0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C);

    /// @notice Treasury address for fee collection
    address public constant TREASURY = 0xe1230E68818CCE66275Ad95E1bC79517Ac1ae502;

    /// @notice Default claim submission fee (10 EMET)
    uint256 public constant DEFAULT_CLAIM_FEE = 10 ether;

    /// @notice Minimum stake required to submit a claim (immutable after deployment)
    uint256 public immutable minimumStake;

    /// @notice Challenge period duration (immutable after deployment)
    uint256 public immutable challengePeriod;

    /// @notice Contract owner for governance functions
    address public owner;

    // ============ Types ============

    enum ClaimStatus {
        Active,       // Open for challenges (PENDING)
        Challenged,   // Currently being disputed (CONTESTED)
        Verified,     // Challenged and resolved in favor of claim (VERIFIED)
        Rejected,     // Challenged and resolved against claim (REJECTED)
        Uncontested   // Passed without challenge (no reputation change)
    }

    struct Claim {
        bytes32 claimHash;       // keccak256(claimText) — integrity check
        string claimText;        // The actual claim in plain text
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

    /// @notice Fee required to submit a claim (goes to Treasury)
    uint256 public claimFee;

    /// @notice Number of verified claims per submitter (for airdrop eligibility)
    mapping(address => uint256) public verifiedClaimsCount;

    // ============ Events ============

    event ClaimSubmitted(
        uint256 indexed claimId,
        bytes32 indexed claimHash,
        address indexed submitter,
        string claimText,
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

    event ClaimFeeUpdated(uint256 indexed oldFee, uint256 indexed newFee);

    event ClaimFeePaid(uint256 indexed claimId, address indexed submitter, uint256 fee);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ============ Errors ============

    error OnlyOwner();
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
        claimFee = DEFAULT_CLAIM_FEE;
        owner = msg.sender;
    }

    // ============ Modifiers ============

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
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

    /// @notice Submit a new claim with full text and evidence
    /// @dev Caller must have approved this contract to spend at least `stake + claimFee` EMET.
    ///      The claimHash is derived on-chain from keccak256(claimText) for integrity.
    ///      A claim fee is transferred to Treasury upon submission.
    /// @param claimText The claim statement in plain text (stored on-chain)
    /// @param evidenceURI URI pointing to evidence (IPFS, Arweave, etc.)
    /// @param stake Amount of EMET to stake (must be >= minimumStake)
    /// @return claimId The unique ID of the created claim
    function submitClaim(
        string calldata claimText,
        string calldata evidenceURI,
        uint256 stake
    ) external returns (uint256 claimId) {
        if (stake < minimumStake) {
            revert InsufficientStake(stake, minimumStake);
        }

        // Derive hash from text on-chain — tamper-proof
        bytes32 claimHash = keccak256(bytes(claimText));

        // Transfer claim fee to Treasury (if claimFee > 0)
        if (claimFee > 0) {
            bool feeSuccess = EMET.transferFrom(msg.sender, TREASURY, claimFee);
            if (!feeSuccess) revert TransferFailed();
        }

        // Transfer stake from caller
        bool success = EMET.transferFrom(msg.sender, address(this), stake);
        if (!success) revert TransferFailed();

        // Create claim
        claimId = claimCount++;
        claims[claimId] = Claim({
            claimHash: claimHash,
            claimText: claimText,
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
            claimText,
            evidenceURI,
            stake,
            block.timestamp
        );

        if (claimFee > 0) {
            emit ClaimFeePaid(claimId, msg.sender, claimFee);
        }
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

        // Track verified claims for airdrop eligibility
        if (verified) {
            verifiedClaimsCount[claim.submitter]++;
        }

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
        claim.status = ClaimStatus.Uncontested;

        // Track uncontested claims for airdrop eligibility (counts as verified)
        verifiedClaimsCount[claim.submitter]++;

        // Return stake to submitter
        bool success = EMET.transfer(claim.submitter, claim.stake);
        if (!success) revert TransferFailed();

        emit ClaimStatusChanged(claimId, oldStatus, ClaimStatus.Uncontested);
    }

    // ============ Owner Functions ============

    /// @notice Set the claim submission fee
    /// @dev Only callable by owner. Fee goes to Treasury on each claim submission.
    /// @param _claimFee New claim fee in EMET (18 decimals)
    function setClaimFee(uint256 _claimFee) external onlyOwner {
        uint256 oldFee = claimFee;
        claimFee = _claimFee;
        emit ClaimFeeUpdated(oldFee, _claimFee);
    }

    /// @notice Transfer ownership to a new address
    /// @param newOwner The new owner address
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
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

    /// @notice Get number of verified claims for an address
    /// @param account The address to query
    /// @return count The number of verified (or uncontested) claims
    function getVerifiedClaimsCount(address account) external view returns (uint256 count) {
        return verifiedClaimsCount[account];
    }
}
