// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, console} from "forge-std/Test.sol";
import {EMETDecay} from "../src/EMETDecay.sol";
import {EMETRegistry} from "../src/EMETRegistry.sol";
import {IEMET} from "../src/interfaces/IEMET.sol";

/// @title EMETDecay Tests
contract EMETDecayTest is Test {
    EMETDecay public decay;
    EMETRegistry public registry;
    MockEMETDC public mockToken;

    address public deployer = address(1);
    address public submitter = address(10);
    address public refresher = address(11);
    address public reporter = address(12);

    uint256 public constant MINIMUM_STAKE = 10 ether;
    uint256 public constant CHALLENGE_PERIOD = 7 days;
    uint256 public constant INITIAL_BALANCE = 100_000 ether;

    function setUp() public {
        // Deploy mock token
        address emetAddress = 0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C;
        vm.etch(emetAddress, type(MockEMETDC).runtimeCode);
        mockToken = MockEMETDC(emetAddress);

        // Deploy registry
        registry = new EMETRegistry(MINIMUM_STAKE, CHALLENGE_PERIOD);

        // Deploy decay
        decay = new EMETDecay(address(registry));

        // Fund accounts
        address[3] memory accounts = [submitter, refresher, reporter];
        for (uint256 i = 0; i < accounts.length; i++) {
            mockToken.mint(accounts[i], INITIAL_BALANCE);
            vm.prank(accounts[i]);
            mockToken.approve(address(registry), type(uint256).max);
            vm.prank(accounts[i]);
            mockToken.approve(address(decay), type(uint256).max);
        }

        // Fund decay contract for stale report rewards
        mockToken.mint(address(decay), 1000 ether);
    }

    // ============ Weight Calculation Tests ============

    function test_Weight_FreshClaim_100() public {
        uint256 claimId = _submitClaim();

        uint256 weight = decay.getClaimWeight(claimId);
        assertEq(weight, 100);
    }

    function test_Weight_At30Days_100() public {
        uint256 claimId = _submitClaim();

        vm.warp(block.timestamp + 30 days);

        uint256 weight = decay.getClaimWeight(claimId);
        assertEq(weight, 100); // Still in grace period
    }

    function test_Weight_At89Days_100() public {
        uint256 claimId = _submitClaim();

        vm.warp(block.timestamp + 89 days);

        uint256 weight = decay.getClaimWeight(claimId);
        assertEq(weight, 100); // Still in grace period (just before 90 days)
    }

    function test_Weight_At90Days_StillFull() public {
        uint256 claimId = _submitClaim();

        vm.warp(block.timestamp + 90 days);

        uint256 weight = decay.getClaimWeight(claimId);
        assertEq(weight, 100); // Exactly at boundary, decay hasn't started
    }

    function test_Weight_At91Days_StartDecaying() public {
        uint256 claimId = _submitClaim();

        // At 91 days, 1 day into the 275-day decay range
        // Weight = 100 - (1 * 90 / 275) = 100 - 0 (integer division, rounds down)
        // Need slightly more elapsed time to see a noticeable drop
        vm.warp(block.timestamp + 95 days);

        uint256 weight = decay.getClaimWeight(claimId);
        assertLt(weight, 100); // Has started decaying
        assertGt(weight, 90); // Should be close to 100
    }

    function test_Weight_AtHalfway_About55() public {
        uint256 claimId = _submitClaim();

        // Halfway through decay period: 90 + (365-90)/2 = 90 + 137.5 = 227.5 days
        vm.warp(block.timestamp + 227 days);

        uint256 weight = decay.getClaimWeight(claimId);
        // Should be roughly 55 (midway between 100 and 10)
        assertGt(weight, 50);
        assertLt(weight, 60);
    }

    function test_Weight_At365Days_Minimum() public {
        uint256 claimId = _submitClaim();

        vm.warp(block.timestamp + 365 days);

        uint256 weight = decay.getClaimWeight(claimId);
        assertEq(weight, 10); // Fully decayed
    }

    function test_Weight_At500Days_StillMinimum() public {
        uint256 claimId = _submitClaim();

        vm.warp(block.timestamp + 500 days);

        uint256 weight = decay.getClaimWeight(claimId);
        assertEq(weight, 10); // Floor doesn't go below 10
    }

    function test_Weight_At1000Days_StillMinimum() public {
        uint256 claimId = _submitClaim();

        vm.warp(block.timestamp + 1000 days);

        uint256 weight = decay.getClaimWeight(claimId);
        assertEq(weight, 10);
    }

    // ============ Decay Stages (Linear Decay) ============

    function test_Weight_LinearDecay_Stages() public {
        uint256 claimId = _submitClaim();

        // At 90 days (0% decay)
        vm.warp(block.timestamp + 90 days);
        assertEq(decay.getClaimWeight(claimId), 100);

        // At ~90 + 27.5 = ~117 days (10% through decay, weight ~91)
        vm.warp(block.timestamp + 28 days); // total: 118 days
        uint256 w1 = decay.getClaimWeight(claimId);
        assertGt(w1, 85);
        assertLt(w1, 95);

        // At 365 days (100% decay)
        vm.warp(block.timestamp + 247 days); // total: 365 days
        assertEq(decay.getClaimWeight(claimId), 10);
    }

    // ============ NeedsRefresh Tests ============

    function test_NeedsRefresh_FreshClaim() public {
        uint256 claimId = _submitClaim();
        assertFalse(decay.needsRefresh(claimId));
    }

    function test_NeedsRefresh_DecayedBelow50() public {
        uint256 claimId = _submitClaim();

        // Weight goes below 50 at about 240 days
        vm.warp(block.timestamp + 260 days);

        assertTrue(decay.needsRefresh(claimId));
    }

    function test_NeedsRefresh_FullyDecayed() public {
        uint256 claimId = _submitClaim();

        vm.warp(block.timestamp + 400 days);
        assertTrue(decay.needsRefresh(claimId));
    }

    // ============ Time Until Decay Tests ============

    function test_TimeUntilDecay_FreshClaim() public {
        uint256 claimId = _submitClaim();

        uint256 timeLeft = decay.timeUntilDecay(claimId);
        assertEq(timeLeft, 90 days);
    }

    function test_TimeUntilDecay_AlreadyDecaying() public {
        uint256 claimId = _submitClaim();

        vm.warp(block.timestamp + 100 days);

        uint256 timeLeft = decay.timeUntilDecay(claimId);
        assertEq(timeLeft, 0);
    }

    function test_TimeUntilFullDecay_FreshClaim() public {
        uint256 claimId = _submitClaim();

        uint256 timeLeft = decay.timeUntilFullDecay(claimId);
        assertEq(timeLeft, 365 days);
    }

    function test_TimeUntilFullDecay_FullyDecayed() public {
        uint256 claimId = _submitClaim();

        vm.warp(block.timestamp + 400 days);

        uint256 timeLeft = decay.timeUntilFullDecay(claimId);
        assertEq(timeLeft, 0);
    }

    // ============ Refresh Tests ============

    function test_RefreshClaim_ResetsWeight() public {
        uint256 claimId = _submitClaim();

        // Decay to ~50%
        vm.warp(block.timestamp + 250 days);

        uint256 weightBefore = decay.getClaimWeight(claimId);
        assertLt(weightBefore, 60);

        // Refresh
        vm.prank(refresher);
        decay.refreshClaim(claimId, 1 ether); // 10% of 10 ether stake

        uint256 weightAfter = decay.getClaimWeight(claimId);
        assertEq(weightAfter, 100); // Reset to full weight
    }

    function test_RefreshClaim_AnyoneCanRefresh() public {
        uint256 claimId = _submitClaim();

        vm.warp(block.timestamp + 200 days);

        // Refresher is not the submitter
        vm.prank(refresher);
        decay.refreshClaim(claimId, 1 ether);

        assertEq(decay.getClaimWeight(claimId), 100);
    }

    function test_RefreshClaim_InsufficientStake() public {
        uint256 claimId = _submitClaim();

        vm.expectRevert(
            abi.encodeWithSelector(
                EMETDecay.InsufficientRefreshStake.selector,
                0.5 ether,
                1 ether // 10% of 10 ether
            )
        );
        vm.prank(refresher);
        decay.refreshClaim(claimId, 0.5 ether);
    }

    function test_RefreshClaim_UpdatesStats() public {
        uint256 claimId = _submitClaim();

        vm.prank(refresher);
        decay.refreshClaim(claimId, 2 ether);

        assertEq(decay.refreshCount(claimId), 1);
        assertEq(decay.refreshStakes(claimId), 2 ether);

        // Refresh again
        vm.prank(refresher);
        decay.refreshClaim(claimId, 1 ether);

        assertEq(decay.refreshCount(claimId), 2);
        assertEq(decay.refreshStakes(claimId), 3 ether);
    }

    function test_RefreshClaim_ClearsStaleFlag() public {
        uint256 claimId = _submitClaim();

        // Decay and report as stale
        vm.warp(block.timestamp + 300 days);
        vm.prank(reporter);
        decay.reportStaleClaim(claimId);
        assertTrue(decay.flaggedStale(claimId));

        // Refresh clears the flag
        vm.prank(refresher);
        decay.refreshClaim(claimId, 1 ether);
        assertFalse(decay.flaggedStale(claimId));
    }

    function test_RefreshClaim_MultipleRefreshes() public {
        uint256 claimId = _submitClaim();

        // Decay partially
        vm.warp(block.timestamp + 200 days);
        assertLt(decay.getClaimWeight(claimId), 100);

        // First refresh
        vm.prank(refresher);
        decay.refreshClaim(claimId, 1 ether);
        assertEq(decay.getClaimWeight(claimId), 100);

        // Decay again
        vm.warp(block.timestamp + 200 days);
        assertLt(decay.getClaimWeight(claimId), 100);

        // Second refresh
        vm.prank(refresher);
        decay.refreshClaim(claimId, 1 ether);
        assertEq(decay.getClaimWeight(claimId), 100);
    }

    // ============ Stale Report Tests ============

    function test_ReportStaleClaim_Success() public {
        uint256 claimId = _submitClaim();

        // Decay below threshold
        vm.warp(block.timestamp + 300 days);
        uint256 weight = decay.getClaimWeight(claimId);
        assertLt(weight, 50);

        uint256 reporterBefore = mockToken.balanceOf(reporter);

        vm.prank(reporter);
        decay.reportStaleClaim(claimId);

        assertTrue(decay.flaggedStale(claimId));
        assertEq(decay.staleReporter(claimId), reporter);

        // Reporter gets reward
        assertEq(mockToken.balanceOf(reporter) - reporterBefore, 5 ether);
    }

    function test_ReportStaleClaim_NotStale() public {
        uint256 claimId = _submitClaim();

        // Fresh claim - weight is 100
        uint256 weight = decay.getClaimWeight(claimId);

        vm.expectRevert(
            abi.encodeWithSelector(EMETDecay.ClaimNotStale.selector, claimId, weight)
        );
        vm.prank(reporter);
        decay.reportStaleClaim(claimId);
    }

    function test_ReportStaleClaim_AlreadyFlagged() public {
        uint256 claimId = _submitClaim();

        vm.warp(block.timestamp + 300 days);

        vm.prank(reporter);
        decay.reportStaleClaim(claimId);

        vm.expectRevert(
            abi.encodeWithSelector(EMETDecay.AlreadyFlaggedStale.selector, claimId)
        );
        vm.prank(reporter);
        decay.reportStaleClaim(claimId);
    }

    function test_ReportStaleClaim_NoRewardIfNoFunds() public {
        // Deploy fresh decay with no funds
        EMETDecay freshDecay = new EMETDecay(address(registry));

        uint256 claimId = _submitClaim();

        vm.warp(block.timestamp + 300 days);

        uint256 reporterBefore = mockToken.balanceOf(reporter);

        vm.prank(reporter);
        freshDecay.reportStaleClaim(claimId);

        // No reward paid (insufficient funds)
        assertEq(mockToken.balanceOf(reporter), reporterBefore);
        // But claim IS flagged
        assertTrue(freshDecay.flaggedStale(claimId));
    }

    // ============ View Function Tests ============

    function test_GetDecayInfo() public {
        uint256 claimId = _submitClaim();

        (uint256 weight, bool isStale, uint256 totalRefreshStake, uint256 numRefreshes) =
            decay.getDecayInfo(claimId);

        assertEq(weight, 100);
        assertFalse(isStale);
        assertEq(totalRefreshStake, 0);
        assertEq(numRefreshes, 0);
    }

    function test_GetDecayInfo_AfterRefresh() public {
        uint256 claimId = _submitClaim();

        vm.prank(refresher);
        decay.refreshClaim(claimId, 5 ether);

        (,, uint256 totalRefreshStake, uint256 numRefreshes) = decay.getDecayInfo(claimId);

        assertEq(totalRefreshStake, 5 ether);
        assertEq(numRefreshes, 1);
    }

    function test_GetBaseTime_InitialClaim() public {
        uint256 claimId = _submitClaim();

        uint256 baseTime = decay.getBaseTime(claimId);
        assertEq(baseTime, block.timestamp);
    }

    function test_GetBaseTime_AfterRefresh() public {
        uint256 claimId = _submitClaim();

        vm.warp(block.timestamp + 100 days);
        uint256 refreshTime = block.timestamp;

        vm.prank(refresher);
        decay.refreshClaim(claimId, 1 ether);

        uint256 baseTime = decay.getBaseTime(claimId);
        assertEq(baseTime, refreshTime);
    }

    // ============ Edge Cases ============

    function test_RefreshClaim_OnlyActiveOrVerified() public {
        uint256 claimId = _submitClaim();

        // Set a challenge contract to mark claim as challenged
        address challengeContract = address(99);
        registry.setChallengeContract(challengeContract);

        // Mark as challenged
        vm.prank(challengeContract);
        registry.markChallenged(claimId);

        // Cannot refresh challenged claim
        vm.expectRevert(
            abi.encodeWithSelector(EMETDecay.ClaimNotActive.selector, claimId)
        );
        vm.prank(refresher);
        decay.refreshClaim(claimId, 1 ether);
    }

    function test_Weight_MonotonicallyDecreasing() public {
        uint256 claimId = _submitClaim();

        uint256 prevWeight = 100;
        // Check at 10-day intervals
        for (uint256 i = 0; i < 40; i++) {
            vm.warp(block.timestamp + 10 days);
            uint256 weight = decay.getClaimWeight(claimId);
            assertLe(weight, prevWeight);
            prevWeight = weight;
        }
        // Final weight should be 10
        assertEq(prevWeight, 10);
    }

    // ============ Helpers ============

    function _submitClaim() internal returns (uint256 claimId) {
        vm.prank(submitter);
        return registry.submitClaim("Test claim text", "ipfs://evidence", MINIMUM_STAKE);
    }
}

// ============ Mock Token ============

contract MockEMETDC {
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
