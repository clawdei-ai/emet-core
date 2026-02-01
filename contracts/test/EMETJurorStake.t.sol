// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, console} from "forge-std/Test.sol";
import {EMETJurorStake} from "../src/EMETJurorStake.sol";
import {IEMET} from "../src/interfaces/IEMET.sol";

/// @title EMETJurorStake Tests
contract EMETJurorStakeTest is Test {
    EMETJurorStake public jurorStake;
    MockEMETJS public mockToken;

    address public challengeContract = address(100);
    address public juror1 = address(10);
    address public juror2 = address(11);
    address public juror3 = address(12);
    address public juror4 = address(13);

    uint256 public constant INITIAL_BALANCE = 10_000 ether;

    function setUp() public {
        // Deploy mock token at EMET address
        address emetAddress = 0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C;
        vm.etch(emetAddress, type(MockEMETJS).runtimeCode);
        mockToken = MockEMETJS(emetAddress);

        // Deploy juror stake with challenge contract
        jurorStake = new EMETJurorStake(challengeContract);

        // Fund jurors
        address[4] memory jurors = [juror1, juror2, juror3, juror4];
        for (uint256 i = 0; i < jurors.length; i++) {
            mockToken.mint(jurors[i], INITIAL_BALANCE);
            vm.prank(jurors[i]);
            mockToken.approve(address(jurorStake), type(uint256).max);
        }
    }

    // ============ Staking Tests ============

    function test_StakeOnVerdict_ForClaim() public {
        vm.prank(juror1);
        jurorStake.stakeOnVerdict(1, 10 ether, true);

        (uint256 amount, bool forClaim, bool claimed) = jurorStake.getJurorStake(1, juror1);
        assertEq(amount, 10 ether);
        assertTrue(forClaim);
        assertFalse(claimed);
    }

    function test_StakeOnVerdict_AgainstClaim() public {
        vm.prank(juror1);
        jurorStake.stakeOnVerdict(1, 10 ether, false);

        (uint256 amount, bool forClaim,) = jurorStake.getJurorStake(1, juror1);
        assertEq(amount, 10 ether);
        assertFalse(forClaim);
    }

    function test_StakeOnVerdict_MultipleJurors() public {
        vm.prank(juror1);
        jurorStake.stakeOnVerdict(1, 10 ether, true);
        vm.prank(juror2);
        jurorStake.stakeOnVerdict(1, 20 ether, true);
        vm.prank(juror3);
        jurorStake.stakeOnVerdict(1, 15 ether, false);

        (uint256 forClaim, uint256 againstClaim) = jurorStake.getTotalJurorStakes(1);
        assertEq(forClaim, 30 ether);
        assertEq(againstClaim, 15 ether);
    }

    function test_StakeOnVerdict_StakeTooLow() public {
        vm.expectRevert(
            abi.encodeWithSelector(EMETJurorStake.StakeTooLow.selector, 0.5 ether, 1 ether)
        );
        vm.prank(juror1);
        jurorStake.stakeOnVerdict(1, 0.5 ether, true);
    }

    function test_StakeOnVerdict_StakeTooHigh() public {
        vm.expectRevert(
            abi.encodeWithSelector(EMETJurorStake.StakeTooHigh.selector, 501 ether, 500 ether)
        );
        vm.prank(juror1);
        jurorStake.stakeOnVerdict(1, 501 ether, true);
    }

    function test_StakeOnVerdict_DoubleStake() public {
        vm.prank(juror1);
        jurorStake.stakeOnVerdict(1, 10 ether, true);

        vm.expectRevert(
            abi.encodeWithSelector(EMETJurorStake.AlreadyStaked.selector, 1, juror1)
        );
        vm.prank(juror1);
        jurorStake.stakeOnVerdict(1, 10 ether, false);
    }

    function test_StakeOnVerdict_AfterDistribution() public {
        vm.prank(juror1);
        jurorStake.stakeOnVerdict(1, 10 ether, true);

        vm.prank(challengeContract);
        jurorStake.distributeJurorStakes(1, true);

        vm.expectRevert(
            abi.encodeWithSelector(EMETJurorStake.AlreadyDistributed.selector, 1)
        );
        vm.prank(juror2);
        jurorStake.stakeOnVerdict(1, 10 ether, true);
    }

    function test_StakeOnVerdict_TokenTransfer() public {
        uint256 balBefore = mockToken.balanceOf(juror1);

        vm.prank(juror1);
        jurorStake.stakeOnVerdict(1, 10 ether, true);

        assertEq(mockToken.balanceOf(juror1), balBefore - 10 ether);
        assertEq(mockToken.balanceOf(address(jurorStake)), 10 ether);
    }

    // ============ Distribution Tests ============

    function test_Distribute_WinnersGetLoserStakes() public {
        // Juror1 and juror2 stake FOR claim (20 + 30 = 50 total)
        vm.prank(juror1);
        jurorStake.stakeOnVerdict(1, 20 ether, true);
        vm.prank(juror2);
        jurorStake.stakeOnVerdict(1, 30 ether, true);

        // Juror3 stakes AGAINST claim (40 total)
        vm.prank(juror3);
        jurorStake.stakeOnVerdict(1, 40 ether, false);

        uint256 j1Before = mockToken.balanceOf(juror1);
        uint256 j2Before = mockToken.balanceOf(juror2);
        uint256 j3Before = mockToken.balanceOf(juror3);

        // Claim upheld → for-claim jurors win
        vm.prank(challengeContract);
        jurorStake.distributeJurorStakes(1, true);

        // Total pool = 90 ether. Winner pool = 50, Loser pool = 40
        // Juror1 gets: (20/50) * 90 = 36 ether
        // Juror2 gets: (30/50) * 90 = 54 ether
        // Juror3 gets: 0 (lost everything)
        assertEq(mockToken.balanceOf(juror1) - j1Before, 36 ether);
        assertEq(mockToken.balanceOf(juror2) - j2Before, 54 ether);
        assertEq(mockToken.balanceOf(juror3), j3Before); // No change, lost it all
    }

    function test_Distribute_LoserLosesEverything() public {
        // One juror on wrong side
        vm.prank(juror1);
        jurorStake.stakeOnVerdict(1, 100 ether, false); // Stakes against claim

        vm.prank(juror2);
        jurorStake.stakeOnVerdict(1, 50 ether, true); // Stakes for claim

        uint256 j1Before = mockToken.balanceOf(juror1);

        // Claim upheld → juror1 on wrong side
        vm.prank(challengeContract);
        jurorStake.distributeJurorStakes(1, true);

        // Juror1 loses everything (was against claim, claim was upheld)
        assertEq(mockToken.balanceOf(juror1), j1Before);
    }

    function test_Distribute_OnlyWinnersNoLosers() public {
        // All jurors on same side
        vm.prank(juror1);
        jurorStake.stakeOnVerdict(1, 20 ether, true);
        vm.prank(juror2);
        jurorStake.stakeOnVerdict(1, 30 ether, true);

        uint256 j1Before = mockToken.balanceOf(juror1);
        uint256 j2Before = mockToken.balanceOf(juror2);

        vm.prank(challengeContract);
        jurorStake.distributeJurorStakes(1, true);

        // No losers → winners just get their stakes back
        assertEq(mockToken.balanceOf(juror1) - j1Before, 20 ether);
        assertEq(mockToken.balanceOf(juror2) - j2Before, 30 ether);
    }

    function test_Distribute_OnlyLosersNoWinners() public {
        // All jurors staked wrong side
        vm.prank(juror1);
        jurorStake.stakeOnVerdict(1, 20 ether, false);
        vm.prank(juror2);
        jurorStake.stakeOnVerdict(1, 30 ether, false);

        // Claim upheld → both on wrong side, but no winners to distribute to
        // Stakes stay in contract (effectively burned/locked)
        vm.prank(challengeContract);
        jurorStake.distributeJurorStakes(1, true);

        // Contract retains the funds (no winners)
        assertEq(mockToken.balanceOf(address(jurorStake)), 50 ether);
    }

    function test_Distribute_OnlyChallengeContract() public {
        vm.prank(juror1);
        jurorStake.stakeOnVerdict(1, 10 ether, true);

        vm.expectRevert(EMETJurorStake.OnlyChallengeContract.selector);
        vm.prank(juror1);
        jurorStake.distributeJurorStakes(1, true);
    }

    function test_Distribute_CannotDoubleDistribute() public {
        vm.prank(juror1);
        jurorStake.stakeOnVerdict(1, 10 ether, true);

        vm.prank(challengeContract);
        jurorStake.distributeJurorStakes(1, true);

        vm.expectRevert(
            abi.encodeWithSelector(EMETJurorStake.AlreadyDistributed.selector, 1)
        );
        vm.prank(challengeContract);
        jurorStake.distributeJurorStakes(1, true);
    }

    function test_Distribute_ChallengeNotUpheld() public {
        vm.prank(juror1);
        jurorStake.stakeOnVerdict(1, 20 ether, true);  // for claim
        vm.prank(juror2);
        jurorStake.stakeOnVerdict(1, 30 ether, false); // against claim

        uint256 j1Before = mockToken.balanceOf(juror1);
        uint256 j2Before = mockToken.balanceOf(juror2);

        // Claim NOT upheld → against-claim jurors win
        vm.prank(challengeContract);
        jurorStake.distributeJurorStakes(1, false);

        // Juror2 wins everything (pool = 50, winner pool = 30, loser = 20)
        // Juror2 gets: (30/30) * 50 = 50
        assertEq(mockToken.balanceOf(juror2) - j2Before, 50 ether);
        assertEq(mockToken.balanceOf(juror1), j1Before); // Lost everything
    }

    // ============ View Function Tests ============

    function test_GetStakedJurorCount() public {
        assertEq(jurorStake.getStakedJurorCount(1), 0);

        vm.prank(juror1);
        jurorStake.stakeOnVerdict(1, 10 ether, true);
        assertEq(jurorStake.getStakedJurorCount(1), 1);

        vm.prank(juror2);
        jurorStake.stakeOnVerdict(1, 10 ether, false);
        assertEq(jurorStake.getStakedJurorCount(1), 2);
    }

    function test_IsDistributed() public {
        assertFalse(jurorStake.isDistributed(1));

        vm.prank(juror1);
        jurorStake.stakeOnVerdict(1, 10 ether, true);

        vm.prank(challengeContract);
        jurorStake.distributeJurorStakes(1, true);

        assertTrue(jurorStake.isDistributed(1));
    }

    function test_CalculateExpectedPayout_Winner() public {
        vm.prank(juror1);
        jurorStake.stakeOnVerdict(1, 20 ether, true);
        vm.prank(juror2);
        jurorStake.stakeOnVerdict(1, 30 ether, false);

        // If claim upheld, juror1 wins
        uint256 expected = jurorStake.calculateExpectedPayout(1, juror1, true);
        assertEq(expected, 50 ether); // 20/20 * (20+30) = 50
    }

    function test_CalculateExpectedPayout_Loser() public {
        vm.prank(juror1);
        jurorStake.stakeOnVerdict(1, 20 ether, true);

        // If claim NOT upheld, juror1 loses
        uint256 expected = jurorStake.calculateExpectedPayout(1, juror1, false);
        assertEq(expected, 0);
    }

    function test_CalculateExpectedPayout_NoStake() public {
        uint256 expected = jurorStake.calculateExpectedPayout(1, juror1, true);
        assertEq(expected, 0);
    }

    // ============ Edge Cases ============

    function test_MaxStakeAmount() public {
        vm.prank(juror1);
        jurorStake.stakeOnVerdict(1, 500 ether, true);

        (uint256 amount,,) = jurorStake.getJurorStake(1, juror1);
        assertEq(amount, 500 ether);
    }

    function test_MinStakeAmount() public {
        vm.prank(juror1);
        jurorStake.stakeOnVerdict(1, 1 ether, true);

        (uint256 amount,,) = jurorStake.getJurorStake(1, juror1);
        assertEq(amount, 1 ether);
    }

    function test_MultipleChallenges_Independent() public {
        vm.prank(juror1);
        jurorStake.stakeOnVerdict(1, 10 ether, true);
        vm.prank(juror1);
        jurorStake.stakeOnVerdict(2, 20 ether, false);

        (uint256 amount1, bool for1,) = jurorStake.getJurorStake(1, juror1);
        (uint256 amount2, bool for2,) = jurorStake.getJurorStake(2, juror1);

        assertEq(amount1, 10 ether);
        assertTrue(for1);
        assertEq(amount2, 20 ether);
        assertFalse(for2);
    }

    function test_ZeroAddressConstructor() public {
        vm.expectRevert(EMETJurorStake.ZeroAddress.selector);
        new EMETJurorStake(address(0));
    }

    function test_Distribute_EmptyChallenge() public {
        // No stakes, just distribute
        vm.prank(challengeContract);
        jurorStake.distributeJurorStakes(99, true);

        assertTrue(jurorStake.isDistributed(99));
    }
}

// ============ Mock Token ============

contract MockEMETJS {
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
