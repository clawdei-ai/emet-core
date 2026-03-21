// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, console} from "forge-std/Test.sol";
import {EMETAgentProfile} from "../src/EMETAgentProfile.sol";

/// @title EMETAgentProfile.t.sol
/// @notice Tests for on-chain accuracy/risk-appetite separation (v0.10.0)
/// @dev Verifies that:
///   1. accuracyBps correctly tracks % of correct claims (0–10000 BPS)
///   2. riskAppetite classifies based on average stake size
///   3. Separating these two dimensions doesn't conflate them
///   4. Stake floor checks work based on requester tier
///   5. Bootstrap path (no history) handled correctly

contract EMETAgentProfileTest is Test {
    EMETAgentProfile public agentProfile;

    address public deployer = address(this);
    address public updater  = makeAddr("updater");

    address public alice     = makeAddr("alice");   // high accuracy, high risk
    address public bob       = makeAddr("bob");     // low accuracy, low risk
    address public charlie   = makeAddr("charlie"); // no history (bootstrap)
    address public diana     = makeAddr("diana");   // medium profile
    address public requester = makeAddr("requester");

    uint256 constant SMALL_STAKE   = 0.0001 ether;  // → Low appetite
    uint256 constant MEDIUM_STAKE  = 0.005 ether;   // → Medium appetite
    uint256 constant LARGE_STAKE   = 0.05 ether;    // → High appetite

    function setUp() public {
        agentProfile = new EMETAgentProfile();
        agentProfile.setUpdater(updater);
    }

    // ============ Updater Gate ============

    function test_onlyUpdater_canRecord() public {
        vm.expectRevert(EMETAgentProfile.OnlyUpdater.selector);
        agentProfile.recordCorrectClaim(alice, MEDIUM_STAKE);
    }

    function test_updaterCanRecord() public {
        vm.prank(updater);
        agentProfile.recordCorrectClaim(alice, MEDIUM_STAKE);
        assertEq(agentProfile.getProfile(alice).totalClaims, 1);
    }

    function test_updaterSetOnce() public {
        vm.expectRevert(EMETAgentProfile.UpdaterAlreadySet.selector);
        agentProfile.setUpdater(makeAddr("other"));
    }

    // ============ Accuracy Tracking ============

    function test_freshAddress_accuracy_isZero() public view {
        EMETAgentProfile.Profile memory p = agentProfile.getProfile(charlie);
        assertEq(p.accuracyBps, 0, "Fresh: no claims = 0 accuracy");
        assertEq(p.totalClaims, 0);
    }

    function test_allCorrect_accuracy100Pct() public {
        vm.startPrank(updater);
        agentProfile.recordCorrectClaim(alice, LARGE_STAKE);
        agentProfile.recordCorrectClaim(alice, LARGE_STAKE);
        agentProfile.recordCorrectClaim(alice, LARGE_STAKE);
        vm.stopPrank();

        EMETAgentProfile.Profile memory p = agentProfile.getProfile(alice);
        assertEq(p.totalClaims, 3);
        assertEq(p.correctClaims, 3);
        assertEq(p.slashCount, 0);
        assertEq(p.accuracyBps, 10_000, "3/3 correct = 100% = 10000 BPS");
    }

    function test_allSlashed_accuracy0Pct() public {
        vm.startPrank(updater);
        agentProfile.recordSlashedClaim(bob, SMALL_STAKE);
        agentProfile.recordSlashedClaim(bob, SMALL_STAKE);
        vm.stopPrank();

        EMETAgentProfile.Profile memory p = agentProfile.getProfile(bob);
        assertEq(p.slashCount, 2);
        assertEq(p.correctClaims, 0);
        assertEq(p.accuracyBps, 0, "0/2 correct = 0%");
    }

    function test_mixed_accuracy75Pct() public {
        vm.startPrank(updater);
        agentProfile.recordCorrectClaim(diana, MEDIUM_STAKE);
        agentProfile.recordCorrectClaim(diana, MEDIUM_STAKE);
        agentProfile.recordCorrectClaim(diana, MEDIUM_STAKE);
        agentProfile.recordSlashedClaim(diana, MEDIUM_STAKE);
        vm.stopPrank();

        EMETAgentProfile.Profile memory p = agentProfile.getProfile(diana);
        assertEq(p.totalClaims, 4);
        assertEq(p.correctClaims, 3);
        assertEq(p.slashCount, 1);
        assertEq(p.accuracyBps, 7_500, "3/4 correct = 75% = 7500 BPS");
    }

    // ============ Risk Appetite Classification ============

    function test_noStakeHistory_riskUnknown() public view {
        EMETAgentProfile.RiskAppetite r = agentProfile.getRiskAppetite(charlie);
        assertEq(uint256(r), uint256(EMETAgentProfile.RiskAppetite.Unknown));
    }

    function test_smallStake_riskLow() public {
        vm.prank(updater);
        agentProfile.recordCorrectClaim(bob, SMALL_STAKE); // 0.0001 ETH < 0.001 → Low
        assertEq(uint256(agentProfile.getRiskAppetite(bob)), uint256(EMETAgentProfile.RiskAppetite.Low));
    }

    function test_mediumStake_riskMedium() public {
        vm.prank(updater);
        agentProfile.recordCorrectClaim(diana, MEDIUM_STAKE); // 0.005 ETH → Medium
        assertEq(uint256(agentProfile.getRiskAppetite(diana)), uint256(EMETAgentProfile.RiskAppetite.Medium));
    }

    function test_largeStake_riskHigh() public {
        vm.prank(updater);
        agentProfile.recordCorrectClaim(alice, LARGE_STAKE); // 0.05 ETH → High
        assertEq(uint256(agentProfile.getRiskAppetite(alice)), uint256(EMETAgentProfile.RiskAppetite.High));
    }

    // ============ Key Property: Accuracy and Risk Are Independent ============

    /// @notice High-risk, occasionally-wrong agent can still have 90% accuracy
    function test_highRisk_highAccuracy_trustedAgent() public {
        vm.startPrank(updater);
        // 9 correct large-stake claims, 1 wrong
        for (uint256 i = 0; i < 9; i++) {
            agentProfile.recordCorrectClaim(alice, LARGE_STAKE);
        }
        agentProfile.recordSlashedClaim(alice, LARGE_STAKE);
        vm.stopPrank();

        EMETAgentProfile.Profile memory p = agentProfile.getProfile(alice);
        assertEq(p.accuracyBps, 9_000, "90% accuracy = 9000 BPS");
        assertEq(uint256(p.riskAppetite), uint256(EMETAgentProfile.RiskAppetite.High));
        // V1 would have lowered reputation due to slash. V2 shows accuracy correctly.
        assertTrue(p.accuracyBps >= 8_000, "90% accuracy meets Gold threshold");
    }

    /// @notice Low-risk, always-plays-safe agent may have only 50% accuracy
    function test_lowRisk_lowAccuracy_coinFlipAgent() public {
        vm.startPrank(updater);
        // 5 correct tiny-stake, 5 wrong — exactly 50%
        for (uint256 i = 0; i < 5; i++) {
            agentProfile.recordCorrectClaim(bob, SMALL_STAKE);
        }
        for (uint256 i = 0; i < 5; i++) {
            agentProfile.recordSlashedClaim(bob, SMALL_STAKE);
        }
        vm.stopPrank();

        EMETAgentProfile.Profile memory p = agentProfile.getProfile(bob);
        assertEq(p.accuracyBps, 5_000, "50% accuracy = 5000 BPS");
        assertEq(uint256(p.riskAppetite), uint256(EMETAgentProfile.RiskAppetite.Low));
        // V1 would have this agent appear "safe" (never challenged, low risk).
        // V2 correctly identifies 50% accuracy — not trustworthy for decisions.
        assertFalse(p.accuracyBps >= 8_000, "50% accuracy fails Gold threshold");
    }

    // ============ Accuracy Threshold Check ============

    function test_meetsAccuracyThreshold_true() public {
        vm.startPrank(updater);
        agentProfile.recordCorrectClaim(alice, MEDIUM_STAKE);
        agentProfile.recordCorrectClaim(alice, MEDIUM_STAKE);
        agentProfile.recordSlashedClaim(alice, MEDIUM_STAKE);
        vm.stopPrank();
        // 2/3 correct = 6666 BPS
        assertTrue(agentProfile.meetsAccuracyThreshold(alice, 6_000), "6666 BPS >= 6000 BPS threshold");
        assertFalse(agentProfile.meetsAccuracyThreshold(alice, 8_000), "6666 BPS < 8000 BPS threshold");
    }

    function test_meetsAccuracyThreshold_noHistory_false() public view {
        // Bootstrap path: no history → does not meet any threshold
        assertFalse(agentProfile.meetsAccuracyThreshold(charlie, 1), "No history fails any threshold");
    }

    // ============ Stake Floor by Requester Tier ============

    /// @notice Gold-tier requester requires candidate avg >= 0.01 ETH
    function test_stakFloor_goldRequester_blocksLowAvg() public {
        // Build Gold-tier requester (80%+ accuracy, 20+ claims)
        vm.startPrank(updater);
        for (uint256 i = 0; i < 20; i++) {
            agentProfile.recordCorrectClaim(requester, LARGE_STAKE);
        }
        // Candidate has LOW risk appetite (small stakes)
        agentProfile.recordCorrectClaim(charlie, SMALL_STAKE);
        vm.stopPrank();

        (bool meetsFloor, uint256 floorWei) = agentProfile.meetsStakeFloor(charlie, requester);
        assertEq(floorWei, 0.01 ether, "Gold floor = 0.01 ETH");
        assertFalse(meetsFloor, "Low-stake candidate fails Gold floor");
    }

    /// @notice Bronze-tier requester has no floor (bootstrap always passes)
    function test_stakeFloor_bronzeRequester_noFloor() public view {
        (bool meetsFloor, uint256 floorWei) = agentProfile.meetsStakeFloor(charlie, requester);
        assertEq(floorWei, 0, "Bronze floor = 0 (no floor)");
        assertTrue(meetsFloor, "Bronze requester: bootstrap path always passes");
    }

    /// @notice High avg stake candidate passes Gold floor
    function test_stakeFloor_highStakeCandidate_passesGold() public {
        // Build Gold requester
        vm.startPrank(updater);
        for (uint256 i = 0; i < 20; i++) {
            agentProfile.recordCorrectClaim(requester, LARGE_STAKE);
        }
        // Candidate with HIGH avg stake
        agentProfile.recordCorrectClaim(alice, LARGE_STAKE); // 0.05 ETH >> 0.01 ETH
        vm.stopPrank();

        (bool meetsFloor,) = agentProfile.meetsStakeFloor(alice, requester);
        assertTrue(meetsFloor, "High-stake candidate passes Gold floor");
    }

    // ============ Tier Labels ============

    function test_tierLabel_bronze() public view {
        assertEq(agentProfile.tierLabel(charlie), "Bronze");
    }

    function test_tierLabel_gold() public {
        vm.startPrank(updater);
        for (uint256 i = 0; i < 20; i++) {
            agentProfile.recordCorrectClaim(alice, LARGE_STAKE);
        }
        vm.stopPrank();
        assertEq(agentProfile.tierLabel(alice), "Gold");
    }

    function test_riskLabel() public {
        vm.prank(updater);
        agentProfile.recordCorrectClaim(alice, LARGE_STAKE);
        assertEq(agentProfile.riskLabel(alice), "High");
        assertEq(agentProfile.riskLabel(charlie), "Unknown");
    }

    // ============ avgStakeWei Rolling Average ============

    function test_avgStake_rollsCorrectly() public {
        vm.startPrank(updater);
        agentProfile.recordCorrectClaim(alice, 1 ether);   // total = 1 ETH, count = 1, avg = 1 ETH
        agentProfile.recordCorrectClaim(alice, 0 ether);   // wait — 0 stake is valid but trivial
        agentProfile.recordSlashedClaim(alice, 2 ether);   // total = 3 ETH, count = 3, avg = 1 ETH
        vm.stopPrank();

        EMETAgentProfile.Profile memory p = agentProfile.getProfile(alice);
        assertEq(p.totalStakeWei, 3 ether);
        assertEq(p.totalClaims, 3);
        assertEq(p.avgStakeWei, 1 ether);
        assertEq(uint256(p.riskAppetite), uint256(EMETAgentProfile.RiskAppetite.High));
    }
}
