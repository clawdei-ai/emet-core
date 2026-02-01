// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

/// @title EMETPrecedent - Formal precedent registry for EMET Protocol
/// @notice Stores resolved dispute outcomes as precedent for future jurors.
///         Precedents are immutable once recorded and queryable by claim ID or hash.
/// @dev Only authorized contract (ChallengeV3) can record precedents.
///      Precedents serve as reference material for future disputes on similar claims.
contract EMETPrecedent {
    // ============ Types ============

    /// @notice Verdict types matching ChallengeV3
    enum Verdict { None, UpholdClaim, UpholdChallenge, Abstain }

    /// @notice Challenge tiers matching ChallengeV3
    enum Tier { Minor, Major, Critical }

    /// @notice A recorded precedent from a resolved dispute
    struct Precedent {
        uint256 challengeId;           // The challenge that created this precedent
        uint256 claimId;               // The claim that was disputed
        bytes32 claimHash;             // keccak256 of claim text for similarity matching
        string evidence;               // Challenger's evidence/reasoning
        Verdict verdict;               // Final verdict (UpholdClaim or UpholdChallenge)
        Tier tier;                     // Challenge tier (Minor/Major/Critical)
        uint256 resolvedAt;            // Timestamp of resolution
        uint256 upholdClaimVotes;      // Votes to uphold the claim
        uint256 upholdChallengeVotes;  // Votes to uphold the challenge
        uint256 abstainVotes;          // Abstention votes
        string[] jurorReasonings;      // All reasoning strings from jurors
    }

    // ============ State ============

    /// @notice All precedents indexed by ID
    mapping(uint256 => Precedent) private precedents;

    /// @notice Total number of precedents recorded
    uint256 public precedentCount;

    /// @notice Mapping from claimId to list of precedent IDs
    mapping(uint256 => uint256[]) private claimPrecedents;

    /// @notice Mapping from claimHash to list of precedent IDs (for similar claim lookup)
    mapping(bytes32 => uint256[]) private hashPrecedents;

    /// @notice Authorized recorder (ChallengeV3 contract), set once
    address public recorder;

    /// @notice Deployer, used only to set recorder once
    address public immutable deployer;

    // ============ Events ============

    /// @notice Emitted when a new precedent is recorded
    event PrecedentRecorded(
        uint256 indexed precedentId,
        uint256 indexed challengeId,
        uint256 indexed claimId,
        bytes32 claimHash,
        Verdict verdict,
        Tier tier,
        uint256 resolvedAt
    );

    /// @notice Emitted when the recorder is set
    event RecorderSet(address indexed recorder);

    // ============ Errors ============

    error OnlyRecorder();
    error OnlyDeployer();
    error RecorderAlreadySet();
    error ZeroAddress();
    error PrecedentDoesNotExist(uint256 precedentId);
    error InvalidVerdict();

    // ============ Constructor ============

    constructor() {
        deployer = msg.sender;
    }

    // ============ Configuration ============

    /// @notice Set the authorized recorder contract. Can only be set once.
    /// @param _recorder Address of EMETChallengeV3
    function setRecorder(address _recorder) external {
        if (msg.sender != deployer) revert OnlyDeployer();
        if (recorder != address(0)) revert RecorderAlreadySet();
        if (_recorder == address(0)) revert ZeroAddress();
        recorder = _recorder;
        emit RecorderSet(_recorder);
    }

    // ============ Recording Functions ============

    /// @notice Record a new precedent from a resolved challenge
    /// @dev Only callable by the authorized recorder (ChallengeV3)
    /// @param challengeId The ID of the resolved challenge
    /// @param claimId The ID of the disputed claim
    /// @param claimHash keccak256 hash of the claim text for similarity matching
    /// @param evidence The challenger's evidence string
    /// @param verdict The final verdict (must be UpholdClaim or UpholdChallenge)
    /// @param tier The challenge tier
    /// @param upholdClaimVotes Number of votes to uphold the claim
    /// @param upholdChallengeVotes Number of votes to uphold the challenge
    /// @param abstainVotes Number of abstention votes
    /// @param jurorReasonings Array of reasoning strings from all jurors
    /// @return precedentId The ID of the newly recorded precedent
    function recordPrecedent(
        uint256 challengeId,
        uint256 claimId,
        bytes32 claimHash,
        string calldata evidence,
        Verdict verdict,
        Tier tier,
        uint256 upholdClaimVotes,
        uint256 upholdChallengeVotes,
        uint256 abstainVotes,
        string[] calldata jurorReasonings
    ) external returns (uint256 precedentId) {
        if (msg.sender != recorder) revert OnlyRecorder();
        if (verdict == Verdict.None) revert InvalidVerdict();

        precedentId = precedentCount++;

        // Store the precedent
        Precedent storage p = precedents[precedentId];
        p.challengeId = challengeId;
        p.claimId = claimId;
        p.claimHash = claimHash;
        p.evidence = evidence;
        p.verdict = verdict;
        p.tier = tier;
        p.resolvedAt = block.timestamp;
        p.upholdClaimVotes = upholdClaimVotes;
        p.upholdChallengeVotes = upholdChallengeVotes;
        p.abstainVotes = abstainVotes;

        // Copy juror reasonings
        for (uint256 i = 0; i < jurorReasonings.length; i++) {
            p.jurorReasonings.push(jurorReasonings[i]);
        }

        // Index by claimId
        claimPrecedents[claimId].push(precedentId);

        // Index by claimHash for similarity queries
        hashPrecedents[claimHash].push(precedentId);

        emit PrecedentRecorded(
            precedentId,
            challengeId,
            claimId,
            claimHash,
            verdict,
            tier,
            block.timestamp
        );

        return precedentId;
    }

    // ============ Query Functions ============

    /// @notice Get a single precedent by ID
    /// @param precedentId The ID of the precedent to retrieve
    /// @return The full precedent struct
    function getPrecedent(uint256 precedentId) external view returns (Precedent memory) {
        if (precedentId >= precedentCount) revert PrecedentDoesNotExist(precedentId);
        return precedents[precedentId];
    }

    /// @notice Get all precedents for a specific claim
    /// @dev Useful for exact claim history
    /// @param claimId The claim ID to query
    /// @return Array of precedents for this claim
    function getPrecedentsForClaim(uint256 claimId) external view returns (Precedent[] memory) {
        uint256[] storage ids = claimPrecedents[claimId];
        Precedent[] memory result = new Precedent[](ids.length);

        for (uint256 i = 0; i < ids.length; i++) {
            result[i] = precedents[ids[i]];
        }

        return result;
    }

    /// @notice Get all precedents for claims with the same hash
    /// @dev Useful for finding similar claims across different IDs
    /// @param claimHash The keccak256 hash of claim text
    /// @return Array of precedents with matching claim hash
    function getPrecedentsByHash(bytes32 claimHash) external view returns (Precedent[] memory) {
        uint256[] storage ids = hashPrecedents[claimHash];
        Precedent[] memory result = new Precedent[](ids.length);

        for (uint256 i = 0; i < ids.length; i++) {
            result[i] = precedents[ids[i]];
        }

        return result;
    }

    /// @notice Get precedent IDs for a claim (gas-efficient alternative)
    /// @param claimId The claim ID to query
    /// @return Array of precedent IDs
    function getPrecedentIdsForClaim(uint256 claimId) external view returns (uint256[] memory) {
        return claimPrecedents[claimId];
    }

    /// @notice Get precedent IDs by hash (gas-efficient alternative)
    /// @param claimHash The claim hash to query
    /// @return Array of precedent IDs
    function getPrecedentIdsByHash(bytes32 claimHash) external view returns (uint256[] memory) {
        return hashPrecedents[claimHash];
    }

    /// @notice Get the number of precedents for a claim
    /// @param claimId The claim ID to query
    /// @return The count of precedents
    function getPrecedentCountForClaim(uint256 claimId) external view returns (uint256) {
        return claimPrecedents[claimId].length;
    }

    /// @notice Get the number of precedents for a claim hash
    /// @param claimHash The claim hash to query
    /// @return The count of precedents
    function getPrecedentCountByHash(bytes32 claimHash) external view returns (uint256) {
        return hashPrecedents[claimHash].length;
    }

    /// @notice Check if a precedent exists for a specific challenge
    /// @param challengeId The challenge ID to check
    /// @return exists True if a precedent was recorded for this challenge
    /// @return precedentId The ID of the precedent (0 if not found, check exists flag)
    function hasPrecedentForChallenge(uint256 challengeId) external view returns (bool exists, uint256 precedentId) {
        // Linear search - could be optimized with a mapping if needed
        for (uint256 i = 0; i < precedentCount; i++) {
            if (precedents[i].challengeId == challengeId) {
                return (true, i);
            }
        }
        return (false, 0);
    }

    /// @notice Get statistics about recorded precedents
    /// @return total Total number of precedents
    /// @return upheldClaims Number of precedents where claim was upheld
    /// @return upheldChallenges Number of precedents where challenge was upheld
    function getStats() external view returns (
        uint256 total,
        uint256 upheldClaims,
        uint256 upheldChallenges
    ) {
        total = precedentCount;
        for (uint256 i = 0; i < precedentCount; i++) {
            if (precedents[i].verdict == Verdict.UpholdClaim) {
                upheldClaims++;
            } else if (precedents[i].verdict == Verdict.UpholdChallenge) {
                upheldChallenges++;
            }
        }
    }
}
