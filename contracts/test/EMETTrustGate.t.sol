// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "forge-std/Test.sol";
import "../src/EMETTrustGate.sol";
import "../src/EMETAgentProfile.sol";
import "../src/EMETReputation.sol";

/// @title EMETTrustGateTest — Comprehensive tests for EMETTrustGate composable trust gate
/// @notice Tests all policies (LENIENT/STANDARD/STRICT/CUSTOM), batch ops, filtering,
///         events, edge cases, and external builder integration patterns.
contract EMETTrustGateTest is Test {

    EMETAgentProfile internal profile;
    EMETReputation   internal reputation;
    EMETTrustGate    internal gate;

    address internal deployer = address(this);
    address internal updater  = address(0xAB01);

    // Test agents
    address internal agentAlpha   = address(0x1111); // High-trust agent
    address internal agentBeta    = address(0x2222); // Standard-trust agent
    address internal agentGamma   = address(0x3333); // Low-trust / slashed agent
    address internal agentEpsilon = address(0x4444); // Fresh agent (no history)
    address internal agentDelta   = address(0x5555); // Negative reputation agent
    address internal callerContract = address(0xCAFE); // External caller

    // ============ Setup ============

    function setUp() public {
        // Deploy contracts
        profile    = new EMETAgentProfile();
        reputation = new EMETReputation();
        gate       = new EMETTrustGate(address(profile), address(reputation));

        // Wire AgentProfile updater
        profile.setUpdater(updater);

        // Authorise updater on Reputation
        reputation.setUpdater(updater);

        // Seed agent histories
        _seedAlpha();
        _seedBeta();
        _seedGamma();
        _seedDelta();
        // agentEpsilon stays empty (no history)
    }

    // ============ Seed Helpers ============

    /// @dev Alpha: 15 correct claims, 2 slashed → 88.2% accuracy, reputation +100
    function _seedAlpha() internal {
        vm.startPrank(updater);
        for (uint256 i = 0; i < 15; i++) {
            profile.recordCorrectClaim(agentAlpha, 0.01 ether);
            reputation.recordClaimVerified(agentAlpha);
        }
        for (uint256 i = 0; i < 2; i++) {
            profile.recordSlashedClaim(agentAlpha, 0.01 ether);
            reputation.recordClaimRejected(agentAlpha);
        }
        vm.stopPrank();
    }

    /// @dev Beta: 5 correct, 2 slashed → 71.4% accuracy, reputation +30
    function _seedBeta() internal {
        vm.startPrank(updater);
        for (uint256 i = 0; i < 5; i++) {
            profile.recordCorrectClaim(agentBeta, 0.005 ether);
            reputation.recordClaimVerified(agentBeta);
        }
        for (uint256 i = 0; i < 2; i++) {
            profile.recordSlashedClaim(agentBeta, 0.005 ether);
            reputation.recordClaimRejected(agentBeta);
        }
        vm.stopPrank();
    }

    /// @dev Gamma: 2 correct, 10 slashed → 16.7% accuracy, reputation negative
    function _seedGamma() internal {
        vm.startPrank(updater);
        for (uint256 i = 0; i < 2; i++) {
            profile.recordCorrectClaim(agentGamma, 0.001 ether);
            reputation.recordClaimVerified(agentGamma);
        }
        for (uint256 i = 0; i < 10; i++) {
            profile.recordSlashedClaim(agentGamma, 0.001 ether);
            reputation.recordClaimRejected(agentGamma);
        }
        vm.stopPrank();
    }

    /// @dev Delta: decent accuracy but forced negative reputation via challenge failures
    function _seedDelta() internal {
        vm.startPrank(updater);
        for (uint256 i = 0; i < 5; i++) {
            profile.recordCorrectClaim(agentDelta, 0.002 ether);
            reputation.recordClaimVerified(agentDelta);
        }
        // Push reputation deeply negative via challenge failures
        for (uint256 i = 0; i < 10; i++) {
            reputation.recordChallengeFailed(agentDelta);
        }
        vm.stopPrank();
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsImmutables() public view {
        assertEq(address(gate.agentProfile()), address(profile));
        assertEq(address(gate.reputation()), address(reputation));
    }

    function test_Constructor_RejectsZeroAddressProfile() public {
        vm.expectRevert(EMETTrustGate.ZeroAddress.selector);
        new EMETTrustGate(address(0), address(reputation));
    }

    function test_Constructor_RejectsZeroAddressReputation() public {
        vm.expectRevert(EMETTrustGate.ZeroAddress.selector);
        new EMETTrustGate(address(profile), address(0));
    }

    // ============ LENIENT Policy ============

    function test_Lenient_FreshAgentFails() public {
        (bool passes, string memory reason) = gate.check(agentEpsilon, EMETTrustGate.Policy.LENIENT);
        assertFalse(passes);
        assertEq(reason, "NO_HISTORY: agent has no resolved claims");
    }

    function test_Lenient_AnyAgentWithOneClaimPasses() public {
        // Give epsilon exactly 1 claim
        vm.prank(updater);
        profile.recordCorrectClaim(agentEpsilon, 0.001 ether);
        vm.prank(updater);
        reputation.recordClaimVerified(agentEpsilon);

        (bool passes,) = gate.check(agentEpsilon, EMETTrustGate.Policy.LENIENT);
        assertTrue(passes);
    }

    function test_Lenient_SlashedAgentWithHistoryPasses() public {
        // Gamma has history (bad accuracy) — still passes LENIENT
        (bool passes,) = gate.check(agentGamma, EMETTrustGate.Policy.LENIENT);
        assertTrue(passes);
    }

    function test_Lenient_HighTrustAgentPasses() public {
        (bool passes,) = gate.check(agentAlpha, EMETTrustGate.Policy.LENIENT);
        assertTrue(passes);
    }

    // ============ STANDARD Policy ============

    function test_Standard_AlphaPasses() public {
        (bool passes,) = gate.check(agentAlpha, EMETTrustGate.Policy.STANDARD);
        assertTrue(passes);
    }

    function test_Standard_BetaPasses() public {
        (bool passes,) = gate.check(agentBeta, EMETTrustGate.Policy.STANDARD);
        assertTrue(passes);
    }

    function test_Standard_GammaFails_LowAccuracy() public {
        (bool passes, string memory reason) = gate.check(agentGamma, EMETTrustGate.Policy.STANDARD);
        assertFalse(passes);
        // Gamma accuracy ~16.7% < 60%
        assertEq(reason, "LOW_ACCURACY: accuracy below policy threshold");
    }

    function test_Standard_FreshAgentFails() public {
        (bool passes, string memory reason) = gate.check(agentEpsilon, EMETTrustGate.Policy.STANDARD);
        assertFalse(passes);
        assertEq(reason, "NO_HISTORY: agent has no resolved claims");
    }

    function test_Standard_DeltaFails_LowReputation() public {
        (bool passes, string memory reason) = gate.check(agentDelta, EMETTrustGate.Policy.STANDARD);
        assertFalse(passes);
        // Delta has decent accuracy (5 correct, 0 slashed from profile) but
        // reputation is deeply negative from challenge failures
        assertEq(reason, "NEGATIVE_REPUTATION: agent has been penalized");
    }

    // ============ STRICT Policy ============

    function test_Strict_AlphaPasses() public {
        (bool passes,) = gate.check(agentAlpha, EMETTrustGate.Policy.STRICT);
        assertTrue(passes);
        // Alpha: 88.2% accuracy (≥80%), reputation=+110 (≥50), 17 claims (≥10)
    }

    function test_Strict_BetaFails_InsufficientClaims() public {
        (bool passes, string memory reason) = gate.check(agentBeta, EMETTrustGate.Policy.STRICT);
        assertFalse(passes);
        // Beta only has 7 claims (< 10 required for STRICT)
        assertEq(reason, "INSUFFICIENT_CLAIMS: below minimum resolved claim count");
    }

    function test_Strict_GammaFails() public {
        (bool passes,) = gate.check(agentGamma, EMETTrustGate.Policy.STRICT);
        assertFalse(passes);
    }

    // ============ CUSTOM Policy ============

    function test_Custom_ExactThresholds() public {
        EMETTrustGate.CustomPolicy memory cp = EMETTrustGate.CustomPolicy({
            minAccuracyBps: 7_000, // 70%
            minReputation:  0,
            minClaims:      5
        });
        (bool passes,) = gate.checkCustom(agentAlpha, cp);
        assertTrue(passes);
    }

    function test_Custom_BetaPassesRelaxedThresholds() public {
        EMETTrustGate.CustomPolicy memory cp = EMETTrustGate.CustomPolicy({
            minAccuracyBps: 6_000, // 60%
            minReputation:  -100,  // allow some negative rep
            minClaims:      3
        });
        (bool passes,) = gate.checkCustom(agentBeta, cp);
        assertTrue(passes);
    }

    function test_Custom_ZeroMinClaimsReverts() public {
        EMETTrustGate.CustomPolicy memory cp = EMETTrustGate.CustomPolicy({
            minAccuracyBps: 5_000,
            minReputation:  0,
            minClaims:      0 // invalid
        });
        vm.expectRevert(EMETTrustGate.InvalidCustomPolicy.selector);
        gate.checkCustom(agentAlpha, cp);
    }

    function test_Custom_VeryHighThresholdFails() public {
        EMETTrustGate.CustomPolicy memory cp = EMETTrustGate.CustomPolicy({
            minAccuracyBps: 9_500, // 95% — nobody meets this
            minReputation:  200,
            minClaims:      50
        });
        (bool passes,) = gate.checkCustom(agentAlpha, cp);
        assertFalse(passes);
    }

    // ============ query() — view-only, no event ============

    function test_Query_ReturnsCorrectResult() public view {
        (bool passes, string memory reason) = gate.query(agentAlpha, EMETTrustGate.Policy.STANDARD);
        assertTrue(passes);
        assertEq(reason, "PASS");
    }

    function test_Query_DoesNotRevert_FreshAgent() public view {
        (bool passes,) = gate.query(agentEpsilon, EMETTrustGate.Policy.STANDARD);
        assertFalse(passes);
    }

    // ============ evaluate() — full struct ============

    function test_Evaluate_ReturnsFullStruct_Alpha() public view {
        EMETTrustGate.TrustResult memory result = gate.evaluate(agentAlpha, EMETTrustGate.Policy.STANDARD);
        assertTrue(result.passes);
        // Alpha: 15/17 correct = 8823 bps
        assertGt(result.accuracyBps, 8_800);
        assertLt(result.accuracyBps, 8_900);
        assertGt(result.reputation, int256(0));
        assertEq(result.totalClaims, 17);
        assertEq(result.reason, "PASS");
    }

    function test_Evaluate_ReturnsFullStruct_Epsilon() public view {
        EMETTrustGate.TrustResult memory result = gate.evaluate(agentEpsilon, EMETTrustGate.Policy.STANDARD);
        assertFalse(result.passes);
        assertEq(result.accuracyBps, 0);
        assertEq(result.totalClaims, 0);
    }

    function test_Evaluate_ReturnsFullStruct_Gamma() public view {
        EMETTrustGate.TrustResult memory result = gate.evaluate(agentGamma, EMETTrustGate.Policy.STANDARD);
        assertFalse(result.passes);
        // 2 correct / 12 total = ~1666 bps
        assertGt(result.accuracyBps, 1_600);
        assertLt(result.accuracyBps, 1_700);
        assertEq(result.totalClaims, 12);
    }

    // ============ evaluateBatch() ============

    function test_EvaluateBatch_MultipleAgents() public view {
        address[] memory agents = new address[](4);
        agents[0] = agentAlpha;
        agents[1] = agentBeta;
        agents[2] = agentGamma;
        agents[3] = agentEpsilon;

        EMETTrustGate.TrustResult[] memory results = gate.evaluateBatch(agents, EMETTrustGate.Policy.STANDARD);

        assertEq(results.length, 4);
        assertTrue(results[0].passes);   // Alpha: passes
        assertTrue(results[1].passes);   // Beta: passes
        assertFalse(results[2].passes);  // Gamma: fails accuracy
        assertFalse(results[3].passes);  // Epsilon: no history
    }

    function test_EvaluateBatch_EmptyArray() public view {
        address[] memory agents = new address[](0);
        EMETTrustGate.TrustResult[] memory results = gate.evaluateBatch(agents, EMETTrustGate.Policy.STANDARD);
        assertEq(results.length, 0);
    }

    function test_EvaluateBatch_StrictPolicy() public view {
        address[] memory agents = new address[](2);
        agents[0] = agentAlpha;
        agents[1] = agentBeta;

        EMETTrustGate.TrustResult[] memory results = gate.evaluateBatch(agents, EMETTrustGate.Policy.STRICT);
        assertTrue(results[0].passes);   // Alpha: 17 claims, passes STRICT
        assertFalse(results[1].passes);  // Beta: only 7 claims, fails STRICT
    }

    // ============ filter() ============

    function test_Filter_RemovesFailingAgents() public view {
        address[] memory candidates = new address[](4);
        candidates[0] = agentAlpha;
        candidates[1] = agentGamma;
        candidates[2] = agentBeta;
        candidates[3] = agentEpsilon;

        address[] memory qualified = gate.filter(candidates, EMETTrustGate.Policy.STANDARD);
        assertEq(qualified.length, 2);
        assertEq(qualified[0], agentAlpha);
        assertEq(qualified[1], agentBeta);
    }

    function test_Filter_EmptyInput() public view {
        address[] memory candidates = new address[](0);
        address[] memory qualified = gate.filter(candidates, EMETTrustGate.Policy.STANDARD);
        assertEq(qualified.length, 0);
    }

    function test_Filter_NonePass() public view {
        address[] memory candidates = new address[](2);
        candidates[0] = agentGamma;
        candidates[1] = agentEpsilon;

        address[] memory qualified = gate.filter(candidates, EMETTrustGate.Policy.STRICT);
        assertEq(qualified.length, 0);
    }

    function test_Filter_AllPass() public view {
        address[] memory candidates = new address[](2);
        candidates[0] = agentAlpha;
        candidates[1] = agentBeta;

        address[] memory qualified = gate.filter(candidates, EMETTrustGate.Policy.LENIENT);
        assertEq(qualified.length, 2);
    }

    // ============ Event Tests ============

    function test_Check_EmitsTrustChecked() public {
        vm.expectEmit(true, true, true, false);
        emit EMETTrustGate.TrustChecked(
            address(this),
            agentAlpha,
            EMETTrustGate.Policy.STANDARD,
            true,
            0,   // not checked (4th param = false)
            0    // not checked
        );
        gate.check(agentAlpha, EMETTrustGate.Policy.STANDARD);
    }

    function test_CheckCustom_EmitsCustomTrustChecked() public {
        EMETTrustGate.CustomPolicy memory cp = EMETTrustGate.CustomPolicy({
            minAccuracyBps: 7_000,
            minReputation:  0,
            minClaims:      5
        });
        vm.expectEmit(true, true, false, false);
        emit EMETTrustGate.CustomTrustChecked(
            address(this),
            agentAlpha,
            true,
            0,   // not checked
            0    // not checked
        );
        gate.checkCustom(agentAlpha, cp);
    }

    function test_Check_CallerAddressInEvent() public {
        // Simulate check from an external contract
        vm.prank(callerContract);
        // The event should record callerContract, not this test contract
        vm.expectEmit(true, false, false, false);
        emit EMETTrustGate.TrustChecked(
            callerContract,
            agentAlpha,
            EMETTrustGate.Policy.STANDARD,
            true,
            0,
            0
        );
        gate.check(agentAlpha, EMETTrustGate.Policy.STANDARD);
    }

    // ============ Policy Constants ============

    function test_PolicyConstants_Values() public view {
        assertEq(gate.LENIENT_MIN_ACCURACY_BPS(),  0);
        assertEq(gate.STANDARD_MIN_ACCURACY_BPS(), 6_000);
        assertEq(gate.STRICT_MIN_ACCURACY_BPS(),   8_000);
        assertEq(gate.STANDARD_MIN_CLAIMS(),       3);
        assertEq(gate.STRICT_MIN_CLAIMS(),         10);
        assertEq(gate.STRICT_MIN_REPUTATION(),     50);
    }

    // ============ Integration: External Builder Pattern ============

    /// @notice Simulate how an external routing contract would use EMETTrustGate
    function test_Integration_RouterPattern() public view {
        // Pattern: router fetches candidates, filters by trust, picks first
        address[] memory candidates = new address[](4);
        candidates[0] = agentEpsilon; // no history — filtered out
        candidates[1] = agentGamma;   // low accuracy — filtered out
        candidates[2] = agentBeta;    // passes STANDARD
        candidates[3] = agentAlpha;   // passes STANDARD

        address[] memory trusted = gate.filter(candidates, EMETTrustGate.Policy.STANDARD);
        assertEq(trusted.length, 2);
        // Router picks first trusted agent
        address selected = trusted[0];
        assertEq(selected, agentBeta);
    }

    /// @notice Simulate progressive trust escalation (lenient first, then strict)
    function test_Integration_EscalationPattern() public view {
        // Bootstrap: lenient (new agent accepted for small tasks)
        (bool lenientPass,) = gate.query(agentBeta, EMETTrustGate.Policy.LENIENT);
        assertTrue(lenientPass);

        // High-stakes: strict (same agent gated out for large tasks due to claim count)
        (bool strictPass,) = gate.query(agentBeta, EMETTrustGate.Policy.STRICT);
        assertFalse(strictPass);
    }

    /// @notice Simulate crew formation: require all members to pass STANDARD
    function test_Integration_CrewFormation() public view {
        address[] memory crew = new address[](3);
        crew[0] = agentAlpha;
        crew[1] = agentBeta;
        crew[2] = agentGamma; // bad actor

        address[] memory trusted = gate.filter(crew, EMETTrustGate.Policy.STANDARD);
        assertEq(trusted.length, 2); // Gamma filtered out

        // Verify no bad actors in crew
        bool allTrusted = true;
        for (uint256 i = 0; i < trusted.length; i++) {
            (bool passes,) = gate.query(trusted[i], EMETTrustGate.Policy.STANDARD);
            if (!passes) allTrusted = false;
        }
        assertTrue(allTrusted);
    }
}
