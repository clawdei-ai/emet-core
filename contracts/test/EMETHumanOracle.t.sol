// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, console} from "forge-std/Test.sol";
import {EMETHumanOracle} from "../src/EMETHumanOracle.sol";
import {EMETTreasury} from "../src/EMETTreasury.sol";
import {IEMET} from "../src/interfaces/IEMET.sol";

/// @title EMETHumanOracle Tests
contract EMETHumanOracleTest is Test {
    EMETHumanOracle public oracle;
    EMETTreasury public treasury;
    MockEMETHO public mockToken;

    address public treasuryAdmin = address(1);
    address public arbiter1 = address(10);
    address public arbiter2 = address(11);
    address public arbiter3 = address(12);
    address public arbiter4 = address(13);
    address public arbiter5 = address(14);
    address public escalator = address(20);

    uint256 public constant INITIAL_BALANCE = 100_000 ether;

    function setUp() public {
        // Deploy mock token
        address emetAddress = 0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C;
        vm.etch(emetAddress, type(MockEMETHO).runtimeCode);
        mockToken = MockEMETHO(emetAddress);

        // Deploy treasury
        treasury = new EMETTreasury(treasuryAdmin);

        // Deploy oracle
        oracle = new EMETHumanOracle(address(treasury));

        // Fund accounts
        address[6] memory accounts = [arbiter1, arbiter2, arbiter3, arbiter4, arbiter5, escalator];
        for (uint256 i = 0; i < accounts.length; i++) {
            mockToken.mint(accounts[i], INITIAL_BALANCE);
            vm.prank(accounts[i]);
            mockToken.approve(address(oracle), type(uint256).max);
        }
    }

    // ============ Registration Tests ============

    function test_RegisterArbiter_Success() public {
        vm.prank(arbiter1);
        uint256 id = oracle.registerArbiter("Alice", 5000 ether);

        assertEq(id, 1);
        assertEq(oracle.getActiveArbiterCount(), 1);

        EMETHumanOracle.HumanArbiter memory arb = oracle.getArbiter(id);
        assertEq(arb.addr, arbiter1);
        assertEq(arb.name, "Alice");
        assertEq(arb.stake, 5000 ether);
        assertTrue(arb.active);
        assertEq(arb.casesResolved, 0);
    }

    function test_RegisterArbiter_MultipleArbiters() public {
        vm.prank(arbiter1);
        oracle.registerArbiter("Alice", 5000 ether);
        vm.prank(arbiter2);
        oracle.registerArbiter("Bob", 6000 ether);
        vm.prank(arbiter3);
        oracle.registerArbiter("Charlie", 7000 ether);

        assertEq(oracle.getActiveArbiterCount(), 3);
        assertEq(oracle.arbiterCount(), 3);
    }

    function test_RegisterArbiter_InsufficientStake() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                EMETHumanOracle.InsufficientStake.selector,
                4999 ether,
                5000 ether
            )
        );
        vm.prank(arbiter1);
        oracle.registerArbiter("Alice", 4999 ether);
    }

    function test_RegisterArbiter_AlreadyRegistered() public {
        vm.prank(arbiter1);
        oracle.registerArbiter("Alice", 5000 ether);

        vm.expectRevert(
            abi.encodeWithSelector(EMETHumanOracle.AlreadyRegistered.selector, arbiter1)
        );
        vm.prank(arbiter1);
        oracle.registerArbiter("Alice2", 5000 ether);
    }

    function test_RegisterArbiter_TransfersTokens() public {
        uint256 balBefore = mockToken.balanceOf(arbiter1);

        vm.prank(arbiter1);
        oracle.registerArbiter("Alice", 5000 ether);

        assertEq(mockToken.balanceOf(arbiter1), balBefore - 5000 ether);
    }

    // ============ Deactivation Tests ============

    function test_DeactivateArbiter_Success() public {
        vm.prank(arbiter1);
        oracle.registerArbiter("Alice", 5000 ether);

        uint256 balBefore = mockToken.balanceOf(arbiter1);

        vm.prank(arbiter1);
        oracle.deactivateArbiter();

        assertEq(oracle.getActiveArbiterCount(), 0);
        assertEq(mockToken.balanceOf(arbiter1), balBefore + 5000 ether); // Stake returned
    }

    function test_DeactivateArbiter_NotRegistered() public {
        vm.expectRevert(
            abi.encodeWithSelector(EMETHumanOracle.NotRegistered.selector, arbiter1)
        );
        vm.prank(arbiter1);
        oracle.deactivateArbiter();
    }

    function test_DeactivateArbiter_AlreadyInactive() public {
        vm.prank(arbiter1);
        oracle.registerArbiter("Alice", 5000 ether);
        vm.prank(arbiter1);
        oracle.deactivateArbiter();

        vm.expectRevert(
            abi.encodeWithSelector(EMETHumanOracle.NotActiveArbiter.selector, arbiter1)
        );
        vm.prank(arbiter1);
        oracle.deactivateArbiter();
    }

    // ============ Escalation Tests ============

    function test_EscalateToHuman_Success() public {
        _registerArbiters(4); // Need 3 + 1 for exclusion

        vm.prank(escalator);
        uint256 escId = oracle.escalateToHuman(1, "Critical dispute needs human review", 5000 ether);

        assertEq(escId, 1);

        (
            uint256 challengeId,
            address esc,
            string memory reasoning,
            uint256 stake,
            uint256 votingEnd,
            EMETHumanOracle.EscalationStatus status,
            uint256[] memory arbiterIds,
            ,
            ,
        ) = oracle.getEscalation(escId);

        assertEq(challengeId, 1);
        assertEq(esc, escalator);
        assertEq(reasoning, "Critical dispute needs human review");
        assertEq(stake, 5000 ether);
        assertGt(votingEnd, block.timestamp);
        assertEq(uint256(status), uint256(EMETHumanOracle.EscalationStatus.Active));
        assertEq(arbiterIds.length, 3);
    }

    function test_EscalateToHuman_InsufficientStake() public {
        _registerArbiters(4);

        vm.expectRevert(
            abi.encodeWithSelector(
                EMETHumanOracle.InsufficientStake.selector,
                4999 ether,
                5000 ether
            )
        );
        vm.prank(escalator);
        oracle.escalateToHuman(1, "reason", 4999 ether);
    }

    function test_EscalateToHuman_InsufficientArbiters() public {
        _registerArbiters(2); // Need at least 3

        vm.expectRevert(
            abi.encodeWithSelector(EMETHumanOracle.InsufficientArbiters.selector, 2, 3)
        );
        vm.prank(escalator);
        oracle.escalateToHuman(1, "reason", 5000 ether);
    }

    function test_EscalateToHuman_DuplicateEscalation() public {
        _registerArbiters(4);

        vm.prank(escalator);
        oracle.escalateToHuman(1, "reason", 5000 ether);

        vm.expectRevert(
            abi.encodeWithSelector(EMETHumanOracle.EscalationAlreadyExists.selector, 1)
        );
        vm.prank(escalator);
        oracle.escalateToHuman(1, "reason2", 5000 ether);
    }

    function test_HasEscalation() public {
        _registerArbiters(4);

        assertFalse(oracle.hasEscalation(1));

        vm.prank(escalator);
        oracle.escalateToHuman(1, "reason", 5000 ether);

        assertTrue(oracle.hasEscalation(1));
    }

    // ============ Voting Tests ============

    function test_HumanVote_Success() public {
        uint256 escId = _createEscalation();

        (,,,,,,uint256[] memory arbiterIds,,,) = oracle.getEscalation(escId);

        EMETHumanOracle.HumanArbiter memory arb = oracle.getArbiter(arbiterIds[0]);

        vm.prank(arb.addr);
        oracle.humanVote(escId, true, "Claim is valid based on evidence");

        (bool upholdClaim, string memory reasoning, uint256 timestamp, bool hasVoted) =
            oracle.getArbiterVote(escId, arb.addr);

        assertTrue(upholdClaim);
        assertEq(reasoning, "Claim is valid based on evidence");
        assertGt(timestamp, 0);
        assertTrue(hasVoted);
    }

    function test_HumanVote_NotAssigned() public {
        uint256 escId = _createEscalation();

        address notArbiter = address(999);
        vm.expectRevert(
            abi.encodeWithSelector(EMETHumanOracle.NotAssignedArbiter.selector, notArbiter)
        );
        vm.prank(notArbiter);
        oracle.humanVote(escId, true, "reason");
    }

    function test_HumanVote_DoubleVote() public {
        uint256 escId = _createEscalation();

        (,,,,,,uint256[] memory arbiterIds,,,) = oracle.getEscalation(escId);
        EMETHumanOracle.HumanArbiter memory arb = oracle.getArbiter(arbiterIds[0]);

        vm.prank(arb.addr);
        oracle.humanVote(escId, true, "reason1");

        vm.expectRevert(
            abi.encodeWithSelector(EMETHumanOracle.AlreadyVoted.selector, arb.addr)
        );
        vm.prank(arb.addr);
        oracle.humanVote(escId, false, "changed my mind");
    }

    function test_HumanVote_AfterPeriodEnded() public {
        uint256 escId = _createEscalation();

        (,,,,,,uint256[] memory arbiterIds,,,) = oracle.getEscalation(escId);
        EMETHumanOracle.HumanArbiter memory arb = oracle.getArbiter(arbiterIds[0]);

        vm.warp(block.timestamp + 6 days); // Past 5-day voting period

        vm.expectRevert(EMETHumanOracle.VotingPeriodEnded.selector);
        vm.prank(arb.addr);
        oracle.humanVote(escId, true, "too late");
    }

    // ============ Resolution Tests ============

    function test_ResolveHumanEscalation_ClaimUpheld() public {
        uint256 escId = _createEscalation();
        _voteAllArbiters(escId, true); // All vote to uphold claim

        vm.warp(block.timestamp + 6 days);

        oracle.resolveHumanEscalation(escId);

        (,,,,,EMETHumanOracle.EscalationStatus status,,bool claimUpheld,uint256 forClaim,uint256 againstClaim) =
            oracle.getEscalation(escId);

        assertEq(uint256(status), uint256(EMETHumanOracle.EscalationStatus.Resolved));
        assertTrue(claimUpheld);
        assertEq(forClaim, 3);
        assertEq(againstClaim, 0);
    }

    function test_ResolveHumanEscalation_ChallengeUpheld() public {
        uint256 escId = _createEscalation();
        _voteAllArbiters(escId, false); // All vote against claim

        vm.warp(block.timestamp + 6 days);

        oracle.resolveHumanEscalation(escId);

        (,,,,,,,bool claimUpheld,uint256 forClaim,uint256 againstClaim) = oracle.getEscalation(escId);

        assertFalse(claimUpheld);
        assertEq(forClaim, 0);
        assertEq(againstClaim, 3);
    }

    function test_ResolveHumanEscalation_TiedVote_DefaultsToClaim() public {
        uint256 escId = _createEscalation();

        (,,,,,,uint256[] memory arbiterIds,,,) = oracle.getEscalation(escId);

        // 1 for, 1 against, 1 abstains (doesn't vote)
        EMETHumanOracle.HumanArbiter memory arb0 = oracle.getArbiter(arbiterIds[0]);
        EMETHumanOracle.HumanArbiter memory arb1 = oracle.getArbiter(arbiterIds[1]);

        vm.prank(arb0.addr);
        oracle.humanVote(escId, true, "for claim");
        vm.prank(arb1.addr);
        oracle.humanVote(escId, false, "against claim");

        vm.warp(block.timestamp + 6 days);
        oracle.resolveHumanEscalation(escId);

        (,,,,,,,bool claimUpheld,,) = oracle.getEscalation(escId);
        assertTrue(claimUpheld); // Tie goes to claim (status quo)
    }

    function test_ResolveHumanEscalation_VotingNotEnded() public {
        uint256 escId = _createEscalation();

        vm.expectRevert(EMETHumanOracle.VotingPeriodNotEnded.selector);
        oracle.resolveHumanEscalation(escId);
    }

    function test_ResolveHumanEscalation_AlreadyResolved() public {
        uint256 escId = _createEscalation();
        _voteAllArbiters(escId, true);
        vm.warp(block.timestamp + 6 days);

        oracle.resolveHumanEscalation(escId);

        vm.expectRevert(
            abi.encodeWithSelector(EMETHumanOracle.EscalationNotActive.selector, escId)
        );
        oracle.resolveHumanEscalation(escId);
    }

    // ============ Stake Distribution Tests ============

    function test_StakeDistribution_90_5_5_Split() public {
        uint256 escId = _createEscalation();
        _voteAllArbiters(escId, true);

        uint256 escalatorBefore = mockToken.balanceOf(escalator);
        uint256 treasuryBefore = mockToken.balanceOf(address(treasury));

        vm.warp(block.timestamp + 6 days);
        oracle.resolveHumanEscalation(escId);

        // 90% to escalator = 4500 ether
        assertEq(mockToken.balanceOf(escalator) - escalatorBefore, 4500 ether);

        // Treasury gets remainder (5% = 250, adjusted for integer division)
        assertGt(mockToken.balanceOf(address(treasury)) - treasuryBefore, 0);
    }

    function test_StakeDistribution_ArbitersGetPaid() public {
        uint256 escId = _createEscalation();

        (,,,,,,uint256[] memory arbiterIds,,,) = oracle.getEscalation(escId);

        // Get arbiter addresses
        EMETHumanOracle.HumanArbiter memory arb0 = oracle.getArbiter(arbiterIds[0]);
        uint256 arb0Before = mockToken.balanceOf(arb0.addr);

        _voteAllArbiters(escId, true);

        vm.warp(block.timestamp + 6 days);
        oracle.resolveHumanEscalation(escId);

        // Each arbiter should get portion of 5% = 250/3 = ~83 ether
        assertGt(mockToken.balanceOf(arb0.addr) - arb0Before, 0);
    }

    function test_ArbiterStatsUpdated() public {
        uint256 escId = _createEscalation();

        (,,,,,,uint256[] memory arbiterIds,,,) = oracle.getEscalation(escId);

        _voteAllArbiters(escId, true);

        vm.warp(block.timestamp + 6 days);
        oracle.resolveHumanEscalation(escId);

        EMETHumanOracle.HumanArbiter memory arb = oracle.getArbiter(arbiterIds[0]);
        assertEq(arb.casesResolved, 1);
        assertEq(arb.reputation, 10);
    }

    // ============ View Function Tests ============

    function test_GetActiveArbiterCount() public {
        assertEq(oracle.getActiveArbiterCount(), 0);

        vm.prank(arbiter1);
        oracle.registerArbiter("Alice", 5000 ether);

        assertEq(oracle.getActiveArbiterCount(), 1);
    }

    function test_ZeroAddressConstructor() public {
        vm.expectRevert(EMETHumanOracle.ZeroAddress.selector);
        new EMETHumanOracle(address(0));
    }

    // ============ Helpers ============

    function _registerArbiters(uint256 count) internal {
        address[5] memory addrs = [arbiter1, arbiter2, arbiter3, arbiter4, arbiter5];
        string[5] memory names = ["Alice", "Bob", "Charlie", "David", "Eve"];

        for (uint256 i = 0; i < count && i < 5; i++) {
            vm.prank(addrs[i]);
            oracle.registerArbiter(names[i], 5000 ether);
        }
    }

    function _createEscalation() internal returns (uint256 escId) {
        _registerArbiters(4); // 4 arbiters, need 3 non-escalator

        vm.prank(escalator);
        return oracle.escalateToHuman(1, "Critical dispute", 5000 ether);
    }

    function _voteAllArbiters(uint256 escId, bool upholdClaim) internal {
        (,,,,,,uint256[] memory arbiterIds,,,) = oracle.getEscalation(escId);

        for (uint256 i = 0; i < arbiterIds.length; i++) {
            EMETHumanOracle.HumanArbiter memory arb = oracle.getArbiter(arbiterIds[i]);
            vm.prank(arb.addr);
            oracle.humanVote(escId, upholdClaim, "Reasoning for vote");
        }
    }
}

// ============ Mock Token ============

contract MockEMETHO {
    string public name = "Mock EMET";
    string public symbol = "MEMET";
    uint8 public decimals = 18;

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
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
}
