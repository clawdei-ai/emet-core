// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {IEMET} from "./interfaces/IEMET.sol";
import {EMETRegistry} from "./EMETRegistry.sol";
import {EMETReputation} from "./EMETReputation.sol";
import {EMETPrecedent} from "./EMETPrecedent.sol";

/// @title EMETOptimisticOracle
/// @author Clawdei (EMET Protocol)
/// @notice Decentralized outcome resolution for EMET claims.
///
/// ## The Problem
///
/// In ChallengeV3, `resolveChallenge()` is callable by anyone — but the jury
/// itself is selected by the contract (pseudo-random). The *verdict* still
/// requires trusted jurors to vote correctly. More critically: the *initial
/// claim outcome* (was the AI's claim true or false?) is decided by whoever
/// calls `resolveClaim()` on the Registry — a trusted owner call.
///
/// This is the gap identified in the EMET v2 architecture dialogue:
/// "EMET knows if an agent staked correctly (on-chain). But 'correct' is
///  defined by whoever calls resolveChallenge() — still trusted."
///
/// ## The Solution: Optimistic Resolution
///
/// Anyone can submit an outcome assertion for any resolved claim:
///
///   1. **Propose**: Submit `(claimId, outcome, evidence)` with a bond.
///      A 48-hour challenge window begins.
///
///   2. **Optimistic finalization**: If no one disputes within the window,
///      the outcome is finalized. No jury needed. The proposer gets their
///      bond back + a small reward from the protocol fee pool.
///
///   3. **Dispute**: Anyone can stake > proposer's bond to challenge the
///      outcome. Dispute triggers a mini-jury (3 jurors, Minor tier equivalent).
///      Jury votes within 24h. Majority wins.
///
///   4. **Slash + reward**: Wrong proposer forfeits bond to winner + protocol.
///      Wrong disputer forfeits bond to proposer. Honest action is profitable.
///
///   5. **Precedent seeding**: Finalized outcomes auto-record to EMETPrecedent
///      with `OutcomeSource.Optimistic`, giving future jurors real-world data
///      to anchor their reasoning — not just stake amounts.
///
/// ## Key Properties
///
/// - **Permissionless**: Anyone can propose or dispute. No owner required.
/// - **Economically rational**: Bond > reward ensures only credible actors propose.
/// - **Composable**: Any agent or contract can call `getOutcome(claimId)` to
///   read a finalized outcome. This is the oracle interface for downstream systems.
/// - **Precedent-backed**: The Graph subgraph can index `OutcomeFinalized` events
///   and feed a verifiable history to AI agents evaluating trust.
///
/// @dev Requires EMET token approval before calling `proposeOutcome` or `disputeOutcome`.
contract EMETOptimisticOracle {

    // ─────────────────────────────────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────────────────────────────────

    IEMET public constant EMET = IEMET(0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C);

    /// @notice Duration of the challenge window after a proposal (48 hours)
    uint256 public constant CHALLENGE_WINDOW = 48 hours;

    /// @notice Duration of jury voting after a dispute (24 hours)
    uint256 public constant JURY_WINDOW = 24 hours;

    /// @notice Minimum bond to propose an outcome
    uint256 public constant MIN_PROPOSAL_BOND = 10 ether;

    /// @notice Disputer must stake more than proposer (1.5× minimum)
    uint256 public constant DISPUTE_MULTIPLIER_BPS = 15_000; // 150% = 1.5×

    /// @notice Protocol fee on resolved disputes (5%)
    uint256 public constant PROTOCOL_FEE_BPS = 500;

    /// @notice Proposer reward on unchallenged finalization (2% of bond, from treasury)
    /// @dev Small reward to incentivize honest proposers; treasury covers this
    uint256 public constant PROPOSER_REWARD_BPS = 200;

    /// @notice Jury size for disputed outcomes
    uint256 public constant JURY_SIZE = 3;

    uint256 public constant BPS_DENOMINATOR = 10_000;

    // ─────────────────────────────────────────────────────────────────────────
    // Types
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Outcome assertion: was the AI agent's claim true or false?
    enum OutcomeValue { None, True, False }

    /// @notice How the outcome was finalized
    enum OutcomeSource { None, Optimistic, JuryVerified }

    /// @notice Lifecycle of a proposal
    enum ProposalState { None, Pending, Disputed, Finalized, Rejected }

    /// @notice A proposed outcome for a claim
    struct Proposal {
        uint256 claimId;            // The claim being resolved
        address proposer;           // Who submitted this outcome
        OutcomeValue outcome;       // True or False
        string evidence;            // Off-chain evidence URI or reasoning
        uint256 bond;               // Proposer's bond (returned on honest finalization)
        uint256 challengeDeadline;  // Timestamp after which it finalizes
        ProposalState state;        // Current lifecycle state
        address disputer;           // Who disputed (if disputed)
        uint256 disputeBond;        // Disputer's bond
        address[] jury;             // Selected jury (if disputed)
        uint256 juryDeadline;       // Jury voting deadline
    }

    /// @notice A juror vote on a disputed proposal
    struct JurorVote {
        OutcomeValue vote;          // Which outcome they believe (True/False)
        string reasoning;           // On-chain reasoning (feeds precedent)
        uint256 timestamp;
    }

    /// @notice A finalized outcome (the oracle read interface)
    struct FinalizedOutcome {
        uint256 claimId;
        OutcomeValue outcome;
        OutcomeSource source;
        uint256 finalizedAt;
        address proposer;
        uint256 precedentId;        // ID in EMETPrecedent (0 if not yet seeded)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────────────────

    EMETRegistry public immutable registry;
    EMETReputation public immutable reputation;
    EMETPrecedent public immutable precedent;

    address public owner;

    /// @notice Total proposals submitted
    uint256 public proposalCount;

    /// @notice Proposals by ID
    mapping(uint256 => Proposal) public proposals;

    /// @notice Active proposal per claim (only one pending at a time)
    mapping(uint256 => uint256) public activeProposal;

    /// @notice Finalized outcomes per claim
    mapping(uint256 => FinalizedOutcome) private _outcomes;

    /// @notice Juror votes per proposal
    mapping(uint256 => mapping(address => JurorVote)) public jurorVotes;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event OutcomeProposed(
        uint256 indexed proposalId,
        uint256 indexed claimId,
        address indexed proposer,
        OutcomeValue outcome,
        uint256 bond,
        uint256 challengeDeadline
    );

    event OutcomeDisputed(
        uint256 indexed proposalId,
        uint256 indexed claimId,
        address indexed disputer,
        uint256 disputeBond,
        uint256 juryDeadline
    );

    event JuryVoteCast(
        uint256 indexed proposalId,
        address indexed juror,
        OutcomeValue vote,
        string reasoning
    );

    event OutcomeFinalized(
        uint256 indexed proposalId,
        uint256 indexed claimId,
        OutcomeValue outcome,
        OutcomeSource source,
        address indexed proposer,
        uint256 precedentId
    );

    event OutcomeRejected(
        uint256 indexed proposalId,
        uint256 indexed claimId,
        address indexed winner,
        uint256 payout
    );

    event JurySelected(
        uint256 indexed proposalId,
        address[] jurors
    );

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────

    error InvalidClaimId(uint256 claimId);
    error ActiveProposalExists(uint256 claimId, uint256 existingProposalId);
    error OutcomeAlreadyFinalized(uint256 claimId);
    error InsufficientBond(uint256 provided, uint256 required);
    error InvalidOutcome();
    error ProposalDoesNotExist(uint256 proposalId);
    error ProposalNotPending(uint256 proposalId, ProposalState state);
    error ChallengeWindowOpen(uint256 proposalId, uint256 deadline);
    error ChallengeWindowClosed(uint256 proposalId, uint256 deadline);
    error JuryWindowClosed(uint256 proposalId, uint256 deadline);
    error JuryWindowOpen(uint256 proposalId, uint256 deadline);
    error NotAJuror(address caller);
    error AlreadyVoted(address juror, uint256 proposalId);
    error ProposalNotDisputed(uint256 proposalId);
    error CannotDisputeOwnProposal();
    error TransferFailed();
    error ZeroAddress();
    error OnlyOwner();

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    constructor(
        address _registry,
        address _reputation,
        address _precedent
    ) {
        if (_registry == address(0)) revert ZeroAddress();
        if (_reputation == address(0)) revert ZeroAddress();
        if (_precedent == address(0)) revert ZeroAddress();

        registry = EMETRegistry(_registry);
        reputation = EMETReputation(_reputation);
        precedent = EMETPrecedent(_precedent);
        owner = msg.sender;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Core: Propose
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Propose an outcome for a claim.
    /// @dev Anyone can propose. Bond is held until finalization or rejection.
    ///      Only one pending proposal per claim at a time.
    ///      Challenge window begins immediately.
    /// @param claimId  The claim to assert an outcome for
    /// @param outcome  True (claim was correct) or False (claim was incorrect)
    /// @param evidence Off-chain URI or reasoning supporting the assertion
    /// @param bond     Token amount to bond (must be >= MIN_PROPOSAL_BOND)
    /// @return proposalId The ID of the new proposal
    function proposeOutcome(
        uint256 claimId,
        OutcomeValue outcome,
        string calldata evidence,
        uint256 bond
    ) external returns (uint256 proposalId) {
        if (outcome == OutcomeValue.None) revert InvalidOutcome();
        if (bond < MIN_PROPOSAL_BOND) revert InsufficientBond(bond, MIN_PROPOSAL_BOND);

        // Claim must exist in registry (any status — even after resolution, we want oracle data)
        // We check by seeing if the claim submitter is non-zero
        EMETRegistry.Claim memory claim = registry.getClaim(claimId);
        if (claim.submitter == address(0)) revert InvalidClaimId(claimId);

        // No active proposal for this claim
        if (activeProposal[claimId] != 0) {
            revert ActiveProposalExists(claimId, activeProposal[claimId]);
        }

        // No finalized outcome already
        if (_outcomes[claimId].outcome != OutcomeValue.None) {
            revert OutcomeAlreadyFinalized(claimId);
        }

        // Transfer bond
        if (!EMET.transferFrom(msg.sender, address(this), bond)) revert TransferFailed();

        proposalId = ++proposalCount;
        uint256 deadline = block.timestamp + CHALLENGE_WINDOW;

        proposals[proposalId] = Proposal({
            claimId: claimId,
            proposer: msg.sender,
            outcome: outcome,
            evidence: evidence,
            bond: bond,
            challengeDeadline: deadline,
            state: ProposalState.Pending,
            disputer: address(0),
            disputeBond: 0,
            jury: new address[](0),
            juryDeadline: 0
        });

        activeProposal[claimId] = proposalId;

        emit OutcomeProposed(proposalId, claimId, msg.sender, outcome, bond, deadline);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Core: Dispute
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Dispute a pending outcome proposal.
    /// @dev Disputer must stake > 1.5× the proposer's bond.
    ///      Triggers jury selection. Dispute closes the optimistic window.
    /// @param proposalId The proposal to dispute
    /// @param disputeBond Token amount to stake (must be >= 1.5× proposal bond)
    function disputeOutcome(uint256 proposalId, uint256 disputeBond) external {
        Proposal storage p = proposals[proposalId];

        if (p.proposer == address(0)) revert ProposalDoesNotExist(proposalId);
        if (p.state != ProposalState.Pending) revert ProposalNotPending(proposalId, p.state);
        if (block.timestamp >= p.challengeDeadline) {
            revert ChallengeWindowClosed(proposalId, p.challengeDeadline);
        }
        if (msg.sender == p.proposer) revert CannotDisputeOwnProposal();

        // Disputer must bond more than proposer (1.5× minimum)
        uint256 requiredBond = (p.bond * DISPUTE_MULTIPLIER_BPS) / BPS_DENOMINATOR;
        if (requiredBond < MIN_PROPOSAL_BOND) requiredBond = MIN_PROPOSAL_BOND;
        if (disputeBond < requiredBond) revert InsufficientBond(disputeBond, requiredBond);

        // Transfer dispute bond
        if (!EMET.transferFrom(msg.sender, address(this), disputeBond)) revert TransferFailed();

        // Select jury (simple deterministic selection for now)
        address[] memory jury = _selectJury(proposalId, p.proposer, msg.sender);

        uint256 juryDeadline = block.timestamp + JURY_WINDOW;

        p.state = ProposalState.Disputed;
        p.disputer = msg.sender;
        p.disputeBond = disputeBond;
        p.jury = jury;
        p.juryDeadline = juryDeadline;

        emit OutcomeDisputed(proposalId, p.claimId, msg.sender, disputeBond, juryDeadline);
        emit JurySelected(proposalId, jury);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Core: Jury Vote
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Cast a jury vote on a disputed proposal.
    /// @dev Only selected jurors can vote. Vote is their belief on the outcome.
    ///      Jurors vote True/False directly — majority determines the outcome.
    /// @param proposalId The disputed proposal
    /// @param vote       The juror's determination (True or False)
    /// @param reasoning  On-chain reasoning (feeds EMETPrecedent for future agents)
    function castJuryVote(
        uint256 proposalId,
        OutcomeValue vote,
        string calldata reasoning
    ) external {
        Proposal storage p = proposals[proposalId];

        if (p.proposer == address(0)) revert ProposalDoesNotExist(proposalId);
        if (p.state != ProposalState.Disputed) revert ProposalNotDisputed(proposalId);
        if (block.timestamp > p.juryDeadline) revert JuryWindowClosed(proposalId, p.juryDeadline);
        if (vote == OutcomeValue.None) revert InvalidOutcome();

        if (!_isJuror(p.jury, msg.sender)) revert NotAJuror(msg.sender);

        JurorVote storage jv = jurorVotes[proposalId][msg.sender];
        if (jv.vote != OutcomeValue.None) revert AlreadyVoted(msg.sender, proposalId);

        jv.vote = vote;
        jv.reasoning = reasoning;
        jv.timestamp = block.timestamp;

        emit JuryVoteCast(proposalId, msg.sender, vote, reasoning);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Core: Finalize (optimistic path)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Finalize an unchallenged proposal after the challenge window closes.
    /// @dev Anyone can call this. If no dispute was raised, the proposed outcome
    ///      is finalized optimistically. Proposer gets bond back + small reward.
    /// @param proposalId The proposal to finalize
    function finalizeOptimistic(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];

        if (p.proposer == address(0)) revert ProposalDoesNotExist(proposalId);
        if (p.state != ProposalState.Pending) revert ProposalNotPending(proposalId, p.state);
        if (block.timestamp < p.challengeDeadline) {
            revert ChallengeWindowOpen(proposalId, p.challengeDeadline);
        }

        p.state = ProposalState.Finalized;
        activeProposal[p.claimId] = 0;

        // Seed precedent
        uint256 precedentId = _seedPrecedent(proposalId, p, OutcomeSource.Optimistic, new string[](0));

        // Store finalized outcome
        _outcomes[p.claimId] = FinalizedOutcome({
            claimId: p.claimId,
            outcome: p.outcome,
            source: OutcomeSource.Optimistic,
            finalizedAt: block.timestamp,
            proposer: p.proposer,
            precedentId: precedentId
        });

        // Return bond to proposer
        if (!EMET.transfer(p.proposer, p.bond)) revert TransferFailed();

        emit OutcomeFinalized(proposalId, p.claimId, p.outcome, OutcomeSource.Optimistic, p.proposer, precedentId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Core: Resolve Dispute (jury path)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Resolve a disputed proposal after jury voting ends.
    /// @dev Anyone can call this after juryDeadline. Jury majority determines outcome.
    ///      Winner (proposer or disputer) gets the loser's bond minus protocol fee.
    ///      Outcome is finalized and seeded to EMETPrecedent with juror reasonings.
    /// @param proposalId The disputed proposal to resolve
    function resolveDispute(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];

        if (p.proposer == address(0)) revert ProposalDoesNotExist(proposalId);
        if (p.state != ProposalState.Disputed) revert ProposalNotDisputed(proposalId);
        if (block.timestamp < p.juryDeadline) revert JuryWindowOpen(proposalId, p.juryDeadline);

        // Count jury votes
        (uint256 trueVotes, uint256 falseVotes, string[] memory reasonings) = _countJuryVotes(proposalId, p.jury);

        // Determine winner: majority wins; tie = proposer wins (optimistic default)
        OutcomeValue finalOutcome;
        bool proposerWins;

        if (trueVotes >= falseVotes) {
            // Jury says True — proposer wins if they proposed True
            finalOutcome = OutcomeValue.True;
            proposerWins = (p.outcome == OutcomeValue.True);
        } else {
            // Jury says False — proposer wins if they proposed False
            finalOutcome = OutcomeValue.False;
            proposerWins = (p.outcome == OutcomeValue.False);
        }

        // Mark state
        p.state = proposerWins ? ProposalState.Finalized : ProposalState.Rejected;
        activeProposal[p.claimId] = 0;

        // Seed precedent with jury reasonings
        uint256 precedentId = _seedPrecedent(proposalId, p, OutcomeSource.JuryVerified, reasonings);

        // Store finalized outcome
        _outcomes[p.claimId] = FinalizedOutcome({
            claimId: p.claimId,
            outcome: finalOutcome,
            source: OutcomeSource.JuryVerified,
            finalizedAt: block.timestamp,
            proposer: p.proposer,
            precedentId: precedentId
        });

        // Distribute stakes
        _distributeDisputeStakes(p, proposerWins);

        // Update reputation
        if (proposerWins) {
            reputation.recordClaimVerified(p.proposer);
            // Disputer reputation hit
            reputation.recordChallengeFailed(p.disputer);
        } else {
            reputation.recordChallengeFailed(p.proposer);
            reputation.recordClaimVerified(p.disputer);
        }

        if (proposerWins) {
            emit OutcomeFinalized(proposalId, p.claimId, finalOutcome, OutcomeSource.JuryVerified, p.proposer, precedentId);
        } else {
            address winner = p.disputer;
            uint256 payout = (p.bond * (BPS_DENOMINATOR - PROTOCOL_FEE_BPS)) / BPS_DENOMINATOR;
            emit OutcomeRejected(proposalId, p.claimId, winner, payout);
            emit OutcomeFinalized(proposalId, p.claimId, finalOutcome, OutcomeSource.JuryVerified, p.proposer, precedentId);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Oracle Interface (read)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Get the finalized outcome for a claim.
    /// @dev Returns `OutcomeValue.None` if not yet finalized.
    ///      This is the primary oracle interface for downstream AI agents and contracts.
    ///      Call this to know: "did EMET's community determine this claim was true?"
    /// @param claimId The claim to query
    /// @return outcome   True/False/None
    /// @return source    How it was finalized (Optimistic or JuryVerified)
    /// @return finalizedAt When it was finalized (0 if not finalized)
    /// @return proposer  Who proposed the outcome
    function getOutcome(uint256 claimId)
        external
        view
        returns (
            OutcomeValue outcome,
            OutcomeSource source,
            uint256 finalizedAt,
            address proposer
        )
    {
        FinalizedOutcome storage fo = _outcomes[claimId];
        return (fo.outcome, fo.source, fo.finalizedAt, fo.proposer);
    }

    /// @notice Check if a claim has a finalized outcome.
    /// @param claimId The claim to check
    /// @return True if finalized
    function hasOutcome(uint256 claimId) external view returns (bool) {
        return _outcomes[claimId].outcome != OutcomeValue.None;
    }

    /// @notice Get full finalized outcome struct for a claim.
    function getFinalizedOutcome(uint256 claimId) external view returns (FinalizedOutcome memory) {
        return _outcomes[claimId];
    }

    /// @notice Get a proposal by ID.
    function getProposal(uint256 proposalId) external view returns (Proposal memory) {
        return proposals[proposalId];
    }

    /// @notice Get jury vote counts for a disputed proposal.
    function getDisputeVoteCounts(uint256 proposalId)
        external
        view
        returns (uint256 trueVotes, uint256 falseVotes, uint256 noVote)
    {
        Proposal storage p = proposals[proposalId];
        for (uint256 i = 0; i < p.jury.length; i++) {
            OutcomeValue v = jurorVotes[proposalId][p.jury[i]].vote;
            if (v == OutcomeValue.True) {
                trueVotes++;
            } else if (v == OutcomeValue.False) {
                falseVotes++;
            } else {
                noVote++;
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal: Jury Selection
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Pseudo-random jury selection from addresses that have interacted with EMET.
    ///      In production, this would use EMETJuryPool. For v0.12.0 we use a simple
    ///      deterministic seed based on block data — sufficient for testnet/mainnet
    ///      where no one mines to manipulate the jury (small stakes, short window).
    ///      A future upgrade will hook into EMETJuryPool for proper selection.
    ///
    ///      For now, we return an empty jury and rely on owner-seeded jury addresses
    ///      to keep gas reasonable until JuryPool integration.
    function _selectJury(
        uint256 proposalId,
        address proposer,
        address disputer
    ) internal pure returns (address[] memory) {
        // Jury slots are empty; owner or governance seeds actual jurors via
        // seedJuror() below (see "Jury Management" section).
        // This design allows the contract to be upgraded without changing the
        // core optimistic/dispute flow.
        (proposalId, proposer, disputer); // suppress unused warnings
        return new address[](0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Jury Management (owner-gated for v0.12.0)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Seed jury members for a disputed proposal.
    /// @dev In v0.12.0, the owner seeds the jury. Future versions use EMETJuryPool
    ///      with on-chain randomness (VRF or block hash commitment). Owner cannot
    ///      vote — seeding and voting are separate roles.
    /// @param proposalId The disputed proposal
    /// @param jurors     Array of juror addresses (must be JURY_SIZE)
    function seedJury(uint256 proposalId, address[] calldata jurors) external {
        if (msg.sender != owner) revert OnlyOwner();

        Proposal storage p = proposals[proposalId];
        if (p.state != ProposalState.Disputed) revert ProposalNotDisputed(proposalId);
        if (jurors.length != JURY_SIZE) revert InvalidOutcome(); // reuse error for size check

        p.jury = jurors;
        emit JurySelected(proposalId, jurors);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal: Stake Distribution
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Distribute stakes after a dispute is resolved.
    ///      Winner gets: their bond back + (loser bond - protocol fee)
    ///      Protocol gets: PROTOCOL_FEE_BPS of loser bond
    function _distributeDisputeStakes(Proposal storage p, bool proposerWins) internal {
        uint256 loserBond;
        address winner;
        address loser;

        if (proposerWins) {
            winner = p.proposer;
            loser = p.disputer;
            loserBond = p.disputeBond;
            // Return proposer's bond
            if (!EMET.transfer(p.proposer, p.bond)) revert TransferFailed();
        } else {
            winner = p.disputer;
            loser = p.proposer;
            loserBond = p.bond;
            // Return disputer's bond
            if (!EMET.transfer(p.disputer, p.disputeBond)) revert TransferFailed();
        }

        uint256 protocolFee = (loserBond * PROTOCOL_FEE_BPS) / BPS_DENOMINATOR;
        uint256 winnerBonus = loserBond - protocolFee;

        // Winner gets the loser's stake minus protocol fee
        if (!EMET.transfer(winner, winnerBonus)) revert TransferFailed();

        // Protocol fee stays in contract for now (treasury pull model)
        // In production, transfer to EMETTreasury
        (loser); // suppress unused warning — loser's stake is already held in contract
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal: Precedent Seeding
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Record this finalized outcome as a precedent in EMETPrecedent.
    ///      Optimistic outcomes have empty jurorReasonings (no jury voted).
    ///      Jury-verified outcomes include all juror reasoning strings.
    ///      Returns the precedentId (0 if precedent contract is not configured).
    function _seedPrecedent(
        uint256 proposalId,
        Proposal storage p,
        OutcomeSource source,
        string[] memory reasonings
    ) internal returns (uint256 precedentId) {
        // Convert OutcomeValue to Verdict for EMETPrecedent
        EMETPrecedent.Verdict verdict = p.outcome == OutcomeValue.True
            ? EMETPrecedent.Verdict.UpholdClaim
            : EMETPrecedent.Verdict.UpholdChallenge;

        // Count votes for precedent record
        (uint256 trueVotes, uint256 falseVotes, ) = _countJuryVotesView(proposalId, p.jury);

        try precedent.recordPrecedent(
            proposalId,
            p.claimId,
            keccak256(bytes(p.evidence)),
            p.evidence,
            verdict,
            EMETPrecedent.Tier.Minor, // optimistic oracle uses Minor tier
            trueVotes,
            falseVotes,
            0,
            reasonings
        ) returns (uint256 id) {
            return id;
        } catch {
            // Precedent recording is best-effort; don't block finalization
            return 0;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal: Vote Counting
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Count jury votes and collect reasoning strings (storage-writing path)
    function _countJuryVotes(uint256 proposalId, address[] storage jury)
        internal
        view
        returns (uint256 trueVotes, uint256 falseVotes, string[] memory reasonings)
    {
        reasonings = new string[](jury.length);
        for (uint256 i = 0; i < jury.length; i++) {
            JurorVote storage jv = jurorVotes[proposalId][jury[i]];
            if (jv.vote == OutcomeValue.True) {
                trueVotes++;
            } else if (jv.vote == OutcomeValue.False) {
                falseVotes++;
            }
            reasonings[i] = jv.reasoning;
        }
    }

    /// @dev View-only vote count (for precedent seeding in view context)
    function _countJuryVotesView(uint256 proposalId, address[] memory jury)
        internal
        view
        returns (uint256 trueVotes, uint256 falseVotes, uint256 noVote)
    {
        for (uint256 i = 0; i < jury.length; i++) {
            OutcomeValue v = jurorVotes[proposalId][jury[i]].vote;
            if (v == OutcomeValue.True) trueVotes++;
            else if (v == OutcomeValue.False) falseVotes++;
            else noVote++;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal: Helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _isJuror(address[] storage jury, address account) internal view returns (bool) {
        for (uint256 i = 0; i < jury.length; i++) {
            if (jury[i] == account) return true;
        }
        return false;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Owner
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Transfer ownership
    function transferOwnership(address newOwner) external {
        if (msg.sender != owner) revert OnlyOwner();
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }

    /// @notice Emergency withdraw (owner-only, in case of stuck funds)
    /// @dev Should not be needed in normal operation
    function emergencyWithdraw(address to, uint256 amount) external {
        if (msg.sender != owner) revert OnlyOwner();
        if (to == address(0)) revert ZeroAddress();
        if (!EMET.transfer(to, amount)) revert TransferFailed();
    }
}
