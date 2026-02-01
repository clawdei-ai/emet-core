// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {IEMET} from "./interfaces/IEMET.sol";
import {EMETRegistry} from "./EMETRegistry.sol";
import {EMETTreasury} from "./EMETTreasury.sol";
import {EMETReputation} from "./EMETReputation.sol";
import {EMETJuryPool} from "./EMETJuryPool.sol";

/// @title EMETChallengeV3 - Jury-based dispute resolution for EMET Protocol
/// @notice Challenges are resolved by jury vote, NOT stake weight.
///         Jurors evaluate evidence and vote. Majority wins.
///
/// Flow:
///   1. Challenger calls initiateChallenge(claimId, evidence, stake, tier)
///   2. Contract selects jury from JuryPool (3/7/11 based on tier)
///   3. Jurors vote during voting period (24h/72h/7d)
///   4. After period ends, anyone calls resolveChallenge(challengeId)
///   5. Majority vote determines outcome
///   6. Stakes distributed: winner gets (100% - resolutionFeeBps) of loser's stake
///
/// @dev Owner can configure resolution fee. Future governance can take over.
contract EMETChallengeV3 {
    // ============ Constants ============

    /// @notice EMET token on Base mainnet
    IEMET public constant EMET = IEMET(0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C);

    /// @notice Default resolution fee (5% = 500 bps)
    uint256 public constant DEFAULT_RESOLUTION_FEE_BPS = 500;

    /// @notice Juror reward share of remaining after fee (basis points)
    /// @dev After resolutionFeeBps is taken, this portion goes to jurors
    uint256 public constant JUROR_SHARE_OF_REMAINDER_BPS = 1053; // ~10% of 95%

    /// @notice Basis-point denominator
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Maximum allowed resolution fee (20%)
    uint256 public constant MAX_RESOLUTION_FEE_BPS = 2000;

    // ============ Tier Configuration ============

    /// @notice Challenge tiers with different jury sizes and stakes
    enum Tier { Minor, Major, Critical }

    /// @notice Jury sizes per tier
    uint256 public constant MINOR_JURY_SIZE = 3;
    uint256 public constant MAJOR_JURY_SIZE = 7;
    uint256 public constant CRITICAL_JURY_SIZE = 11;

    /// @notice Minimum stakes per tier
    uint256 public constant MINOR_MIN_STAKE = 10 ether;
    uint256 public constant MAJOR_MIN_STAKE = 100 ether;
    uint256 public constant CRITICAL_MIN_STAKE = 1000 ether;

    /// @notice Voting periods per tier (in seconds)
    uint256 public constant MINOR_VOTING_PERIOD = 24 hours;
    uint256 public constant MAJOR_VOTING_PERIOD = 72 hours;
    uint256 public constant CRITICAL_VOTING_PERIOD = 7 days;

    /// @notice Appeal stake multipliers (in basis points)
    uint256 public constant MINOR_APPEAL_MULTIPLIER = 20000; // 2x
    uint256 public constant MAJOR_APPEAL_MULTIPLIER = 25000; // 2.5x
    uint256 public constant CRITICAL_APPEAL_MULTIPLIER = 30000; // 3x

    // ============ Vote Types ============

    enum Vote { None, UpholdClaim, UpholdChallenge, Abstain }

    // ============ Types ============

    struct Challenge {
        uint256 claimId;          // The claim being challenged
        address challenger;        // Who initiated the challenge
        string evidence;           // Evidence URI or reasoning
        uint256 stake;            // Challenger's stake
        uint256 startTime;        // When challenge was created
        uint256 votingEnd;        // When voting period ends
        Tier tier;                // Challenge tier
        bool resolved;            // Whether resolved
        address[] jury;           // Selected jurors
        uint256 appealedTo;       // If appealed, the new challenge ID (0 = not appealed)
    }

    struct JurorVote {
        Vote vote;                // The vote cast
        string reasoning;         // On-chain reasoning for precedent
        uint256 timestamp;        // When vote was cast
    }

    struct ResolutionResult {
        Vote verdict;             // Winning verdict
        uint256 upholdClaimCount; // Votes to uphold claim
        uint256 upholdChallengeCount; // Votes to uphold challenge
        uint256 abstainCount;     // Abstention count
        address winner;           // Winner address (challenger or submitter)
        uint256 winnerPayout;     // Amount paid to winner
        uint256 jurorPayout;      // Amount paid to each winning juror
        uint256 protocolFee;      // Amount to treasury
    }

    /// @dev Internal struct to reduce stack depth in resolution
    struct VoteCounts {
        uint256 upholdClaim;
        uint256 upholdChallenge;
        uint256 abstain;
    }

    /// @dev Internal struct for payout calculation
    struct PayoutCalc {
        uint256 totalPool;
        uint256 protocolFee;
        uint256 afterFee;
        address winner;
        uint256 winnerPayout;
        uint256 jurorPayout;
    }

    // ============ Immutables ============

    EMETRegistry public immutable registry;
    EMETTreasury public immutable treasury;
    EMETReputation public immutable reputationContract;
    EMETJuryPool public immutable juryPool;

    /// @notice Contract owner for fee configuration
    address public owner;

    /// @notice Resolution fee in basis points (default 500 = 5%)
    /// @dev Deducted from losing party's stake, sent to Treasury
    uint256 public resolutionFeeBps;

    // ============ State ============

    /// @notice All challenges by ID
    mapping(uint256 => Challenge) public challenges;

    /// @notice Challenge count (also used as next ID)
    uint256 public challengeCount;

    /// @notice Votes per challenge per juror
    mapping(uint256 => mapping(address => JurorVote)) public votes;

    /// @notice Resolution results per challenge
    mapping(uint256 => ResolutionResult) public resolutions;

    /// @notice Active challenge per claim (only one at a time)
    mapping(uint256 => uint256) public activeChallenge;

    // ============ Events ============

    event ChallengeCreated(
        uint256 indexed challengeId,
        uint256 indexed claimId,
        address indexed challenger,
        string evidence,
        uint256 stake,
        Tier tier,
        uint256 votingEnd
    );

    event JurySelected(
        uint256 indexed challengeId,
        address[] jurors
    );

    event VoteCast(
        uint256 indexed challengeId,
        address indexed juror,
        Vote vote,
        string reasoning
    );

    event ChallengeResolved(
        uint256 indexed challengeId,
        Vote indexed verdict,
        address indexed winner,
        uint256 winnerPayout,
        uint256 jurorPayout,
        uint256 protocolFee
    );

    event ChallengeAppealed(
        uint256 indexed originalChallengeId,
        uint256 indexed newChallengeId,
        address indexed appellant,
        Tier newTier,
        uint256 stake
    );

    event ReputationUpdated(
        uint256 indexed challengeId,
        address indexed account,
        string action
    );

    event ResolutionFeeUpdated(uint256 indexed oldFeeBps, uint256 indexed newFeeBps);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ============ Errors ============

    error ClaimDoesNotExist(uint256 claimId);
    error ClaimNotActive(uint256 claimId);
    error ChallengeAlreadyExists(uint256 claimId);
    error ChallengeDoesNotExist(uint256 challengeId);
    error CannotChallengeOwnClaim();
    error InsufficientStake(uint256 provided, uint256 required);
    error VotingPeriodNotStarted();
    error VotingPeriodEnded();
    error VotingPeriodNotEnded();
    error NotAJuror(address account);
    error AlreadyVoted(address juror);
    error ChallengeAlreadyResolved(uint256 challengeId);
    error ChallengeNotResolved(uint256 challengeId);
    error ChallengeAlreadyAppealed(uint256 challengeId);
    error CannotAppealCritical();
    error InvalidVote();
    error TransferFailed();
    error ZeroAddress();
    error OnlyOwner();
    error InvalidResolutionFee(uint256 provided, uint256 max);

    // ============ Constructor ============

    /// @notice Deploy ChallengeV3 with all protocol integrations
    constructor(
        address _registry,
        address _treasury,
        address _reputation,
        address _juryPool
    ) {
        if (_registry == address(0)) revert ZeroAddress();
        if (_treasury == address(0)) revert ZeroAddress();
        if (_reputation == address(0)) revert ZeroAddress();
        if (_juryPool == address(0)) revert ZeroAddress();

        registry = EMETRegistry(_registry);
        treasury = EMETTreasury(_treasury);
        reputationContract = EMETReputation(_reputation);
        juryPool = EMETJuryPool(_juryPool);
        
        owner = msg.sender;
        resolutionFeeBps = DEFAULT_RESOLUTION_FEE_BPS;
    }

    // ============ Modifiers ============

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    // ============ Challenge Creation ============

    /// @notice Initiate a challenge against an active claim
    function initiateChallenge(
        uint256 claimId,
        string calldata evidence,
        uint256 stake,
        Tier tier
    ) external returns (uint256 challengeId) {
        EMETRegistry.Claim memory claim = registry.getClaim(claimId);

        if (claim.status != EMETRegistry.ClaimStatus.Active) {
            revert ClaimNotActive(claimId);
        }
        if (claim.submitter == msg.sender) {
            revert CannotChallengeOwnClaim();
        }
        if (activeChallenge[claimId] != 0) {
            revert ChallengeAlreadyExists(claimId);
        }

        // Validate stake for tier
        uint256 minStake = _getMinStake(tier);
        if (stake < minStake) {
            revert InsufficientStake(stake, minStake);
        }

        // Transfer stake
        if (!EMET.transferFrom(msg.sender, address(this), stake)) revert TransferFailed();

        // Create challenge
        challengeId = ++challengeCount;
        uint256 votingPeriod = _getVotingPeriod(tier);

        challenges[challengeId] = Challenge({
            claimId: claimId,
            challenger: msg.sender,
            evidence: evidence,
            stake: stake,
            startTime: block.timestamp,
            votingEnd: block.timestamp + votingPeriod,
            tier: tier,
            resolved: false,
            jury: new address[](0),
            appealedTo: 0
        });

        activeChallenge[claimId] = challengeId;

        // Mark claim as challenged in registry
        registry.markChallenged(claimId);

        // Select jury
        address[] memory excludes = new address[](2);
        excludes[0] = msg.sender;
        excludes[1] = claim.submitter;

        address[] memory selectedJury = juryPool.selectJury(challengeId, _getJurySize(tier), excludes);
        challenges[challengeId].jury = selectedJury;

        emit ChallengeCreated(challengeId, claimId, msg.sender, evidence, stake, tier, block.timestamp + votingPeriod);
        emit JurySelected(challengeId, selectedJury);

        return challengeId;
    }

    // ============ Voting ============

    /// @notice Cast a vote on a challenge
    function vote(uint256 challengeId, Vote v, string calldata reasoning) external {
        Challenge storage challenge = challenges[challengeId];

        if (challenge.challenger == address(0)) revert ChallengeDoesNotExist(challengeId);
        if (challenge.resolved) revert ChallengeAlreadyResolved(challengeId);
        if (block.timestamp > challenge.votingEnd) revert VotingPeriodEnded();
        if (v == Vote.None) revert InvalidVote();

        // Check if sender is a selected juror
        if (!_isJuror(challenge.jury, msg.sender)) revert NotAJuror(msg.sender);

        // Check if already voted
        if (votes[challengeId][msg.sender].vote != Vote.None) revert AlreadyVoted(msg.sender);

        // Record vote
        votes[challengeId][msg.sender] = JurorVote({
            vote: v,
            reasoning: reasoning,
            timestamp: block.timestamp
        });

        emit VoteCast(challengeId, msg.sender, v, reasoning);
    }

    // ============ Resolution ============

    /// @notice Resolve a challenge after voting period ends
    function resolveChallenge(uint256 challengeId) external {
        Challenge storage challenge = challenges[challengeId];

        if (challenge.challenger == address(0)) revert ChallengeDoesNotExist(challengeId);
        if (challenge.resolved) revert ChallengeAlreadyResolved(challengeId);
        if (block.timestamp < challenge.votingEnd) revert VotingPeriodNotEnded();

        challenge.resolved = true;
        activeChallenge[challenge.claimId] = 0;

        // Count votes
        VoteCounts memory counts = _countVotes(challengeId, challenge.jury);

        // Determine verdict
        Vote verdict = _determineVerdict(counts);

        // Get claim details
        EMETRegistry.Claim memory claim = registry.getClaim(challenge.claimId);

        // Execute resolution
        PayoutCalc memory payout = _executeResolution(
            challengeId,
            challenge,
            claim,
            verdict,
            counts
        );

        // Store resolution
        resolutions[challengeId] = ResolutionResult({
            verdict: verdict,
            upholdClaimCount: counts.upholdClaim,
            upholdChallengeCount: counts.upholdChallenge,
            abstainCount: counts.abstain,
            winner: payout.winner,
            winnerPayout: payout.winnerPayout,
            jurorPayout: payout.jurorPayout,
            protocolFee: payout.protocolFee
        });

        emit ChallengeResolved(
            challengeId,
            verdict,
            payout.winner,
            payout.winnerPayout,
            payout.jurorPayout,
            payout.protocolFee
        );
    }

    /// @dev Count votes for a challenge
    function _countVotes(uint256 challengeId, address[] storage jury)
        internal
        view
        returns (VoteCounts memory counts)
    {
        for (uint256 i = 0; i < jury.length; i++) {
            Vote v = votes[challengeId][jury[i]].vote;
            if (v == Vote.UpholdClaim) {
                counts.upholdClaim++;
            } else if (v == Vote.UpholdChallenge) {
                counts.upholdChallenge++;
            } else if (v == Vote.Abstain) {
                counts.abstain++;
            }
        }
    }

    /// @dev Determine verdict from vote counts
    function _determineVerdict(VoteCounts memory counts) internal pure returns (Vote) {
        if (counts.upholdClaim == 0 && counts.upholdChallenge == 0) {
            return Vote.Abstain;
        } else if (counts.upholdChallenge > counts.upholdClaim) {
            return Vote.UpholdChallenge;
        } else {
            return Vote.UpholdClaim;
        }
    }

    /// @dev Execute resolution and distribute funds
    function _executeResolution(
        uint256 challengeId,
        Challenge storage challenge,
        EMETRegistry.Claim memory claim,
        Vote verdict,
        VoteCounts memory counts
    ) internal returns (PayoutCalc memory payout) {
        payout.totalPool = challenge.stake + claim.stake;

        if (verdict == Vote.Abstain) {
            _handleAbstainResolution(challenge, claim, payout);
        } else {
            _handleVerdictResolution(challengeId, challenge, claim, verdict, payout);
        }

        return payout;
    }

    /// @dev Handle resolution when all abstained
    /// No verdict: both parties get stakes back, but challenger pays resolution fee
    function _handleAbstainResolution(
        Challenge storage challenge,
        EMETRegistry.Claim memory claim,
        PayoutCalc memory payout
    ) internal {
        payout.winner = address(0);
        payout.winnerPayout = 0;
        payout.jurorPayout = 0;

        // On abstain (no decision), claim is upheld by default (status quo)
        // Registry returns claim stake directly to submitter
        registry.resolveClaim(challenge.claimId, true, address(this));

        // Fee only from challenger's stake (submitter already got full stake back)
        payout.protocolFee = (challenge.stake * resolutionFeeBps) / BPS_DENOMINATOR;
        uint256 challengerReturn = challenge.stake - payout.protocolFee;

        // Return challenger stake minus fee
        if (!EMET.transfer(challenge.challenger, challengerReturn)) revert TransferFailed();

        // Pay protocol fee
        if (!EMET.transfer(address(treasury), payout.protocolFee)) revert TransferFailed();
    }

    /// @dev Handle resolution with a verdict
    /// @notice Winner gets (100% - resolutionFeeBps) of loser's stake
    ///         Resolution fee goes to Treasury from losing party's stake
    function _handleVerdictResolution(
        uint256 challengeId,
        Challenge storage challenge,
        EMETRegistry.Claim memory claim,
        Vote verdict,
        PayoutCalc memory payout
    ) internal {
        bool claimUpheld = (verdict == Vote.UpholdClaim);

        if (claimUpheld) {
            payout.winner = claim.submitter;
            // Claim upheld: registry sends stake back to submitter
            // We distribute challenger's stake (loser) to winner and jurors
            registry.resolveClaim(challenge.claimId, true, address(this));

            // Loser's stake = challenger's stake
            uint256 loserStake = challenge.stake;
            payout.protocolFee = (loserStake * resolutionFeeBps) / BPS_DENOMINATOR;
            payout.afterFee = loserStake - payout.protocolFee;

        } else {
            payout.winner = challenge.challenger;
            // Challenge upheld: registry sends claim stake (loser) to us
            registry.resolveClaim(challenge.claimId, false, address(this));

            // Winner gets their stake back + loser's stake minus fee
            // Loser's stake = claim stake
            uint256 loserStake = claim.stake;
            payout.protocolFee = (loserStake * resolutionFeeBps) / BPS_DENOMINATOR;
            // afterFee = challenger's own stake back + (loser's stake - fee)
            payout.afterFee = challenge.stake + loserStake - payout.protocolFee;
        }

        // Calculate distributions from afterFee
        // Juror share is calculated from the loser's stake portion after fee
        uint256 loserStakeAfterFee = claimUpheld ? 
            (challenge.stake - payout.protocolFee) : 
            (claim.stake - payout.protocolFee);
        uint256 jurorPoolAmount = (loserStakeAfterFee * JUROR_SHARE_OF_REMAINDER_BPS) / BPS_DENOMINATOR;
        payout.winnerPayout = payout.afterFee - jurorPoolAmount;

        // Distribute to winning jurors
        Vote winningVote = claimUpheld ? Vote.UpholdClaim : Vote.UpholdChallenge;
        payout.jurorPayout = _distributeToJurors(challengeId, challenge.jury, winningVote, jurorPoolAmount);

        // If no jurors voted for winning side, winner gets their share
        if (payout.jurorPayout == 0) {
            payout.winnerPayout += jurorPoolAmount;
        }

        // Pay winner
        if (!EMET.transfer(payout.winner, payout.winnerPayout)) revert TransferFailed();

        // Pay protocol fee
        if (!EMET.transfer(address(treasury), payout.protocolFee)) revert TransferFailed();

        // Update reputation
        _updateReputation(challengeId, claim.submitter, challenge.challenger, claimUpheld);
    }

    /// @dev Distribute juror rewards and return per-juror amount
    function _distributeToJurors(
        uint256 challengeId,
        address[] storage jury,
        Vote winningVote,
        uint256 totalAmount
    ) internal returns (uint256 perJurorPayout) {
        // Count winning jurors
        uint256 winnerCount = 0;
        for (uint256 i = 0; i < jury.length; i++) {
            if (votes[challengeId][jury[i]].vote == winningVote) {
                winnerCount++;
            }
        }

        if (winnerCount == 0) return 0;

        perJurorPayout = totalAmount / winnerCount;

        // Distribute
        for (uint256 i = 0; i < jury.length; i++) {
            if (votes[challengeId][jury[i]].vote == winningVote) {
                if (!EMET.transfer(jury[i], perJurorPayout)) revert TransferFailed();
            }
        }
    }

    // ============ Appeals ============

    /// @notice Appeal a resolved challenge to a higher tier
    function appeal(
        uint256 challengeId,
        string calldata evidence,
        uint256 stake
    ) external returns (uint256 newChallengeId) {
        Challenge storage original = challenges[challengeId];

        if (original.challenger == address(0)) revert ChallengeDoesNotExist(challengeId);
        if (!original.resolved) revert ChallengeNotResolved(challengeId);
        if (original.appealedTo != 0) revert ChallengeAlreadyAppealed(challengeId);
        if (original.tier == Tier.Critical) revert CannotAppealCritical();

        // Calculate required stake
        uint256 multiplier = _getAppealMultiplier(original.tier);
        uint256 requiredStake = (original.stake * multiplier) / BPS_DENOMINATOR;

        // Also must meet next tier minimum
        Tier newTier = Tier(uint8(original.tier) + 1);
        uint256 tierMin = _getMinStake(newTier);
        if (requiredStake < tierMin) {
            requiredStake = tierMin;
        }

        if (stake < requiredStake) {
            revert InsufficientStake(stake, requiredStake);
        }

        // Transfer stake
        if (!EMET.transferFrom(msg.sender, address(this), stake)) revert TransferFailed();

        // Create new challenge at higher tier
        newChallengeId = ++challengeCount;
        uint256 votingPeriod = _getVotingPeriod(newTier);

        EMETRegistry.Claim memory claim = registry.getClaim(original.claimId);

        challenges[newChallengeId] = Challenge({
            claimId: original.claimId,
            challenger: msg.sender,
            evidence: evidence,
            stake: stake,
            startTime: block.timestamp,
            votingEnd: block.timestamp + votingPeriod,
            tier: newTier,
            resolved: false,
            jury: new address[](0),
            appealedTo: 0
        });

        original.appealedTo = newChallengeId;
        activeChallenge[original.claimId] = newChallengeId;

        // Select new jury
        address[] memory excludes = new address[](2);
        excludes[0] = msg.sender;
        excludes[1] = claim.submitter;

        address[] memory selectedJury = juryPool.selectJury(newChallengeId, _getJurySize(newTier), excludes);
        challenges[newChallengeId].jury = selectedJury;

        emit ChallengeAppealed(challengeId, newChallengeId, msg.sender, newTier, stake);
        emit JurySelected(newChallengeId, selectedJury);

        return newChallengeId;
    }

    // ============ Owner Functions ============

    /// @notice Set the resolution fee in basis points
    /// @dev Only callable by owner. Fee is deducted from losing party's stake.
    /// @param _resolutionFeeBps New fee in basis points (max 2000 = 20%)
    function setResolutionFee(uint256 _resolutionFeeBps) external onlyOwner {
        if (_resolutionFeeBps > MAX_RESOLUTION_FEE_BPS) {
            revert InvalidResolutionFee(_resolutionFeeBps, MAX_RESOLUTION_FEE_BPS);
        }
        uint256 oldFee = resolutionFeeBps;
        resolutionFeeBps = _resolutionFeeBps;
        emit ResolutionFeeUpdated(oldFee, _resolutionFeeBps);
    }

    /// @notice Transfer ownership to a new address
    /// @param newOwner The new owner address
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    // ============ Internal Helpers ============

    function _isJuror(address[] storage jury, address account) internal view returns (bool) {
        for (uint256 i = 0; i < jury.length; i++) {
            if (jury[i] == account) return true;
        }
        return false;
    }

    function _getMinStake(Tier tier) internal pure returns (uint256) {
        if (tier == Tier.Minor) return MINOR_MIN_STAKE;
        if (tier == Tier.Major) return MAJOR_MIN_STAKE;
        return CRITICAL_MIN_STAKE;
    }

    function _getVotingPeriod(Tier tier) internal pure returns (uint256) {
        if (tier == Tier.Minor) return MINOR_VOTING_PERIOD;
        if (tier == Tier.Major) return MAJOR_VOTING_PERIOD;
        return CRITICAL_VOTING_PERIOD;
    }

    function _getJurySize(Tier tier) internal pure returns (uint256) {
        if (tier == Tier.Minor) return MINOR_JURY_SIZE;
        if (tier == Tier.Major) return MAJOR_JURY_SIZE;
        return CRITICAL_JURY_SIZE;
    }

    function _getAppealMultiplier(Tier tier) internal pure returns (uint256) {
        if (tier == Tier.Minor) return MINOR_APPEAL_MULTIPLIER;
        if (tier == Tier.Major) return MAJOR_APPEAL_MULTIPLIER;
        return CRITICAL_APPEAL_MULTIPLIER;
    }

    function _updateReputation(
        uint256 challengeId,
        address submitter,
        address challenger,
        bool claimUpheld
    ) internal {
        if (claimUpheld) {
            reputationContract.recordClaimVerified(submitter);
            reputationContract.recordChallengeFailed(challenger);
            emit ReputationUpdated(challengeId, submitter, "claim_verified");
            emit ReputationUpdated(challengeId, challenger, "challenge_failed");
        } else {
            reputationContract.recordClaimRejected(submitter);
            reputationContract.recordChallengeSuccess(challenger);
            emit ReputationUpdated(challengeId, submitter, "claim_rejected");
            emit ReputationUpdated(challengeId, challenger, "challenge_success");
        }
    }

    // ============ View Functions ============

    /// @notice Get challenge details
    function getChallenge(uint256 challengeId)
        external
        view
        returns (
            uint256 claimId,
            address challenger,
            string memory evidence,
            uint256 stake,
            uint256 startTime,
            uint256 votingEnd,
            Tier tier,
            bool resolved,
            address[] memory jury,
            uint256 appealedTo
        )
    {
        Challenge storage c = challenges[challengeId];
        return (
            c.claimId,
            c.challenger,
            c.evidence,
            c.stake,
            c.startTime,
            c.votingEnd,
            c.tier,
            c.resolved,
            c.jury,
            c.appealedTo
        );
    }

    /// @notice Get juror's vote on a challenge
    function getVote(uint256 challengeId, address juror)
        external
        view
        returns (Vote v, string memory reasoning, uint256 timestamp)
    {
        JurorVote storage jv = votes[challengeId][juror];
        return (jv.vote, jv.reasoning, jv.timestamp);
    }

    /// @notice Get resolution result
    function getResolution(uint256 challengeId)
        external
        view
        returns (ResolutionResult memory)
    {
        return resolutions[challengeId];
    }

    /// @notice Check if voting period is active
    function isVotingActive(uint256 challengeId) external view returns (bool) {
        Challenge storage c = challenges[challengeId];
        if (c.challenger == address(0)) return false;
        if (c.resolved) return false;
        return block.timestamp <= c.votingEnd;
    }

    /// @notice Check if a challenge can be resolved
    function canResolve(uint256 challengeId) external view returns (bool) {
        Challenge storage c = challenges[challengeId];
        if (c.challenger == address(0)) return false;
        if (c.resolved) return false;
        return block.timestamp > c.votingEnd;
    }

    /// @notice Get current vote counts for a challenge
    function getVoteCounts(uint256 challengeId)
        external
        view
        returns (uint256 upholdClaim, uint256 upholdChallenge, uint256 abstain, uint256 notVoted)
    {
        Challenge storage c = challenges[challengeId];

        for (uint256 i = 0; i < c.jury.length; i++) {
            Vote v = votes[challengeId][c.jury[i]].vote;
            if (v == Vote.UpholdClaim) {
                upholdClaim++;
            } else if (v == Vote.UpholdChallenge) {
                upholdChallenge++;
            } else if (v == Vote.Abstain) {
                abstain++;
            } else {
                notVoted++;
            }
        }
    }

    /// @notice Get tier parameters
    function getTierParams(Tier tier)
        external
        pure
        returns (
            uint256 jurySize,
            uint256 minStake,
            uint256 votingPeriod,
            uint256 appealMultiplier
        )
    {
        return (
            _getJurySize(tier),
            _getMinStake(tier),
            _getVotingPeriod(tier),
            _getAppealMultiplier(tier)
        );
    }
}
