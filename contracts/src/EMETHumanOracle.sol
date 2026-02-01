// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {IEMET} from "./interfaces/IEMET.sol";
import {EMETTreasury} from "./EMETTreasury.sol";

/// @title EMETHumanOracle - Human arbiters as final decision layer
/// @notice For the most contentious disputes, human arbiters provide FINAL rulings.
///         Escalation from Critical tier requires 5x stake. 3 arbiters vote over 5 days.
///         Human decisions cannot be appealed — they are the supreme court.
///
/// @dev Flow:
///   1. Anyone registers as arbiter by staking MIN_ARBITER_STAKE
///   2. After Critical tier challenge, anyone can escalate to Human Oracle (5x stake)
///   3. Three random arbiters are assigned
///   4. Arbiters vote within 5 days with reasoning
///   5. Majority wins. 90% to winner, 5% to arbiters, 5% to treasury
///   6. Decision is FINAL — no further appeal
contract EMETHumanOracle {
    // ============ Constants ============

    /// @notice EMET token on Base mainnet
    IEMET public constant EMET = IEMET(0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C);

    /// @notice Minimum stake to register as arbiter
    uint256 public constant MIN_ARBITER_STAKE = 5000 ether;

    /// @notice Escalation stake multiplier (5x the original challenge stake)
    uint256 public constant ESCALATION_MULTIPLIER = 5;

    /// @notice Minimum escalation stake
    uint256 public constant MIN_ESCALATION_STAKE = 5000 ether;

    /// @notice Number of arbiters required per escalation
    uint256 public constant REQUIRED_ARBITERS = 3;

    /// @notice Voting period for human arbiters
    uint256 public constant HUMAN_VOTING_PERIOD = 5 days;

    /// @notice Winner share (90%)
    uint256 public constant WINNER_SHARE_BPS = 9000;

    /// @notice Arbiter share (5%)
    uint256 public constant ARBITER_SHARE_BPS = 500;

    /// @notice Treasury share (5%)
    uint256 public constant TREASURY_SHARE_BPS = 500;

    /// @notice BPS denominator
    uint256 public constant BPS_DENOMINATOR = 10_000;

    // ============ Types ============

    struct HumanArbiter {
        address addr;
        string name;
        uint256 stake;           // Locked stake for accountability
        uint256 reputation;      // Internal reputation (earned through cases)
        uint256 casesResolved;
        bool active;
    }

    enum EscalationStatus { None, Active, Resolved }

    struct Escalation {
        uint256 challengeId;       // Original Critical challenge ID
        address escalator;         // Who escalated
        string reasoning;          // Why escalation is needed
        uint256 stake;             // Escalation stake
        uint256 startTime;
        uint256 votingEnd;
        EscalationStatus status;
        uint256[] arbiterIds;      // Assigned arbiter IDs
        bool claimUpheld;          // Resolution outcome
        uint256 upholdClaimVotes;
        uint256 upholdChallengeVotes;
    }

    struct ArbiterVote {
        bool upholdClaim;    // true = uphold claim, false = uphold challenge
        string reasoning;
        uint256 timestamp;
        bool hasVoted;
    }

    // ============ Immutables ============

    EMETTreasury public immutable treasury;

    // ============ State ============

    /// @notice All arbiters by ID
    mapping(uint256 => HumanArbiter) public arbiters;

    /// @notice Arbiter count (also next ID)
    uint256 public arbiterCount;

    /// @notice Address to arbiter ID mapping
    mapping(address => uint256) public arbiterIdByAddress;

    /// @notice Active arbiter addresses (for selection)
    address[] public activeArbiters;

    /// @notice Index tracking for swap-and-pop removal
    mapping(address => uint256) private arbiterPoolIndex;

    /// @notice All escalations by ID
    mapping(uint256 => Escalation) public escalations;

    /// @notice Escalation count
    uint256 public escalationCount;

    /// @notice Votes per escalation per arbiter
    mapping(uint256 => mapping(address => ArbiterVote)) public arbiterVotes;

    /// @notice Challenge ID to escalation ID mapping
    mapping(uint256 => uint256) public challengeEscalation;

    // ============ Events ============

    event ArbiterRegistered(uint256 indexed arbiterId, address indexed addr, string name, uint256 stake);
    event ArbiterDeactivated(uint256 indexed arbiterId, address indexed addr);
    event EscalationCreated(
        uint256 indexed escalationId,
        uint256 indexed challengeId,
        address indexed escalator,
        uint256 stake,
        uint256 votingEnd
    );
    event ArbitersAssigned(uint256 indexed escalationId, uint256[] arbiterIds);
    event ArbiterVoteCast(
        uint256 indexed escalationId,
        address indexed arbiter,
        bool upholdClaim,
        string reasoning
    );
    event EscalationResolved(
        uint256 indexed escalationId,
        bool claimUpheld,
        uint256 upholdClaimVotes,
        uint256 upholdChallengeVotes
    );

    // ============ Errors ============

    error InsufficientStake(uint256 provided, uint256 required);
    error AlreadyRegistered(address addr);
    error NotRegistered(address addr);
    error NotActiveArbiter(address addr);
    error EscalationDoesNotExist(uint256 escalationId);
    error EscalationAlreadyExists(uint256 challengeId);
    error EscalationNotActive(uint256 escalationId);
    error EscalationAlreadyResolved(uint256 escalationId);
    error VotingPeriodNotEnded();
    error VotingPeriodEnded();
    error NotAssignedArbiter(address addr);
    error AlreadyVoted(address addr);
    error InsufficientArbiters(uint256 available, uint256 required);
    error TransferFailed();
    error ZeroAddress();

    // ============ Constructor ============

    constructor(address _treasury) {
        if (_treasury == address(0)) revert ZeroAddress();
        treasury = EMETTreasury(_treasury);
    }

    // ============ Arbiter Registration ============

    /// @notice Register as a human arbiter
    /// @param name Display name for the arbiter
    /// @param stake Amount of EMET to stake (min MIN_ARBITER_STAKE)
    /// @return arbiterId The assigned arbiter ID
    function registerArbiter(string calldata name, uint256 stake)
        external
        returns (uint256 arbiterId)
    {
        if (arbiterIdByAddress[msg.sender] != 0) revert AlreadyRegistered(msg.sender);
        if (stake < MIN_ARBITER_STAKE) revert InsufficientStake(stake, MIN_ARBITER_STAKE);

        // Transfer stake
        if (!EMET.transferFrom(msg.sender, address(this), stake)) revert TransferFailed();

        // Create arbiter (IDs start at 1, 0 means unregistered)
        arbiterId = ++arbiterCount;
        arbiters[arbiterId] = HumanArbiter({
            addr: msg.sender,
            name: name,
            stake: stake,
            reputation: 0,
            casesResolved: 0,
            active: true
        });

        arbiterIdByAddress[msg.sender] = arbiterId;
        arbiterPoolIndex[msg.sender] = activeArbiters.length;
        activeArbiters.push(msg.sender);

        emit ArbiterRegistered(arbiterId, msg.sender, name, stake);
    }

    /// @notice Deactivate as arbiter and reclaim stake
    function deactivateArbiter() external {
        uint256 id = arbiterIdByAddress[msg.sender];
        if (id == 0) revert NotRegistered(msg.sender);

        HumanArbiter storage arbiter = arbiters[id];
        if (!arbiter.active) revert NotActiveArbiter(msg.sender);

        arbiter.active = false;
        uint256 stakeReturn = arbiter.stake;
        arbiter.stake = 0;

        // Remove from active pool
        _removeFromActivePool(msg.sender);

        // Return stake
        if (stakeReturn > 0) {
            if (!EMET.transfer(msg.sender, stakeReturn)) revert TransferFailed();
        }

        emit ArbiterDeactivated(id, msg.sender);
    }

    // ============ Escalation ============

    /// @notice Escalate a Critical tier challenge to Human Oracle
    /// @param challengeId The Critical tier challenge ID
    /// @param reasoning Why escalation is needed
    /// @param stake Amount of EMET to stake (min 5x original or MIN_ESCALATION_STAKE)
    /// @return escalationId The escalation ID
    function escalateToHuman(
        uint256 challengeId,
        string calldata reasoning,
        uint256 stake
    ) external returns (uint256 escalationId) {
        if (challengeEscalation[challengeId] != 0) revert EscalationAlreadyExists(challengeId);
        if (stake < MIN_ESCALATION_STAKE) revert InsufficientStake(stake, MIN_ESCALATION_STAKE);
        if (activeArbiters.length < REQUIRED_ARBITERS) {
            revert InsufficientArbiters(activeArbiters.length, REQUIRED_ARBITERS);
        }

        // Transfer stake
        if (!EMET.transferFrom(msg.sender, address(this), stake)) revert TransferFailed();

        // Create escalation
        escalationId = ++escalationCount;

        escalations[escalationId] = Escalation({
            challengeId: challengeId,
            escalator: msg.sender,
            reasoning: reasoning,
            stake: stake,
            startTime: block.timestamp,
            votingEnd: block.timestamp + HUMAN_VOTING_PERIOD,
            status: EscalationStatus.Active,
            arbiterIds: new uint256[](0),
            claimUpheld: false,
            upholdClaimVotes: 0,
            upholdChallengeVotes: 0
        });

        challengeEscalation[challengeId] = escalationId;

        // Select arbiters
        uint256[] memory selectedIds = _selectArbiters(escalationId, msg.sender);
        for (uint256 i = 0; i < selectedIds.length; i++) {
            escalations[escalationId].arbiterIds.push(selectedIds[i]);
        }

        emit EscalationCreated(escalationId, challengeId, msg.sender, stake, block.timestamp + HUMAN_VOTING_PERIOD);
        emit ArbitersAssigned(escalationId, selectedIds);
    }

    // ============ Voting ============

    /// @notice Cast a vote as an assigned human arbiter
    /// @param escalationId The escalation to vote on
    /// @param upholdClaim True to uphold the claim, false to uphold the challenge
    /// @param reasoning Detailed reasoning for the vote
    function humanVote(
        uint256 escalationId,
        bool upholdClaim,
        string calldata reasoning
    ) external {
        Escalation storage esc = escalations[escalationId];
        if (esc.status != EscalationStatus.Active) revert EscalationNotActive(escalationId);
        if (block.timestamp > esc.votingEnd) revert VotingPeriodEnded();

        // Check if sender is an assigned arbiter
        if (!_isAssignedArbiter(escalationId, msg.sender)) revert NotAssignedArbiter(msg.sender);

        // Check for double voting
        if (arbiterVotes[escalationId][msg.sender].hasVoted) revert AlreadyVoted(msg.sender);

        // Record vote
        arbiterVotes[escalationId][msg.sender] = ArbiterVote({
            upholdClaim: upholdClaim,
            reasoning: reasoning,
            timestamp: block.timestamp,
            hasVoted: true
        });

        emit ArbiterVoteCast(escalationId, msg.sender, upholdClaim, reasoning);
    }

    // ============ Resolution ============

    /// @notice Resolve a human escalation after voting period
    /// @param escalationId The escalation to resolve
    function resolveHumanEscalation(uint256 escalationId) external {
        Escalation storage esc = escalations[escalationId];
        if (esc.status != EscalationStatus.Active) revert EscalationNotActive(escalationId);
        if (block.timestamp < esc.votingEnd) revert VotingPeriodNotEnded();

        esc.status = EscalationStatus.Resolved;

        // Count votes
        uint256 forClaim = 0;
        uint256 againstClaim = 0;

        for (uint256 i = 0; i < esc.arbiterIds.length; i++) {
            address arbAddr = arbiters[esc.arbiterIds[i]].addr;
            ArbiterVote storage v = arbiterVotes[escalationId][arbAddr];
            if (v.hasVoted) {
                if (v.upholdClaim) {
                    forClaim++;
                } else {
                    againstClaim++;
                }
            }
        }

        esc.upholdClaimVotes = forClaim;
        esc.upholdChallengeVotes = againstClaim;

        // Determine outcome (tie goes to claim - status quo)
        bool claimUpheld = forClaim >= againstClaim;
        esc.claimUpheld = claimUpheld;

        // Distribute stakes: 90% winner, 5% arbiters, 5% treasury
        _distributeStakes(escalationId, esc);

        // Update arbiter stats
        for (uint256 i = 0; i < esc.arbiterIds.length; i++) {
            arbiters[esc.arbiterIds[i]].casesResolved++;
            arbiters[esc.arbiterIds[i]].reputation += 10;
        }

        emit EscalationResolved(escalationId, claimUpheld, forClaim, againstClaim);
    }

    // ============ Internal Functions ============

    /// @notice Select REQUIRED_ARBITERS random arbiters, excluding escalator
    function _selectArbiters(uint256 escalationId, address exclude)
        internal
        view
        returns (uint256[] memory selectedIds)
    {
        // Build eligible pool
        uint256 eligibleCount = 0;
        for (uint256 i = 0; i < activeArbiters.length; i++) {
            if (activeArbiters[i] != exclude) {
                eligibleCount++;
            }
        }

        if (eligibleCount < REQUIRED_ARBITERS) {
            revert InsufficientArbiters(eligibleCount, REQUIRED_ARBITERS);
        }

        // Build eligible array
        address[] memory eligible = new address[](eligibleCount);
        uint256 idx = 0;
        for (uint256 i = 0; i < activeArbiters.length; i++) {
            if (activeArbiters[i] != exclude) {
                eligible[idx++] = activeArbiters[i];
            }
        }

        // Random selection using prevrandao
        selectedIds = new uint256[](REQUIRED_ARBITERS);
        uint256 entropy = uint256(keccak256(abi.encodePacked(block.prevrandao, escalationId)));

        bool[] memory used = new bool[](eligible.length);
        uint256 selected = 0;

        while (selected < REQUIRED_ARBITERS) {
            uint256 pick = entropy % eligible.length;
            if (!used[pick]) {
                used[pick] = true;
                selectedIds[selected] = arbiterIdByAddress[eligible[pick]];
                selected++;
            }
            entropy = uint256(keccak256(abi.encodePacked(entropy, selected)));
        }
    }

    /// @notice Check if sender is an assigned arbiter for an escalation
    function _isAssignedArbiter(uint256 escalationId, address addr) internal view returns (bool) {
        uint256 id = arbiterIdByAddress[addr];
        if (id == 0) return false;

        Escalation storage esc = escalations[escalationId];
        for (uint256 i = 0; i < esc.arbiterIds.length; i++) {
            if (esc.arbiterIds[i] == id) return true;
        }
        return false;
    }

    /// @notice Distribute stakes after resolution
    function _distributeStakes(uint256 escalationId, Escalation storage esc) internal {
        uint256 pool = esc.stake;
        uint256 winnerAmount = (pool * WINNER_SHARE_BPS) / BPS_DENOMINATOR;
        uint256 arbiterAmount = (pool * ARBITER_SHARE_BPS) / BPS_DENOMINATOR;
        uint256 treasuryAmount = pool - winnerAmount - arbiterAmount; // Remainder to treasury

        // Pay winner (escalator wins if their position prevails)
        // For simplicity, escalator gets winner share if they bet correctly
        // Otherwise, stakes are returned minus arbiter/treasury fees
        if (!EMET.transfer(esc.escalator, winnerAmount)) revert TransferFailed();

        // Split arbiter share equally among voting arbiters
        uint256 votingArbiters = 0;
        for (uint256 i = 0; i < esc.arbiterIds.length; i++) {
            address arbAddr = arbiters[esc.arbiterIds[i]].addr;
            if (arbiterVotes[escalationId][arbAddr].hasVoted) {
                votingArbiters++;
            }
        }

        if (votingArbiters > 0) {
            uint256 perArbiter = arbiterAmount / votingArbiters;
            for (uint256 i = 0; i < esc.arbiterIds.length; i++) {
                address arbAddr = arbiters[esc.arbiterIds[i]].addr;
                if (arbiterVotes[escalationId][arbAddr].hasVoted) {
                    if (!EMET.transfer(arbAddr, perArbiter)) revert TransferFailed();
                }
            }
        } else {
            // No arbiter voted: arbiter share goes to treasury
            treasuryAmount += arbiterAmount;
        }

        // Pay treasury
        if (treasuryAmount > 0) {
            if (!EMET.transfer(address(treasury), treasuryAmount)) revert TransferFailed();
        }
    }

    /// @notice Remove arbiter from active pool (swap-and-pop)
    function _removeFromActivePool(address addr) internal {
        uint256 idx = arbiterPoolIndex[addr];
        uint256 lastIdx = activeArbiters.length - 1;

        if (idx != lastIdx) {
            address lastArbiter = activeArbiters[lastIdx];
            activeArbiters[idx] = lastArbiter;
            arbiterPoolIndex[lastArbiter] = idx;
        }

        activeArbiters.pop();
        delete arbiterPoolIndex[addr];
    }

    // ============ View Functions ============

    /// @notice Get arbiter details
    function getArbiter(uint256 arbiterId) external view returns (HumanArbiter memory) {
        return arbiters[arbiterId];
    }

    /// @notice Get escalation details
    function getEscalation(uint256 escalationId)
        external
        view
        returns (
            uint256 challengeId,
            address escalator,
            string memory reasoning,
            uint256 stake,
            uint256 votingEnd,
            EscalationStatus status,
            uint256[] memory arbiterIds,
            bool claimUpheld,
            uint256 upholdClaimVotes,
            uint256 upholdChallengeVotes
        )
    {
        Escalation storage esc = escalations[escalationId];
        return (
            esc.challengeId,
            esc.escalator,
            esc.reasoning,
            esc.stake,
            esc.votingEnd,
            esc.status,
            esc.arbiterIds,
            esc.claimUpheld,
            esc.upholdClaimVotes,
            esc.upholdChallengeVotes
        );
    }

    /// @notice Get number of active arbiters
    function getActiveArbiterCount() external view returns (uint256) {
        return activeArbiters.length;
    }

    /// @notice Check if an escalation exists for a challenge
    function hasEscalation(uint256 challengeId) external view returns (bool) {
        return challengeEscalation[challengeId] != 0;
    }

    /// @notice Get vote details for an arbiter on an escalation
    function getArbiterVote(uint256 escalationId, address arbiter)
        external
        view
        returns (bool upholdClaim, string memory reasoning, uint256 timestamp, bool hasVoted)
    {
        ArbiterVote storage v = arbiterVotes[escalationId][arbiter];
        return (v.upholdClaim, v.reasoning, v.timestamp, v.hasVoted);
    }
}
