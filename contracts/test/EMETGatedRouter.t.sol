// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "forge-std/Test.sol";
import "../src/EMETGatedRouter.sol";
import "../src/EMETTrustGate.sol";
import "../src/EMETAgentProfile.sol";
import "../src/EMETReputation.sol";

// ============ Concrete router for testing (adds owner-gated management) ============

contract TestRouter is EMETGatedRouter {
    address public owner;

    constructor(address trustGate, EMETTrustGate.Policy policy)
        EMETGatedRouter(trustGate, policy)
    {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    // Management functions with owner guard (call internal helpers from base)
    function setDefaultPolicy(EMETTrustGate.Policy policy) external onlyOwner {
        _setDefaultPolicy(policy);
    }

    function addBypass(address agent, string calldata reason) external onlyOwner {
        _addBypass(agent, reason);
    }

    function removeBypass(address agent) external onlyOwner {
        _removeBypass(agent);
    }

    // ---- Routing functions that use the modifiers ----

    /// Dispatches to a single trusted agent
    function dispatch(address agent) external onlyTrusted(agent) returns (bool) {
        return true;
    }

    /// Dispatches to all agents after checking each one
    function dispatchAll(address[] calldata agents) external allTrusted(agents) returns (bool) {
        return true;
    }

    /// Dispatches with an explicit policy override
    function dispatchLenient(address agent) external onlyTrustedWith(agent, EMETTrustGate.Policy.LENIENT) returns (bool) {
        return true;
    }

    /// Query trust without gating
    function queryAgent(address agent)
        external
        view
        returns (bool passes, string memory reason)
    {
        return this.queryTrust(agent, defaultPolicy);
    }
}

/// @title EMETGatedRouterTest — Tests for the EMETGatedRouter abstract base contract
contract EMETGatedRouterTest is Test {

    EMETAgentProfile internal profile;
    EMETReputation   internal reputation;
    EMETTrustGate    internal gate;
    TestRouter       internal router;

    address internal deployer   = address(this);
    address internal updater    = address(0xAB01);
    address internal routerOwner = address(0xBEEF);

    // Test agents
    address internal agentTrusted   = address(0x1111); // 10 correct claims → passes STANDARD
    address internal agentUntrusted = address(0x2222); // 0 claims → fails STANDARD
    address internal agentLenient   = address(0x3333); // 1 claim → passes LENIENT only
    address internal agentStrict    = address(0x4444); // 12 correct, high rep → passes STRICT

    // ============ Setup ============

    function setUp() public {
        profile    = new EMETAgentProfile();
        reputation = new EMETReputation();
        gate       = new EMETTrustGate(address(profile), address(reputation));

        // Wire updaters
        profile.setUpdater(updater);
        reputation.setUpdater(updater);

        // Seed agents
        _seedTrusted();
        _seedLenient();
        _seedStrict();
        // agentUntrusted stays empty

        // Deploy router with STANDARD policy, owned by routerOwner
        vm.prank(routerOwner);
        router = new TestRouter(address(gate), EMETTrustGate.Policy.STANDARD);
    }

    // ============ Seed Helpers ============

    /// agentTrusted: 10 correct → accuracy 100%, rep +10 → passes STANDARD
    function _seedTrusted() internal {
        vm.startPrank(updater);
        for (uint256 i = 0; i < 10; i++) {
            profile.recordCorrectClaim(agentTrusted, 0.01 ether);
            reputation.recordClaimVerified(agentTrusted);
        }
        vm.stopPrank();
    }

    /// agentLenient: 1 correct → accuracy 100%, rep +1, 1 claim → passes LENIENT, fails STANDARD (needs 3)
    function _seedLenient() internal {
        vm.startPrank(updater);
        profile.recordCorrectClaim(agentLenient, 0.01 ether);
        reputation.recordClaimVerified(agentLenient);
        vm.stopPrank();
    }

    /// agentStrict: 12 correct → accuracy 100%, rep +12 → passes STRICT (needs 80%, rep≥50, 10+ claims)
    function _seedStrict() internal {
        vm.startPrank(updater);
        for (uint256 i = 0; i < 12; i++) {
            profile.recordCorrectClaim(agentStrict, 0.01 ether);
            reputation.recordClaimVerified(agentStrict);
        }
        // Boost reputation to pass STRICT threshold (≥50)
        for (uint256 i = 0; i < 38; i++) {
            reputation.recordClaimVerified(agentStrict);
        }
        vm.stopPrank();
    }

    // ============ Constructor ============

    function test_constructor_storesTrustGate() public view {
        assertEq(address(router.trustGate()), address(gate));
    }

    function test_constructor_storesDefaultPolicy() public view {
        assertTrue(router.defaultPolicy() == EMETTrustGate.Policy.STANDARD);
    }

    function test_constructor_revertsOnZeroGate() public {
        vm.prank(routerOwner);
        vm.expectRevert(EMETGatedRouter.ZeroTrustGateAddress.selector);
        new TestRouter(address(0), EMETTrustGate.Policy.STANDARD);
    }

    // ============ onlyTrusted modifier ============

    function test_onlyTrusted_passesForTrustedAgent() public {
        bool result = router.dispatch(agentTrusted);
        assertTrue(result);
    }

    function test_onlyTrusted_revertsForUntrustedAgent() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                EMETGatedRouter.TrustCheckFailed.selector,
                agentUntrusted,
                "NO_HISTORY: agent has no resolved claims"
            )
        );
        router.dispatch(agentUntrusted);
    }

    function test_onlyTrusted_revertsForInsufficientClaims() public {
        // agentLenient has only 1 claim; STANDARD needs 3
        vm.expectRevert(
            abi.encodeWithSelector(
                EMETGatedRouter.TrustCheckFailed.selector,
                agentLenient,
                "INSUFFICIENT_CLAIMS: below minimum resolved claim count"
            )
        );
        router.dispatch(agentLenient);
    }

    // ============ allTrusted modifier ============

    function test_allTrusted_passesForAllTrustedAgents() public {
        address[] memory agents = new address[](2);
        agents[0] = agentTrusted;
        agents[1] = agentStrict;
        bool result = router.dispatchAll(agents);
        assertTrue(result);
    }

    function test_allTrusted_revertsIfAnyFails() public {
        address[] memory agents = new address[](2);
        agents[0] = agentTrusted;
        agents[1] = agentUntrusted; // this one fails
        vm.expectRevert(); // TrustCheckFailed
        router.dispatchAll(agents);
    }

    function test_allTrusted_revertsOnEmptyArray() public {
        address[] memory agents = new address[](0);
        vm.expectRevert(EMETGatedRouter.EmptyAgentArray.selector);
        router.dispatchAll(agents);
    }

    // ============ onlyTrustedWith modifier ============

    function test_onlyTrustedWith_lenientPassesColdStartAgent() public {
        // agentLenient: 1 claim — fails STANDARD, passes LENIENT
        bool result = router.dispatchLenient(agentLenient);
        assertTrue(result);
    }

    function test_onlyTrustedWith_lenientPassesTrustedAgent() public {
        bool result = router.dispatchLenient(agentTrusted);
        assertTrue(result);
    }

    function test_onlyTrustedWith_lenientStillFailsZeroHistory() public {
        vm.expectRevert();
        router.dispatchLenient(agentUntrusted);
    }

    // ============ setDefaultPolicy ============

    function test_setDefaultPolicy_updatesPolicy() public {
        vm.prank(routerOwner);
        router.setDefaultPolicy(EMETTrustGate.Policy.LENIENT);
        assertTrue(router.defaultPolicy() == EMETTrustGate.Policy.LENIENT);
    }

    function test_setDefaultPolicy_emitsEvent() public {
        vm.prank(routerOwner);
        vm.expectEmit(false, false, false, true);
        emit EMETGatedRouter.DefaultPolicyUpdated(
            EMETTrustGate.Policy.STANDARD,
            EMETTrustGate.Policy.LENIENT
        );
        router.setDefaultPolicy(EMETTrustGate.Policy.LENIENT);
    }

    function test_setDefaultPolicy_revertsForNonOwner() public {
        vm.expectRevert("not owner");
        router.setDefaultPolicy(EMETTrustGate.Policy.LENIENT);
    }

    function test_setDefaultPolicy_strictPassesHighRepAgent() public {
        // agentStrict: 12 claims, rep=50+ — passes STRICT
        vm.prank(routerOwner);
        router.setDefaultPolicy(EMETTrustGate.Policy.STRICT);
        bool result = router.dispatch(agentStrict);
        assertTrue(result);
    }

    function test_setDefaultPolicy_strictBlocksLowClaimAgent() public {
        // agentLenient: 1 claim — fails STRICT (needs 10+)
        vm.prank(routerOwner);
        router.setDefaultPolicy(EMETTrustGate.Policy.STRICT);
        vm.expectRevert();
        router.dispatch(agentLenient);
    }

    // ============ Bypass Management ============

    function test_addBypass_exemptsColdStartAgent() public {
        // agentUntrusted would normally fail
        vm.prank(routerOwner);
        router.addBypass(agentUntrusted, "bootstrap partner - no EMET history yet");

        // Now it passes
        bool result = router.dispatch(agentUntrusted);
        assertTrue(result);
    }

    function test_addBypass_emitsEvent() public {
        vm.prank(routerOwner);
        vm.expectEmit(true, false, false, true);
        emit EMETGatedRouter.BypassGranted(agentUntrusted, "test", routerOwner);
        router.addBypass(agentUntrusted, "test");
    }

    function test_addBypass_incrementsBypassCount() public {
        assertEq(router.bypassCount(), 0);
        vm.prank(routerOwner);
        router.addBypass(agentUntrusted, "test");
        assertEq(router.bypassCount(), 1);
    }

    function test_addBypass_revertsIfAlreadyBypassed() public {
        vm.startPrank(routerOwner);
        router.addBypass(agentUntrusted, "first");
        vm.expectRevert(abi.encodeWithSelector(EMETGatedRouter.AgentAlreadyBypassed.selector, agentUntrusted));
        router.addBypass(agentUntrusted, "duplicate");
        vm.stopPrank();
    }

    function test_addBypass_revertsForNonOwner() public {
        vm.expectRevert("not owner");
        router.addBypass(agentUntrusted, "unauthorized");
    }

    function test_removeBypass_reEnforcesGate() public {
        vm.startPrank(routerOwner);
        router.addBypass(agentUntrusted, "temp");
        router.removeBypass(agentUntrusted);
        vm.stopPrank();

        // Should fail again after bypass removed
        vm.expectRevert();
        router.dispatch(agentUntrusted);
    }

    function test_removeBypass_emitsEvent() public {
        vm.startPrank(routerOwner);
        router.addBypass(agentUntrusted, "test");
        vm.expectEmit(true, false, false, true);
        emit EMETGatedRouter.BypassRevoked(agentUntrusted, routerOwner);
        router.removeBypass(agentUntrusted);
        vm.stopPrank();
    }

    function test_removeBypass_decrementsBypassCount() public {
        vm.startPrank(routerOwner);
        router.addBypass(agentUntrusted, "test");
        assertEq(router.bypassCount(), 1);
        router.removeBypass(agentUntrusted);
        assertEq(router.bypassCount(), 0);
        vm.stopPrank();
    }

    function test_removeBypass_revertsIfNotBypassed() public {
        vm.prank(routerOwner);
        vm.expectRevert(abi.encodeWithSelector(EMETGatedRouter.AgentNotBypassed.selector, agentUntrusted));
        router.removeBypass(agentUntrusted);
    }

    function test_isBypassed_returnsCorrectly() public {
        assertFalse(router.isBypassed(agentUntrusted));
        vm.prank(routerOwner);
        router.addBypass(agentUntrusted, "test");
        assertTrue(router.isBypassed(agentUntrusted));
        vm.prank(routerOwner);
        router.removeBypass(agentUntrusted);
        assertFalse(router.isBypassed(agentUntrusted));
    }

    // ============ BypassUsed event ============

    function test_bypassUsed_emittedWhenBypassed() public {
        vm.prank(routerOwner);
        router.addBypass(agentUntrusted, "test");
        vm.expectEmit(true, true, false, false);
        emit EMETGatedRouter.BypassUsed(agentUntrusted, address(this));
        router.dispatch(agentUntrusted);
    }

    // ============ View Helpers ============

    function test_queryTrust_returnsCorrectResult() public view {
        (bool passes,) = router.queryTrust(agentTrusted, EMETTrustGate.Policy.STANDARD);
        assertTrue(passes);
        (bool fails,) = router.queryTrust(agentUntrusted, EMETTrustGate.Policy.STANDARD);
        assertFalse(fails);
    }

    function test_evaluateTrust_returnsFullResult() public view {
        EMETTrustGate.TrustResult memory result =
            router.evaluateTrust(agentTrusted, EMETTrustGate.Policy.STANDARD);
        assertTrue(result.passes);
        assertGt(result.accuracyBps, 0);
        assertGt(result.totalClaims, 0);
    }
}
