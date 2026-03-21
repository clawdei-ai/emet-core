// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, console} from "forge-std/Test.sol";
import {EMETWatchtower} from "../src/EMETWatchtower.sol";

/// @title EMETWatchtower Tests
/// @notice Test suite for EMETWatchtower — v0.11.0 (dynamic repricing + watchtower bounties)

// ─────────────────────────────────────────────────────────────────────────────
// Registration tests
// ─────────────────────────────────────────────────────────────────────────────

contract EMETWatchtowerRegistrationTest is Test {
    EMETWatchtower wt;
    address treasury = address(0xBEEF);
    address alice = address(1);
    address bob = address(2);

    function setUp() public {
        wt = new EMETWatchtower(treasury);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function test_Register_Success() public {
        vm.prank(alice);
        wt.register{value: 0.001 ether}();

        (bool active, uint256 bond,,,,) = wt.watchtowers(alice);
        assertTrue(active, "alice should be active");
        assertEq(bond, 0.001 ether, "bond should be stored");
    }

    function test_Register_InsufficientBond() public {
        vm.expectRevert(
            abi.encodeWithSelector(EMETWatchtower.InsufficientBond.selector, 0.0005 ether, 0.001 ether)
        );
        vm.prank(alice);
        wt.register{value: 0.0005 ether}();
    }

    function test_Register_AlreadyRegistered() public {
        vm.startPrank(alice);
        wt.register{value: 0.001 ether}();
        vm.expectRevert(EMETWatchtower.AlreadyRegistered.selector);
        wt.register{value: 0.001 ether}();
        vm.stopPrank();
    }

    function test_Deregister_ReturnsBond() public {
        vm.prank(alice);
        wt.register{value: 0.001 ether}();

        uint256 balanceBefore = alice.balance;
        vm.prank(alice);
        wt.deregister();

        assertEq(alice.balance, balanceBefore + 0.001 ether, "bond should be returned");
        (bool active,,,,,) = wt.watchtowers(alice);
        assertFalse(active, "alice should be inactive after deregister");
    }

    function test_Deregister_NotRegistered() public {
        vm.expectRevert(EMETWatchtower.NotRegistered.selector);
        vm.prank(alice);
        wt.deregister();
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Flagging tests
// ─────────────────────────────────────────────────────────────────────────────

contract EMETWatchtowerFlaggingTest is Test {
    EMETWatchtower wt;
    address treasury = address(0xBEEF);
    address alice = address(1);
    address owner;

    uint256 constant CLAIM_ID = 42;
    bytes32 constant EVIDENCE = keccak256("ipfs://QmFakeEvidenceCID");

    function setUp() public {
        owner = address(this);
        wt = new EMETWatchtower(treasury);
        vm.deal(alice, 10 ether);

        // Register alice as a watchtower
        vm.prank(alice);
        wt.register{value: 0.001 ether}();

        // Record a claim (owner = test contract)
        wt.recordClaim(CLAIM_ID, 0.05 ether);
    }

    function test_Flag_Success() public {
        vm.prank(alice);
        wt.flag(CLAIM_ID, EVIDENCE);

        assertEq(wt.flagCount(CLAIM_ID), 1, "should have 1 flag");
        assertTrue(wt.hasActiveFlag(CLAIM_ID), "claim should have active flag");
    }

    function test_Flag_NotRegistered() public {
        address stranger = address(99);
        vm.expectRevert(EMETWatchtower.NotRegistered.selector);
        vm.prank(stranger);
        wt.flag(CLAIM_ID, EVIDENCE);
    }

    function test_Flag_ClaimNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(EMETWatchtower.ClaimNotFound.selector, 999));
        vm.prank(alice);
        wt.flag(999, EVIDENCE);
    }

    function test_Flag_MultipleFlags() public {
        address bob = address(2);
        vm.deal(bob, 10 ether);
        vm.prank(bob);
        wt.register{value: 0.001 ether}();

        vm.prank(alice);
        wt.flag(CLAIM_ID, EVIDENCE);

        vm.prank(bob);
        wt.flag(CLAIM_ID, keccak256("different evidence"));

        assertEq(wt.flagCount(CLAIM_ID), 2, "should have 2 flags");
    }

    function test_HasActiveFlag_FalseWhenNoneExist() public view {
        assertFalse(wt.hasActiveFlag(CLAIM_ID), "no flags yet");
    }

    function test_GetFlag_ReturnsFlagDetails() public {
        vm.prank(alice);
        wt.flag(CLAIM_ID, EVIDENCE);

        (address watcher, bytes32 evidence, uint256 flaggedAt, bool resolved, bool rewarded) =
            wt.getFlag(CLAIM_ID, 0);

        assertEq(watcher, alice, "watcher should be alice");
        assertEq(evidence, EVIDENCE, "evidence mismatch");
        assertEq(flaggedAt, block.timestamp, "flaggedAt should be now");
        assertFalse(resolved, "should not be resolved yet");
        assertFalse(rewarded, "should not be rewarded yet");
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dynamic repricing tests
// ─────────────────────────────────────────────────────────────────────────────

contract EMETWatchtowerRepricingTest is Test {
    EMETWatchtower wt;
    address treasury = address(0xBEEF);

    uint256 constant CLAIM_ID = 1;
    uint256 constant BASE_BOND = 0.0005 ether;

    function setUp() public {
        wt = new EMETWatchtower(treasury);
        wt.recordClaim(CLAIM_ID, 0.01 ether); // 1× stake threshold
    }

    function test_Bond_AtCreation_IsBase() public view {
        uint256 bond = wt.getChallengeBond(CLAIM_ID);
        // At t=0: timeMul=1×, stakeMul=1×, consensusMul=1× → BASE_BOND
        assertEq(bond, BASE_BOND, "bond at creation should equal BASE_BOND");
    }

    function test_Bond_RisesWithTime() public {
        uint256 bondDay0 = wt.getChallengeBond(CLAIM_ID);

        vm.warp(block.timestamp + 1 days);
        uint256 bondDay1 = wt.getChallengeBond(CLAIM_ID);

        assertGt(bondDay1, bondDay0, "bond should rise after 1 day");
    }

    function test_Bond_RisesWithStake() public {
        wt.recordClaim(99, 0.05 ether); // 5× stake threshold
        uint256 bondLow = wt.getChallengeBond(CLAIM_ID); // 0.01 ETH
        uint256 bondHigh = wt.getChallengeBond(99);      // 0.05 ETH

        assertGt(bondHigh, bondLow, "larger stake claim should have higher bond");
    }

    function test_Bond_FallsWithFlags() public {
        // Register a watchtower and add flags
        address alice = address(1);
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        wt.register{value: 0.001 ether}();

        uint256 bondBefore = wt.getChallengeBond(CLAIM_ID);

        vm.prank(alice);
        wt.flag(CLAIM_ID, keccak256("evidence1"));

        uint256 bondAfter = wt.getChallengeBond(CLAIM_ID);

        assertLt(bondAfter, bondBefore, "bond should decrease after a flag (consensus forming)");
    }

    function test_Bond_Capped_AtTenTimesBase() public {
        // Large stake + many days elapsed → should hit the cap
        wt.recordClaim(77, 1 ether); // 100× stake threshold
        vm.warp(block.timestamp + 30 days); // hit time cap
        uint256 bond = wt.getChallengeBond(77);
        assertLe(bond, BASE_BOND * 10, "bond should not exceed 10x BASE_BOND");
    }

    function test_Bond_Floor_HalfBase() public {
        // 10 flags → 50% consensus discount → could go below BASE_BOND/2 without floor
        address alice = address(1);
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        wt.register{value: 0.001 ether}();

        // Create a low-stake claim to exercise the floor
        wt.recordClaim(55, 0.0001 ether);

        for (uint256 i = 0; i < 10; i++) {
            vm.prank(alice);
            wt.flag(55, bytes32(i));
        }

        uint256 bond = wt.getChallengeBond(55);
        assertGe(bond, BASE_BOND / 2, "bond should not go below floor (BASE_BOND/2)");
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Slash split computation tests
// ─────────────────────────────────────────────────────────────────────────────

contract EMETWatchtowerSlashSplitTest is Test {
    EMETWatchtower wt;
    address treasury = address(0xBEEF);

    function setUp() public {
        wt = new EMETWatchtower(treasury);
    }

    function test_SlashSplit_WithWatchtower() public view {
        uint256 slash = 1 ether;
        (uint256 challenger, uint256 watchtower, uint256 treas) =
            wt.computeSlashSplit(slash, true);

        assertEq(challenger, 0.5 ether, "challenger: 50%");
        assertEq(watchtower, 0.2 ether, "watchtower: 20%");
        assertEq(treas, 0.3 ether, "treasury: 30%");
        assertEq(challenger + watchtower + treas, slash, "shares must sum to slash");
    }

    function test_SlashSplit_WithoutWatchtower() public view {
        uint256 slash = 1 ether;
        (uint256 challenger, uint256 watchtower, uint256 treas) =
            wt.computeSlashSplit(slash, false);

        assertEq(challenger, 0.5 ether, "challenger: 50%");
        assertEq(watchtower, 0, "watchtower: 0% (no watcher)");
        assertEq(treas, 0.5 ether, "treasury: 50% (absorbed watchtower's 20%)");
        assertEq(challenger + watchtower + treas, slash, "shares must sum to slash");
    }

    function test_SlashSplit_SmallAmount() public view {
        uint256 slash = 0.001 ether;
        (uint256 challenger, uint256 watchtower, uint256 treas) =
            wt.computeSlashSplit(slash, true);

        assertGt(challenger, 0, "challenger should get something");
        assertGt(treas, 0, "treasury should get something");
        // watchtower may round to 0 for tiny amounts, that's ok
        assertLe(challenger + watchtower + treas, slash, "no more than slash total");
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Flag resolution tests
// ─────────────────────────────────────────────────────────────────────────────

contract EMETWatchtowerResolutionTest is Test {
    EMETWatchtower wt;
    address treasury = address(0xBEEF);
    address alice = address(1);

    uint256 constant CLAIM_ID = 10;

    function setUp() public {
        wt = new EMETWatchtower(treasury);
        vm.deal(alice, 10 ether);
        vm.deal(address(wt), 1 ether); // pre-fund bounty pool

        vm.prank(alice);
        wt.register{value: 0.001 ether}();

        wt.recordClaim(CLAIM_ID, 0.02 ether);

        vm.prank(alice);
        wt.flag(CLAIM_ID, keccak256("evidence"));
    }

    function test_ResolveFlag_SlashSuccess_CreditsBounty() public {
        uint256 slashAmount = 0.02 ether;
        wt.resolveFlag(CLAIM_ID, 0, true, slashAmount);

        (, , , , uint256 earnedBounty,) = wt.watchtowers(alice);
        uint256 expectedBounty = (slashAmount * 2_000) / 10_000; // 20%
        assertEq(earnedBounty, expectedBounty, "alice should have earned 20% bounty");
    }

    function test_ResolveFlag_Dismissed_IncrementsMissedFlags() public {
        wt.resolveFlag(CLAIM_ID, 0, false, 0);

        (, , , uint256 missed,,) = wt.watchtowers(alice);
        assertEq(missed, 1, "missed flags should be 1");
    }

    function test_ResolveFlag_AlreadyResolved_Reverts() public {
        wt.resolveFlag(CLAIM_ID, 0, true, 0.02 ether);

        vm.expectRevert(
            abi.encodeWithSelector(EMETWatchtower.FlagAlreadyResolved.selector, CLAIM_ID, 0)
        );
        wt.resolveFlag(CLAIM_ID, 0, true, 0.02 ether);
    }

    function test_ResolveFlag_HasActiveFlagFalseAfterResolve() public {
        wt.resolveFlag(CLAIM_ID, 0, true, 0.02 ether);
        assertFalse(wt.hasActiveFlag(CLAIM_ID), "no active flags after resolution");
    }

    function test_WithdrawBounty() public {
        uint256 slashAmount = 0.02 ether;
        wt.resolveFlag(CLAIM_ID, 0, true, slashAmount);

        // Fund the bounty in the contract
        uint256 bounty = (slashAmount * 2_000) / 10_000;

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        wt.withdrawBounty();

        assertEq(alice.balance, aliceBefore + bounty, "alice should receive bounty");

        (, , , , uint256 remaining,) = wt.watchtowers(alice);
        assertEq(remaining, 0, "earned bounty should be zero after withdrawal");
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Slash farming prevention tests (integration with missed flag penalty)
// ─────────────────────────────────────────────────────────────────────────────

contract EMETWatchtowerSlashFarmingTest is Test {
    EMETWatchtower wt;
    address treasury;
    address badActor;

    function setUp() public {
        treasury = address(0xBEEF);
        badActor = address(42);
        vm.deal(badActor, 10 ether);
        vm.deal(treasury, 0 ether);

        wt = new EMETWatchtower(treasury);

        vm.prank(badActor);
        wt.register{value: 0.001 ether}();
    }

    function test_MissedFlagLimit_SlashesWatchtower() public {
        uint256 limit = wt.MISSED_FLAG_LIMIT();

        for (uint256 i = 0; i < limit; i++) {
            uint256 claimId = 1000 + i;
            wt.recordClaim(claimId, 0.01 ether);

            vm.prank(badActor);
            wt.flag(claimId, bytes32(i));

            // Resolve as dismissed (slash = false)
            wt.resolveFlag(claimId, 0, false, 0);
        }

        // After MISSED_FLAG_LIMIT dismissals, badActor should be deregistered
        (bool active,,,,,) = wt.watchtowers(badActor);
        assertFalse(active, "badActor should be deregistered after too many missed flags");
    }

    function test_MissedFlagLimit_BondSentToTreasury() public {
        uint256 limit = wt.MISSED_FLAG_LIMIT();
        uint256 treasuryBefore = treasury.balance;

        for (uint256 i = 0; i < limit; i++) {
            uint256 claimId = 2000 + i;
            wt.recordClaim(claimId, 0.01 ether);

            vm.prank(badActor);
            wt.flag(claimId, bytes32(i));

            wt.resolveFlag(claimId, 0, false, 0);
        }

        // Treasury should have received badActor's bond
        assertEq(treasury.balance, treasuryBefore + 0.001 ether, "treasury should receive slashed bond");
    }

    function test_GoodWatcher_NotSlashed() public {
        // Resolve 4 flags successfully (under limit)
        for (uint256 i = 0; i < 4; i++) {
            uint256 claimId = 3000 + i;
            wt.recordClaim(claimId, 0.01 ether);

            vm.prank(badActor);
            wt.flag(claimId, bytes32(i));

            // Successful slash — bounty credited
            wt.resolveFlag(claimId, 0, true, 0.01 ether);
        }

        (bool active,,,,,) = wt.watchtowers(badActor);
        assertTrue(active, "good watcher should remain active");
    }
}
