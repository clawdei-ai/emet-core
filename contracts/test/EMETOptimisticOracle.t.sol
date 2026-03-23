// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, console} from "forge-std/Test.sol";
import {EMETOptimisticOracle} from "../src/EMETOptimisticOracle.sol";
import {EMETPrecedent} from "../src/EMETPrecedent.sol";

/// @title EMETOptimisticOracle Tests
/// @notice Test suite for EMETOptimisticOracle — v0.12.0
/// @dev Covers:
///   1. Proposal lifecycle (propose → finalize optimistically)
///   2. Dispute path (propose → dispute → jury vote → resolve)
///   3. Oracle read interface (getOutcome, hasOutcome)
///   4. Precedent seeding on finalization
///   5. Stake distribution (proposer win / disputer win)
///   6. Guard rails (duplicate proposals, finalized claims, invalid bonds)

// ─────────────────────────────────────────────────────────────────────────────
// Mocks
// ─────────────────────────────────────────────────────────────────────────────

contract MockEMET {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient balance");
        require(allowance[from][msg.sender] >= amount, "insufficient allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockRegistry {
    /// @dev Must match EMETRegistry.Claim field order exactly for ABI compatibility
    enum ClaimStatus { None, Active, Challenged, Resolved }

    struct Claim {
        bytes32 claimHash;
        string claimText;
        string evidenceURI;
        address submitter;
        uint256 timestamp;
        uint256 stake;
        uint256 challengeEnd;
        ClaimStatus status;
    }

    mapping(uint256 => Claim) public claims;
    uint256 public claimCount;

    function addClaim(address submitter, uint256 stake) external returns (uint256 id) {
        id = claimCount++;
        Claim storage c = claims[id];
        c.claimHash = keccak256("test claim");
        c.claimText = "test claim";
        c.evidenceURI = "ipfs://evidence";
        c.submitter = submitter;
        c.timestamp = block.timestamp;
        c.stake = stake;
        c.challengeEnd = 0;
        c.status = ClaimStatus.Active;
    }

    function getClaim(uint256 claimId) external view returns (Claim memory) {
        return claims[claimId];
    }
}

contract MockReputation {
    mapping(address => uint256) public claimVerifiedCount;
    mapping(address => uint256) public challengeFailedCount;
    mapping(address => uint256) public resolvedCorrectCount;

    function recordClaimVerified(address account) external {
        claimVerifiedCount[account]++;
    }

    function recordChallengeFailed(address account) external {
        challengeFailedCount[account]++;
    }

    function recordChallengeSuccess(address account) external {
        resolvedCorrectCount[account]++;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Setup
// ─────────────────────────────────────────────────────────────────────────────

/// @notice Base setup for all test contracts in this file
contract OracleTestBase is Test {
    EMETOptimisticOracle public oracle;
    EMETPrecedent public precedentContract;
    MockEMET public emet;
    MockRegistry public registry;
    MockReputation public reputation;

    address constant EMET_ADDR = 0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C;

    address public deployer = makeAddr("deployer");
    address public alice    = makeAddr("alice");     // proposer
    address public bob      = makeAddr("bob");       // disputer
    address public juror1   = makeAddr("juror1");
    address public juror2   = makeAddr("juror2");
    address public juror3   = makeAddr("juror3");
    address public eve      = makeAddr("eve");       // third party

    uint256 constant MIN_BOND         = 10 ether;    // EMETOptimisticOracle.MIN_PROPOSAL_BOND
    uint256 constant CLAIM_STAKE      = 100 ether;
    uint256 constant PROTOCOL_FEE_BPS = 500;         // EMETOptimisticOracle.PROTOCOL_FEE_BPS (5%)

    function setUp() public virtual {
        // Deploy mock EMET at the hardcoded address
        emet = new MockEMET();
        vm.etch(EMET_ADDR, address(emet).code);
        emet = MockEMET(EMET_ADDR);

        // Deploy mock registry and reputation
        registry = new MockRegistry();
        reputation = new MockReputation();

        // Deploy EMETPrecedent with this test contract as deployer
        precedentContract = new EMETPrecedent();

        // Deploy oracle
        vm.prank(deployer);
        oracle = new EMETOptimisticOracle(
            address(registry),
            address(reputation),
            address(precedentContract)
        );

        // Set oracle as recorder in precedent (deployer = this test contract)
        precedentContract.setRecorder(address(oracle));

        // Seed balances and approvals
        emet.mint(alice, 1_000 ether);
        emet.mint(bob, 1_000 ether);
        emet.mint(eve, 1_000 ether);
        emet.mint(address(oracle), 0); // Initialize oracle balance slot

        vm.prank(alice);
        emet.approve(address(oracle), type(uint256).max);
        vm.prank(bob);
        emet.approve(address(oracle), type(uint256).max);
        vm.prank(eve);
        emet.approve(address(oracle), type(uint256).max);
    }

    /// @dev Helper: create a claim in the mock registry
    function _createClaim(address submitter) internal returns (uint256 claimId) {
        claimId = registry.addClaim(submitter, CLAIM_STAKE);
    }

    /// @dev Helper: propose outcome for a claim as alice
    function _alicePropose(uint256 claimId, EMETOptimisticOracle.OutcomeValue outcome)
        internal
        returns (uint256 proposalId)
    {
        vm.prank(alice);
        proposalId = oracle.proposeOutcome(claimId, outcome, "ipfs://evidence", MIN_BOND);
    }

    /// @dev Helper: dispute alice's proposal as bob
    function _bobDispute(uint256 proposalId) internal {
        uint256 disputeBond = (MIN_BOND * 15_000) / 10_000; // 1.5×
        vm.prank(bob);
        oracle.disputeOutcome(proposalId, disputeBond);
    }

    /// @dev Helper: seed 3 jurors for a disputed proposal
    function _seedJury(uint256 proposalId) internal {
        address[] memory jurors = new address[](3);
        jurors[0] = juror1;
        jurors[1] = juror2;
        jurors[2] = juror3;
        vm.prank(deployer);
        oracle.seedJury(proposalId, jurors);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. Proposal Lifecycle Tests
// ─────────────────────────────────────────────────────────────────────────────

contract EMETOptimisticOracle_ProposeTest is OracleTestBase {

    function test_Propose_Success() public {
        uint256 claimId = _createClaim(eve);
        uint256 aliceBalanceBefore = emet.balanceOf(alice);

        vm.prank(alice);
        uint256 proposalId = oracle.proposeOutcome(
            claimId,
            EMETOptimisticOracle.OutcomeValue.True,
            "ipfs://evidence",
            MIN_BOND
        );

        assertEq(proposalId, 1, "first proposal ID should be 1");
        assertEq(emet.balanceOf(alice), aliceBalanceBefore - MIN_BOND, "bond deducted");
        assertEq(emet.balanceOf(address(oracle)), MIN_BOND, "oracle holds bond");

        EMETOptimisticOracle.Proposal memory p = oracle.getProposal(proposalId);
        assertEq(p.claimId, claimId);
        assertEq(p.proposer, alice);
        assertTrue(p.outcome == EMETOptimisticOracle.OutcomeValue.True);
        assertTrue(p.state == EMETOptimisticOracle.ProposalState.Pending);
        assertEq(p.bond, MIN_BOND);
        assertEq(p.challengeDeadline, block.timestamp + 48 hours);
    }

    function test_Propose_EmitsEvent() public {
        uint256 claimId = _createClaim(eve);
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit EMETOptimisticOracle.OutcomeProposed(
            1, claimId, alice, EMETOptimisticOracle.OutcomeValue.True, MIN_BOND, block.timestamp + 48 hours
        );
        oracle.proposeOutcome(claimId, EMETOptimisticOracle.OutcomeValue.True, "ipfs://e", MIN_BOND);
    }

    function test_Propose_RevertIfBondTooLow() public {
        uint256 claimId = _createClaim(eve);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(EMETOptimisticOracle.InsufficientBond.selector, 5 ether, MIN_BOND)
        );
        oracle.proposeOutcome(claimId, EMETOptimisticOracle.OutcomeValue.True, "ipfs://e", 5 ether);
    }

    function test_Propose_RevertIfInvalidOutcome() public {
        uint256 claimId = _createClaim(eve);
        vm.prank(alice);
        vm.expectRevert(EMETOptimisticOracle.InvalidOutcome.selector);
        oracle.proposeOutcome(claimId, EMETOptimisticOracle.OutcomeValue.None, "ipfs://e", MIN_BOND);
    }

    function test_Propose_RevertIfClaimNotExist() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(EMETOptimisticOracle.InvalidClaimId.selector, 999));
        oracle.proposeOutcome(999, EMETOptimisticOracle.OutcomeValue.True, "ipfs://e", MIN_BOND);
    }

    function test_Propose_RevertIfActiveProposalExists() public {
        uint256 claimId = _createClaim(eve);
        _alicePropose(claimId, EMETOptimisticOracle.OutcomeValue.True);

        // Second proposal for same claim should fail
        vm.prank(eve);
        emet.mint(eve, MIN_BOND);
        vm.prank(eve);
        emet.approve(address(oracle), type(uint256).max);
        vm.prank(eve);
        vm.expectRevert(
            abi.encodeWithSelector(EMETOptimisticOracle.ActiveProposalExists.selector, claimId, 1)
        );
        oracle.proposeOutcome(claimId, EMETOptimisticOracle.OutcomeValue.False, "ipfs://e", MIN_BOND);
    }

    function test_Propose_TracksProposaCount() public {
        uint256 c1 = _createClaim(eve);
        uint256 c2 = _createClaim(eve);
        _alicePropose(c1, EMETOptimisticOracle.OutcomeValue.True);
        // Fast-forward, finalize first proposal, then propose second
        vm.warp(block.timestamp + 48 hours + 1);
        oracle.finalizeOptimistic(1);

        vm.prank(alice);
        uint256 p2 = oracle.proposeOutcome(c2, EMETOptimisticOracle.OutcomeValue.False, "ipfs://e2", MIN_BOND);
        assertEq(p2, 2, "second proposal should have ID 2");
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. Optimistic Finalization Tests
// ─────────────────────────────────────────────────────────────────────────────

contract EMETOptimisticOracle_FinalizeTest is OracleTestBase {

    function test_FinalizeOptimistic_AfterWindow_ReturnsBond() public {
        uint256 claimId = _createClaim(eve);
        uint256 aliceBalanceBefore = emet.balanceOf(alice);

        uint256 proposalId = _alicePropose(claimId, EMETOptimisticOracle.OutcomeValue.True);

        vm.warp(block.timestamp + 48 hours + 1);

        oracle.finalizeOptimistic(proposalId);

        // Bond returned to alice
        assertEq(emet.balanceOf(alice), aliceBalanceBefore, "alice gets full bond back");
    }

    function test_FinalizeOptimistic_SetsOutcome() public {
        uint256 claimId = _createClaim(eve);
        uint256 proposalId = _alicePropose(claimId, EMETOptimisticOracle.OutcomeValue.True);

        vm.warp(block.timestamp + 48 hours + 1);
        oracle.finalizeOptimistic(proposalId);

        (
            EMETOptimisticOracle.OutcomeValue outcome,
            EMETOptimisticOracle.OutcomeSource source,
            uint256 finalizedAt,
            address proposer
        ) = oracle.getOutcome(claimId);

        assertTrue(outcome == EMETOptimisticOracle.OutcomeValue.True, "outcome should be True");
        assertTrue(source == EMETOptimisticOracle.OutcomeSource.Optimistic, "source should be Optimistic");
        assertEq(proposer, alice);
        assertGt(finalizedAt, 0, "finalizedAt should be set");
    }

    function test_FinalizeOptimistic_HasOutcome_ReturnsTrue() public {
        uint256 claimId = _createClaim(eve);
        uint256 proposalId = _alicePropose(claimId, EMETOptimisticOracle.OutcomeValue.True);

        assertFalse(oracle.hasOutcome(claimId), "not finalized yet");

        vm.warp(block.timestamp + 48 hours + 1);
        oracle.finalizeOptimistic(proposalId);

        assertTrue(oracle.hasOutcome(claimId), "should have outcome after finalization");
    }

    function test_FinalizeOptimistic_EmitsEvent() public {
        uint256 claimId = _createClaim(eve);
        uint256 proposalId = _alicePropose(claimId, EMETOptimisticOracle.OutcomeValue.True);

        vm.warp(block.timestamp + 48 hours + 1);

        vm.expectEmit(true, true, true, false);
        emit EMETOptimisticOracle.OutcomeFinalized(
            proposalId, claimId, EMETOptimisticOracle.OutcomeValue.True,
            EMETOptimisticOracle.OutcomeSource.Optimistic, alice, 0
        );
        oracle.finalizeOptimistic(proposalId);
    }

    function test_FinalizeOptimistic_RevertBeforeWindow() public {
        uint256 claimId = _createClaim(eve);
        uint256 proposalId = _alicePropose(claimId, EMETOptimisticOracle.OutcomeValue.True);

        vm.warp(block.timestamp + 24 hours); // only halfway through window
        vm.expectRevert(
            abi.encodeWithSelector(
                EMETOptimisticOracle.ChallengeWindowOpen.selector,
                proposalId,
                block.timestamp - 24 hours + 48 hours
            )
        );
        oracle.finalizeOptimistic(proposalId);
    }

    function test_FinalizeOptimistic_RevertIfAlreadyFinalized() public {
        uint256 claimId = _createClaim(eve);
        uint256 proposalId = _alicePropose(claimId, EMETOptimisticOracle.OutcomeValue.True);

        vm.warp(block.timestamp + 48 hours + 1);
        oracle.finalizeOptimistic(proposalId);

        vm.expectRevert(
            abi.encodeWithSelector(
                EMETOptimisticOracle.ProposalNotPending.selector,
                proposalId,
                EMETOptimisticOracle.ProposalState.Finalized
            )
        );
        oracle.finalizeOptimistic(proposalId);
    }

    function test_FinalizeOptimistic_RevertIfAlreadyFinalizedClaim() public {
        uint256 claimId = _createClaim(eve);
        uint256 proposalId = _alicePropose(claimId, EMETOptimisticOracle.OutcomeValue.True);

        vm.warp(block.timestamp + 48 hours + 1);
        oracle.finalizeOptimistic(proposalId);

        // Try to propose again for same claim
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(EMETOptimisticOracle.OutcomeAlreadyFinalized.selector, claimId));
        oracle.proposeOutcome(claimId, EMETOptimisticOracle.OutcomeValue.False, "ipfs://e2", MIN_BOND);
    }

    function test_FinalizeOptimistic_SeedsPrecedent() public {
        uint256 claimId = _createClaim(eve);
        uint256 proposalId = _alicePropose(claimId, EMETOptimisticOracle.OutcomeValue.True);

        vm.warp(block.timestamp + 48 hours + 1);
        oracle.finalizeOptimistic(proposalId);

        // Precedent should have been recorded (precedentCount > 0)
        assertEq(precedentContract.precedentCount(), 1, "one precedent recorded");
    }

    function test_FinalizeOptimistic_ClearsActiveProposal() public {
        uint256 claimId = _createClaim(eve);
        uint256 proposalId = _alicePropose(claimId, EMETOptimisticOracle.OutcomeValue.True);

        vm.warp(block.timestamp + 48 hours + 1);
        oracle.finalizeOptimistic(proposalId);

        assertEq(oracle.activeProposal(claimId), 0, "active proposal cleared after finalization");
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. Dispute Tests
// ─────────────────────────────────────────────────────────────────────────────

contract EMETOptimisticOracle_DisputeTest is OracleTestBase {

    function test_Dispute_Success() public {
        uint256 claimId = _createClaim(eve);
        uint256 proposalId = _alicePropose(claimId, EMETOptimisticOracle.OutcomeValue.True);

        uint256 disputeBond = (MIN_BOND * 15_000) / 10_000;
        uint256 bobBalanceBefore = emet.balanceOf(bob);

        vm.prank(bob);
        oracle.disputeOutcome(proposalId, disputeBond);

        assertEq(emet.balanceOf(bob), bobBalanceBefore - disputeBond, "bob's dispute bond deducted");

        EMETOptimisticOracle.Proposal memory p = oracle.getProposal(proposalId);
        assertTrue(p.state == EMETOptimisticOracle.ProposalState.Disputed, "state should be Disputed");
        assertEq(p.disputer, bob);
        assertEq(p.disputeBond, disputeBond);
        assertGt(p.juryDeadline, 0, "jury deadline set");
    }

    function test_Dispute_EmitsEvent() public {
        uint256 claimId = _createClaim(eve);
        uint256 proposalId = _alicePropose(claimId, EMETOptimisticOracle.OutcomeValue.True);
        uint256 disputeBond = (MIN_BOND * 15_000) / 10_000;

        vm.prank(bob);
        vm.expectEmit(true, true, true, false);
        emit EMETOptimisticOracle.OutcomeDisputed(proposalId, claimId, bob, disputeBond, 0);
        oracle.disputeOutcome(proposalId, disputeBond);
    }

    function test_Dispute_RevertIfBondTooLow() public {
        uint256 claimId = _createClaim(eve);
        uint256 proposalId = _alicePropose(claimId, EMETOptimisticOracle.OutcomeValue.True);
        uint256 requiredBond = (MIN_BOND * 15_000) / 10_000;

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(EMETOptimisticOracle.InsufficientBond.selector, MIN_BOND, requiredBond)
        );
        oracle.disputeOutcome(proposalId, MIN_BOND); // only 1×, not 1.5×
    }

    function test_Dispute_RevertIfSelfDispute() public {
        uint256 claimId = _createClaim(eve);
        uint256 proposalId = _alicePropose(claimId, EMETOptimisticOracle.OutcomeValue.True);
        uint256 disputeBond = (MIN_BOND * 15_000) / 10_000;

        vm.prank(alice);
        vm.expectRevert(EMETOptimisticOracle.CannotDisputeOwnProposal.selector);
        oracle.disputeOutcome(proposalId, disputeBond);
    }

    function test_Dispute_RevertIfWindowClosed() public {
        uint256 claimId = _createClaim(eve);
        uint256 proposalId = _alicePropose(claimId, EMETOptimisticOracle.OutcomeValue.True);
        uint256 disputeBond = (MIN_BOND * 15_000) / 10_000;

        vm.warp(block.timestamp + 48 hours + 1); // past window

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                EMETOptimisticOracle.ChallengeWindowClosed.selector,
                proposalId,
                block.timestamp - 1 // challengeDeadline is in the past
            )
        );
        oracle.disputeOutcome(proposalId, disputeBond);
    }

    function test_Dispute_RevertIfNotPending() public {
        uint256 claimId = _createClaim(eve);
        uint256 proposalId = _alicePropose(claimId, EMETOptimisticOracle.OutcomeValue.True);

        // First dispute from bob
        _bobDispute(proposalId);

        // Second dispute attempt from eve
        uint256 disputeBond = (MIN_BOND * 15_000) / 10_000;
        vm.prank(eve);
        vm.expectRevert(
            abi.encodeWithSelector(
                EMETOptimisticOracle.ProposalNotPending.selector,
                proposalId,
                EMETOptimisticOracle.ProposalState.Disputed
            )
        );
        oracle.disputeOutcome(proposalId, disputeBond);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. Jury Voting Tests
// ─────────────────────────────────────────────────────────────────────────────

contract EMETOptimisticOracle_JuryVoteTest is OracleTestBase {

    uint256 proposalId;

    function setUp() public override {
        super.setUp();
        uint256 claimId = _createClaim(eve);
        proposalId = _alicePropose(claimId, EMETOptimisticOracle.OutcomeValue.True);
        _bobDispute(proposalId);
        _seedJury(proposalId);
    }

    function test_JuryVote_Success() public {
        vm.prank(juror1);
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.True, "Evidence checks out");

        (EMETOptimisticOracle.OutcomeValue v,,) = _getJurorVote(juror1);
        assertTrue(v == EMETOptimisticOracle.OutcomeValue.True);
    }

    function test_JuryVote_EmitsEvent() public {
        vm.prank(juror1);
        vm.expectEmit(true, true, false, true);
        emit EMETOptimisticOracle.JuryVoteCast(
            proposalId, juror1, EMETOptimisticOracle.OutcomeValue.True, "Evidence checks out"
        );
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.True, "Evidence checks out");
    }

    function test_JuryVote_RevertIfNotJuror() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(EMETOptimisticOracle.NotAJuror.selector, alice));
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.True, "I'm not a juror");
    }

    function test_JuryVote_RevertIfAlreadyVoted() public {
        vm.prank(juror1);
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.True, "First vote");

        vm.prank(juror1);
        vm.expectRevert(
            abi.encodeWithSelector(EMETOptimisticOracle.AlreadyVoted.selector, juror1, proposalId)
        );
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.False, "Changing my mind");
    }

    function test_JuryVote_RevertIfWindowClosed() public {
        // Get the actual jury deadline from the proposal
        EMETOptimisticOracle.Proposal memory p = oracle.getProposal(proposalId);
        uint256 juryDeadline = p.juryDeadline;

        vm.warp(block.timestamp + 24 hours + 1);

        vm.prank(juror1);
        vm.expectRevert(
            abi.encodeWithSelector(EMETOptimisticOracle.JuryWindowClosed.selector, proposalId, juryDeadline)
        );
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.True, "Late vote");
    }

    function test_JuryVote_RevertIfInvalidOutcome() public {
        vm.prank(juror1);
        vm.expectRevert(EMETOptimisticOracle.InvalidOutcome.selector);
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.None, "None vote");
    }

    function test_JuryVote_GetVoteCounts() public {
        vm.prank(juror1);
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.True, "True");
        vm.prank(juror2);
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.False, "False");
        // juror3 doesn't vote

        (uint256 trueV, uint256 falseV, uint256 noV) = oracle.getDisputeVoteCounts(proposalId);
        assertEq(trueV, 1, "1 true vote");
        assertEq(falseV, 1, "1 false vote");
        assertEq(noV, 1, "1 no vote");
    }

    function _getJurorVote(address juror)
        internal
        view
        returns (EMETOptimisticOracle.OutcomeValue v, string memory reasoning, uint256 ts)
    {
        (v, reasoning, ts) = oracle.jurorVotes(proposalId, juror);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. Dispute Resolution Tests
// ─────────────────────────────────────────────────────────────────────────────

contract EMETOptimisticOracle_ResolveTest is OracleTestBase {

    uint256 proposalId;
    uint256 claimId;

    function setUp() public override {
        super.setUp();
        claimId = _createClaim(eve);
        proposalId = _alicePropose(claimId, EMETOptimisticOracle.OutcomeValue.True);
        _bobDispute(proposalId);
        _seedJury(proposalId);
    }

    // ── Proposer wins (jury says True, alice proposed True) ──────────────────

    function test_Resolve_ProposerWins_OutcomeFinalized() public {
        // Jury majority votes True → proposer (alice, who said True) wins
        vm.prank(juror1);
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.True, "True: evidence solid");
        vm.prank(juror2);
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.True, "True: verified");
        vm.prank(juror3);
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.False, "False: skeptical");

        vm.warp(block.timestamp + 24 hours + 1);
        oracle.resolveDispute(proposalId);

        (EMETOptimisticOracle.OutcomeValue outcome, EMETOptimisticOracle.OutcomeSource source,,) =
            oracle.getOutcome(claimId);
        assertTrue(outcome == EMETOptimisticOracle.OutcomeValue.True, "outcome should be True");
        assertTrue(source == EMETOptimisticOracle.OutcomeSource.JuryVerified, "source JuryVerified");
    }

    function test_Resolve_ProposerWins_BondReturned() public {
        // Alice starts at 1000 ETH, paid MIN_BOND=10 to propose → now has 990
        // Bob disputed with 1.5× = 15 ETH
        uint256 disputeBond = (MIN_BOND * 15_000) / 10_000; // 15 ETH

        // Capture balance AFTER propose (alice is at 990 here)
        uint256 aliceAfterPropose = emet.balanceOf(alice);

        // Jury votes True (proposer wins)
        vm.prank(juror1);
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.True, "True");
        vm.prank(juror2);
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.True, "True");

        vm.warp(block.timestamp + 24 hours + 1);
        oracle.resolveDispute(proposalId);

        // Alice gets: her bond back (10) + bob's bond minus 5% protocol fee (15 - 0.75 = 14.25)
        uint256 protocolFee = (disputeBond * 500) / 10_000; // 5% = 0.75 ETH
        uint256 winnerBonus = disputeBond - protocolFee;    // 14.25 ETH
        // Total: 990 (current) + 10 (bond returned) + 14.25 (bonus) = 1014.25
        uint256 aliceExpected = aliceAfterPropose + MIN_BOND + winnerBonus;

        assertEq(emet.balanceOf(alice), aliceExpected, "alice should receive bond back + bob's bond minus fee");
    }

    function test_Resolve_DisputerWins_OutcomeFinalized() public {
        // Jury majority votes False → disputer (bob, who implicitly says False) wins
        // alice proposed True, jury says False → alice was wrong
        vm.prank(juror1);
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.False, "False: claim incorrect");
        vm.prank(juror2);
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.False, "False: evidence disputed");
        vm.prank(juror3);
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.True, "True: partial evidence");

        vm.warp(block.timestamp + 24 hours + 1);
        oracle.resolveDispute(proposalId);

        (EMETOptimisticOracle.OutcomeValue outcome, EMETOptimisticOracle.OutcomeSource source,,) =
            oracle.getOutcome(claimId);
        // Jury said False, disputer wins, outcome is False
        assertTrue(outcome == EMETOptimisticOracle.OutcomeValue.False, "outcome should be False (jury overruled proposer)");
        assertTrue(source == EMETOptimisticOracle.OutcomeSource.JuryVerified, "source JuryVerified");
    }

    function test_Resolve_DisputerWins_DisputeBondReturned() public {
        // In setUp, bob already disputed (paid 15 ETH). Bob has 985 at this point.
        uint256 bobAfterDispute = emet.balanceOf(bob); // 985
        uint256 disputeBond = (MIN_BOND * 15_000) / 10_000; // 15 ETH

        vm.prank(juror1);
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.False, "False");
        vm.prank(juror2);
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.False, "False");

        vm.warp(block.timestamp + 24 hours + 1);
        oracle.resolveDispute(proposalId);

        // Bob gets: his dispute bond back (15) + alice's proposal bond minus 5% (10 - 0.5 = 9.5)
        uint256 protocolFee = (MIN_BOND * PROTOCOL_FEE_BPS) / 10_000; // 5% of 10 = 0.5 ETH
        uint256 winnerBonus = MIN_BOND - protocolFee;                  // 9.5 ETH
        // Total: 985 (current) + 15 (dispute bond back) + 9.5 (winner bonus) = 1009.5
        uint256 bobExpected = bobAfterDispute + disputeBond + winnerBonus;

        assertEq(emet.balanceOf(bob), bobExpected, "bob should receive dispute bond back + alice's bond minus fee");
    }

    function test_Resolve_TieGoesToProposer() public {
        // 1 True, 1 False, 1 no-vote → trueVotes (1) >= falseVotes (1) → proposer wins
        vm.prank(juror1);
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.True, "True");
        vm.prank(juror2);
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.False, "False");
        // juror3 doesn't vote

        vm.warp(block.timestamp + 24 hours + 1);
        oracle.resolveDispute(proposalId);

        // trueVotes(1) >= falseVotes(1) → True, alice proposed True → proposer wins
        EMETOptimisticOracle.Proposal memory p = oracle.getProposal(proposalId);
        assertTrue(p.state == EMETOptimisticOracle.ProposalState.Finalized, "tie resolves to proposer win");
    }

    function test_Resolve_EmptyJury_DefaultsToTrue() public {
        // No one seeded the jury, no one voted → trueVotes(0) >= falseVotes(0) → True
        // Alice proposed True → proposer wins
        vm.warp(block.timestamp + 24 hours + 1);
        oracle.resolveDispute(proposalId);

        EMETOptimisticOracle.Proposal memory p = oracle.getProposal(proposalId);
        assertTrue(p.state == EMETOptimisticOracle.ProposalState.Finalized, "empty jury defaults to proposer win");
    }

    function test_Resolve_SeedsPrecedent() public {
        vm.prank(juror1);
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.True, "True: checked sources");
        vm.prank(juror2);
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.True, "True: verified on-chain");

        vm.warp(block.timestamp + 24 hours + 1);
        oracle.resolveDispute(proposalId);

        assertEq(precedentContract.precedentCount(), 1, "precedent recorded after jury resolve");
    }

    function test_Resolve_RevertBeforeJuryWindow() public {
        // Get jury deadline from the proposal
        EMETOptimisticOracle.Proposal memory p = oracle.getProposal(proposalId);
        uint256 juryDeadline = p.juryDeadline;

        vm.warp(block.timestamp + 12 hours); // jury window = 24h, only halfway through

        vm.expectRevert(
            abi.encodeWithSelector(EMETOptimisticOracle.JuryWindowOpen.selector, proposalId, juryDeadline)
        );
        oracle.resolveDispute(proposalId);
    }

    function test_Resolve_RevertIfNotDisputed() public {
        // Create a pending (non-disputed) proposal
        uint256 c2 = _createClaim(eve);
        vm.prank(alice);
        uint256 p2 = oracle.proposeOutcome(c2, EMETOptimisticOracle.OutcomeValue.True, "ipfs://e", MIN_BOND);

        vm.warp(block.timestamp + 24 hours + 1);
        vm.expectRevert(
            abi.encodeWithSelector(EMETOptimisticOracle.ProposalNotDisputed.selector, p2)
        );
        oracle.resolveDispute(p2);
    }

    function test_Resolve_UpdatesReputation() public {
        vm.prank(juror1);
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.True, "True");
        vm.prank(juror2);
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.True, "True");

        vm.warp(block.timestamp + 24 hours + 1);
        oracle.resolveDispute(proposalId);

        // Proposer (alice) won → claimVerifiedCount++
        // Disputer (bob) lost → challengeFailedCount++
        MockReputation rep = MockReputation(address(reputation));
        assertEq(rep.claimVerifiedCount(alice), 1, "alice reputation: claim verified");
        assertEq(rep.challengeFailedCount(bob), 1, "bob reputation: challenge failed");
    }

    function test_Resolve_DisputerWins_UpdatesReputation() public {
        vm.prank(juror1);
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.False, "False");
        vm.prank(juror2);
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.False, "False");

        vm.warp(block.timestamp + 24 hours + 1);
        oracle.resolveDispute(proposalId);

        MockReputation rep = MockReputation(address(reputation));
        assertEq(rep.challengeFailedCount(alice), 1, "alice reputation: challenge failed (wrong proposal)");
        assertEq(rep.claimVerifiedCount(bob), 1, "bob reputation: claim verified (won dispute)");
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. Oracle Read Interface Tests
// ─────────────────────────────────────────────────────────────────────────────

contract EMETOptimisticOracle_ReadTest is OracleTestBase {

    function test_GetOutcome_BeforeFinalization() public {
        uint256 claimId = _createClaim(eve);
        (EMETOptimisticOracle.OutcomeValue outcome, , uint256 finalizedAt,) = oracle.getOutcome(claimId);
        assertTrue(outcome == EMETOptimisticOracle.OutcomeValue.None, "no outcome before finalization");
        assertEq(finalizedAt, 0, "not finalized yet");
    }

    function test_HasOutcome_FalseBeforeFinalization() public {
        uint256 claimId = _createClaim(eve);
        assertFalse(oracle.hasOutcome(claimId));
    }

    function test_GetFinalizedOutcome_OptimisticPath() public {
        uint256 claimId = _createClaim(eve);
        uint256 proposalId = _alicePropose(claimId, EMETOptimisticOracle.OutcomeValue.False);

        vm.warp(block.timestamp + 48 hours + 1);
        oracle.finalizeOptimistic(proposalId);

        EMETOptimisticOracle.FinalizedOutcome memory fo = oracle.getFinalizedOutcome(claimId);
        assertEq(fo.claimId, claimId);
        assertTrue(fo.outcome == EMETOptimisticOracle.OutcomeValue.False);
        assertTrue(fo.source == EMETOptimisticOracle.OutcomeSource.Optimistic);
        assertEq(fo.proposer, alice);
        assertGt(fo.finalizedAt, 0);
    }

    function test_GetProposal_NonExistent() public view {
        EMETOptimisticOracle.Proposal memory p = oracle.getProposal(999);
        assertEq(p.proposer, address(0), "non-existent proposal has zero proposer");
    }

    function test_MultipleClaims_IndependentOutcomes() public {
        uint256 c1 = _createClaim(eve);
        uint256 c2 = _createClaim(eve);

        uint256 p1 = _alicePropose(c1, EMETOptimisticOracle.OutcomeValue.True);

        vm.warp(block.timestamp + 48 hours + 1);
        oracle.finalizeOptimistic(p1);

        // c2 still has no outcome
        assertFalse(oracle.hasOutcome(c2), "c2 should not have an outcome");
        assertTrue(oracle.hasOutcome(c1), "c1 should have an outcome");

        (EMETOptimisticOracle.OutcomeValue o1,,, ) = oracle.getOutcome(c1);
        (EMETOptimisticOracle.OutcomeValue o2,,, ) = oracle.getOutcome(c2);

        assertTrue(o1 == EMETOptimisticOracle.OutcomeValue.True, "c1 is True");
        assertTrue(o2 == EMETOptimisticOracle.OutcomeValue.None, "c2 is None");
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 7. Jury Management (Owner Seeding) Tests
// ─────────────────────────────────────────────────────────────────────────────

contract EMETOptimisticOracle_JuryMgmtTest is OracleTestBase {

    function test_SeedJury_Success() public {
        uint256 claimId = _createClaim(eve);
        uint256 proposalId = _alicePropose(claimId, EMETOptimisticOracle.OutcomeValue.True);
        _bobDispute(proposalId);

        address[] memory jurors = new address[](3);
        jurors[0] = juror1;
        jurors[1] = juror2;
        jurors[2] = juror3;

        vm.prank(deployer);
        oracle.seedJury(proposalId, jurors);

        EMETOptimisticOracle.Proposal memory p = oracle.getProposal(proposalId);
        assertEq(p.jury.length, 3, "jury size should be 3");
        assertEq(p.jury[0], juror1);
        assertEq(p.jury[1], juror2);
        assertEq(p.jury[2], juror3);
    }

    function test_SeedJury_EmitsEvent() public {
        uint256 claimId = _createClaim(eve);
        uint256 proposalId = _alicePropose(claimId, EMETOptimisticOracle.OutcomeValue.True);
        _bobDispute(proposalId);

        address[] memory jurors = new address[](3);
        jurors[0] = juror1;
        jurors[1] = juror2;
        jurors[2] = juror3;

        vm.prank(deployer);
        vm.expectEmit(true, false, false, false);
        emit EMETOptimisticOracle.JurySelected(proposalId, jurors);
        oracle.seedJury(proposalId, jurors);
    }

    function test_SeedJury_RevertIfNotOwner() public {
        uint256 claimId = _createClaim(eve);
        uint256 proposalId = _alicePropose(claimId, EMETOptimisticOracle.OutcomeValue.True);
        _bobDispute(proposalId);

        address[] memory jurors = new address[](3);
        jurors[0] = juror1;
        jurors[1] = juror2;
        jurors[2] = juror3;

        vm.prank(alice); // not owner
        vm.expectRevert(EMETOptimisticOracle.OnlyOwner.selector);
        oracle.seedJury(proposalId, jurors);
    }

    function test_SeedJury_RevertIfWrongSize() public {
        uint256 claimId = _createClaim(eve);
        uint256 proposalId = _alicePropose(claimId, EMETOptimisticOracle.OutcomeValue.True);
        _bobDispute(proposalId);

        address[] memory jurors = new address[](2); // wrong size
        jurors[0] = juror1;
        jurors[1] = juror2;

        vm.prank(deployer);
        vm.expectRevert(EMETOptimisticOracle.InvalidOutcome.selector);
        oracle.seedJury(proposalId, jurors);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 8. End-to-End Integration Test
// ─────────────────────────────────────────────────────────────────────────────

contract EMETOptimisticOracle_E2ETest is OracleTestBase {

    /// @notice Full happy path: AI agent makes claim → oracle proposes True →
    ///         no disputes → finalized → downstream reads getOutcome()
    function test_E2E_OptimisticHappyPath() public {
        // Step 1: AI agent submitted a claim to EMET registry
        uint256 claimId = _createClaim(eve);
        assertFalse(oracle.hasOutcome(claimId), "no outcome yet");

        // Step 2: A watcher proposes the outcome (True: the claim was correct)
        uint256 proposalId = _alicePropose(claimId, EMETOptimisticOracle.OutcomeValue.True);
        assertEq(oracle.proposalCount(), 1);

        // Step 3: 48 hours pass with no disputes
        vm.warp(block.timestamp + 48 hours + 1);

        // Step 4: Anyone finalizes (here bob does it as a third party)
        vm.prank(bob);
        oracle.finalizeOptimistic(proposalId);

        // Step 5: Downstream AI agent reads the oracle
        (
            EMETOptimisticOracle.OutcomeValue outcome,
            EMETOptimisticOracle.OutcomeSource source,
            uint256 finalizedAt,
            address proposer
        ) = oracle.getOutcome(claimId);

        assertTrue(outcome == EMETOptimisticOracle.OutcomeValue.True, "claim was true");
        assertTrue(source == EMETOptimisticOracle.OutcomeSource.Optimistic, "optimistic resolution");
        assertGt(finalizedAt, 0);
        assertEq(proposer, alice);

        // Step 6: EMETPrecedent has a record for future jurors
        assertEq(precedentContract.precedentCount(), 1, "precedent seeded");
    }

    /// @notice Full disputed path: proposal → dispute → jury → resolve → oracle
    function test_E2E_DisputedPath() public {
        uint256 claimId = _createClaim(eve);

        // Alice proposes True
        uint256 proposalId = _alicePropose(claimId, EMETOptimisticOracle.OutcomeValue.True);

        // Bob disputes within window
        _bobDispute(proposalId);

        // Owner seeds jury
        _seedJury(proposalId);

        // Jurors vote: 2 True, 1 False → True wins → proposer wins
        vm.prank(juror1);
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.True,
            "Verified: block data confirms claim was accurate");
        vm.prank(juror2);
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.True,
            "Corroborated by external oracle");
        vm.prank(juror3);
        oracle.castJuryVote(proposalId, EMETOptimisticOracle.OutcomeValue.False,
            "Insufficient evidence");

        // Jury window ends
        vm.warp(block.timestamp + 24 hours + 1);
        oracle.resolveDispute(proposalId);

        // Oracle reflects jury-verified outcome
        (
            EMETOptimisticOracle.OutcomeValue outcome,
            EMETOptimisticOracle.OutcomeSource source,,
        ) = oracle.getOutcome(claimId);

        assertTrue(outcome == EMETOptimisticOracle.OutcomeValue.True, "jury confirmed True");
        assertTrue(source == EMETOptimisticOracle.OutcomeSource.JuryVerified, "jury-verified source");

        // Precedent has reasoning from all 3 jurors for future AI agents
        assertEq(precedentContract.precedentCount(), 1, "precedent with juror reasoning recorded");
    }
}
