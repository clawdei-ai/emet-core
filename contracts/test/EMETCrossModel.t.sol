// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, console} from "forge-std/Test.sol";
import {EMETCrossModel} from "../src/EMETCrossModel.sol";
import {IEMET} from "../src/interfaces/IEMET.sol";

/// @title EMETCrossModel Tests - Cross-model consensus functionality
contract EMETCrossModelTest is Test {
    EMETCrossModel public crossModel;
    MockEMET public mockToken;

    address public deployer = address(1);
    address public governance = address(2);

    // Model operators
    address public claudeOperator = address(10);
    address public grokOperator = address(11);
    address public gptOperator = address(12);
    address public llamaOperator = address(13);
    address public geminiOperator = address(14);

    uint256 public constant INITIAL_BALANCE = 10000 ether;
    uint256 public constant MIN_STAKE = 100 ether;

    function setUp() public {
        // Deploy mock token at the EMET address
        address emetAddress = 0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C;
        vm.etch(emetAddress, type(MockEMET).runtimeCode);
        mockToken = MockEMET(emetAddress);

        vm.startPrank(deployer);
        crossModel = new EMETCrossModel();
        crossModel.setGovernance(governance);
        vm.stopPrank();

        // Fund operators
        _fundOperator(claudeOperator);
        _fundOperator(grokOperator);
        _fundOperator(gptOperator);
        _fundOperator(llamaOperator);
        _fundOperator(geminiOperator);
    }

    function _fundOperator(address operator) internal {
        mockToken.mint(operator, INITIAL_BALANCE);
        vm.prank(operator);
        mockToken.approve(address(crossModel), type(uint256).max);
    }

    // ============ Setup Tests ============

    function test_Constructor_SetsDeployer() public view {
        assertEq(crossModel.deployer(), deployer);
    }

    function test_SetGovernance_Success() public view {
        assertEq(crossModel.governance(), governance);
    }

    function test_SetGovernance_RevertIfNotDeployer() public {
        EMETCrossModel newCrossModel = new EMETCrossModel();
        vm.prank(claudeOperator);
        vm.expectRevert(EMETCrossModel.OnlyDeployer.selector);
        newCrossModel.setGovernance(governance);
    }

    function test_SetGovernance_RevertIfAlreadySet() public {
        vm.prank(deployer);
        vm.expectRevert(EMETCrossModel.GovernanceAlreadySet.selector);
        crossModel.setGovernance(address(5));
    }

    // ============ Model Registration Tests ============

    function test_RegisterModel_Success() public {
        vm.prank(claudeOperator);
        uint256 modelId = crossModel.registerModel("Claude", "anthropic", MIN_STAKE);

        assertEq(modelId, 1);
        assertEq(crossModel.modelCount(), 1);

        EMETCrossModel.Model memory model = crossModel.getModel(1);
        assertEq(model.name, "Claude");
        assertEq(model.architecture, "anthropic");
        assertEq(model.operator, claudeOperator);
        assertEq(model.reputation, 100); // INITIAL_REPUTATION
        assertEq(model.stake, MIN_STAKE);
        assertTrue(model.active);
    }

    function test_RegisterModel_TransfersStake() public {
        uint256 balanceBefore = mockToken.balanceOf(claudeOperator);

        vm.prank(claudeOperator);
        crossModel.registerModel("Claude", "anthropic", MIN_STAKE);

        assertEq(mockToken.balanceOf(claudeOperator), balanceBefore - MIN_STAKE);
        assertEq(mockToken.balanceOf(address(crossModel)), MIN_STAKE);
    }

    function test_RegisterModel_RevertIfInsufficientStake() public {
        vm.prank(claudeOperator);
        vm.expectRevert(abi.encodeWithSelector(
            EMETCrossModel.InsufficientStake.selector, 50 ether, MIN_STAKE
        ));
        crossModel.registerModel("Claude", "anthropic", 50 ether);
    }

    function test_RegisterModel_RevertIfOperatorAlreadyRegistered() public {
        vm.prank(claudeOperator);
        crossModel.registerModel("Claude", "anthropic", MIN_STAKE);

        vm.prank(claudeOperator);
        vm.expectRevert(abi.encodeWithSelector(
            EMETCrossModel.OperatorAlreadyRegistered.selector, claudeOperator
        ));
        crossModel.registerModel("Claude 2", "anthropic", MIN_STAKE);
    }

    function test_RegisterModel_RevertIfEmptyName() public {
        vm.prank(claudeOperator);
        vm.expectRevert(EMETCrossModel.EmptyName.selector);
        crossModel.registerModel("", "anthropic", MIN_STAKE);
    }

    function test_RegisterModel_RevertIfEmptyArchitecture() public {
        vm.prank(claudeOperator);
        vm.expectRevert(EMETCrossModel.EmptyArchitecture.selector);
        crossModel.registerModel("Claude", "", MIN_STAKE);
    }

    function test_RegisterModel_EmitsEvent() public {
        vm.prank(claudeOperator);
        vm.expectEmit(true, true, false, true);
        emit EMETCrossModel.ModelRegistered(1, "Claude", "anthropic", claudeOperator, MIN_STAKE);
        crossModel.registerModel("Claude", "anthropic", MIN_STAKE);
    }

    // ============ Model Deactivation Tests ============

    function test_DeactivateModel_Success() public {
        vm.prank(claudeOperator);
        crossModel.registerModel("Claude", "anthropic", MIN_STAKE);

        uint256 balanceBefore = mockToken.balanceOf(claudeOperator);

        vm.prank(claudeOperator);
        crossModel.deactivateModel();

        EMETCrossModel.Model memory model = crossModel.getModel(1);
        assertFalse(model.active);
        assertEq(model.stake, 0);
        assertEq(mockToken.balanceOf(claudeOperator), balanceBefore + MIN_STAKE);
    }

    function test_DeactivateModel_RevertIfNotRegistered() public {
        vm.prank(claudeOperator);
        vm.expectRevert(abi.encodeWithSelector(EMETCrossModel.ModelDoesNotExist.selector, 0));
        crossModel.deactivateModel();
    }

    function test_DeactivateModel_RevertIfAlreadyDeactivated() public {
        vm.prank(claudeOperator);
        crossModel.registerModel("Claude", "anthropic", MIN_STAKE);

        vm.prank(claudeOperator);
        crossModel.deactivateModel();

        vm.prank(claudeOperator);
        vm.expectRevert(abi.encodeWithSelector(EMETCrossModel.ModelNotActive.selector, 1));
        crossModel.deactivateModel();
    }

    // ============ Attestation Tests ============

    function test_Attest_Success() public {
        vm.prank(claudeOperator);
        crossModel.registerModel("Claude", "anthropic", MIN_STAKE);

        vm.prank(claudeOperator);
        crossModel.attest(100, true, 85, "Evidence strongly supports claim");

        EMETCrossModel.Attestation memory a = crossModel.getAttestation(100, 1);
        assertEq(a.claimId, 100);
        assertEq(a.modelId, 1);
        assertTrue(a.supportsClaim);
        assertEq(a.confidence, 85);
        assertEq(a.reasoning, "Evidence strongly supports claim");
        assertTrue(a.timestamp > 0);
    }

    function test_Attest_RevertIfNotRegistered() public {
        vm.prank(claudeOperator);
        vm.expectRevert(abi.encodeWithSelector(EMETCrossModel.ModelDoesNotExist.selector, 0));
        crossModel.attest(100, true, 85, "Reasoning");
    }

    function test_Attest_RevertIfModelNotActive() public {
        vm.prank(claudeOperator);
        crossModel.registerModel("Claude", "anthropic", MIN_STAKE);

        vm.prank(claudeOperator);
        crossModel.deactivateModel();

        vm.prank(claudeOperator);
        vm.expectRevert(abi.encodeWithSelector(EMETCrossModel.ModelNotActive.selector, 1));
        crossModel.attest(100, true, 85, "Reasoning");
    }

    function test_Attest_RevertIfInvalidConfidence() public {
        vm.prank(claudeOperator);
        crossModel.registerModel("Claude", "anthropic", MIN_STAKE);

        vm.prank(claudeOperator);
        vm.expectRevert(abi.encodeWithSelector(EMETCrossModel.InvalidConfidence.selector, 101));
        crossModel.attest(100, true, 101, "Reasoning");
    }

    function test_Attest_RevertIfDoubleAttestation() public {
        vm.prank(claudeOperator);
        crossModel.registerModel("Claude", "anthropic", MIN_STAKE);

        vm.prank(claudeOperator);
        crossModel.attest(100, true, 85, "First attestation");

        vm.prank(claudeOperator);
        vm.expectRevert(abi.encodeWithSelector(EMETCrossModel.AlreadyAttested.selector, 100, 1));
        crossModel.attest(100, false, 90, "Second attestation");
    }

    function test_Attest_EmitsEvent() public {
        vm.prank(claudeOperator);
        crossModel.registerModel("Claude", "anthropic", MIN_STAKE);

        vm.prank(claudeOperator);
        vm.expectEmit(true, true, false, true);
        emit EMETCrossModel.AttestationSubmitted(100, 1, true, 85, "Reasoning");
        crossModel.attest(100, true, 85, "Reasoning");
    }

    function test_Attest_IncrementsModelAttestations() public {
        vm.prank(claudeOperator);
        crossModel.registerModel("Claude", "anthropic", MIN_STAKE);

        vm.prank(claudeOperator);
        crossModel.attest(100, true, 85, "First");
        vm.prank(claudeOperator);
        crossModel.attest(200, false, 70, "Second");

        EMETCrossModel.Model memory model = crossModel.getModel(1);
        assertEq(model.totalAttestations, 2);
    }

    // ============ Consensus Tests ============

    function _registerAllModels() internal {
        vm.prank(claudeOperator);
        crossModel.registerModel("Claude", "anthropic", MIN_STAKE);
        vm.prank(grokOperator);
        crossModel.registerModel("Grok", "xai", MIN_STAKE);
        vm.prank(gptOperator);
        crossModel.registerModel("GPT-4", "openai", MIN_STAKE);
        vm.prank(llamaOperator);
        crossModel.registerModel("Llama", "meta", MIN_STAKE);
        vm.prank(geminiOperator);
        crossModel.registerModel("Gemini", "google", MIN_STAKE);
    }

    function test_GetConsensus_NoAttestations() public view {
        EMETCrossModel.Consensus memory c = crossModel.getConsensus(100);
        assertEq(c.supportingModels, 0);
        assertEq(c.disputingModels, 0);
        assertFalse(c.consensusReached);
    }

    function test_GetConsensus_UnanimousSupport() public {
        _registerAllModels();

        vm.prank(claudeOperator);
        crossModel.attest(100, true, 90, "Valid");
        vm.prank(grokOperator);
        crossModel.attest(100, true, 85, "Confirmed");
        vm.prank(gptOperator);
        crossModel.attest(100, true, 80, "Verified");

        EMETCrossModel.Consensus memory c = crossModel.getConsensus(100);
        assertEq(c.supportingModels, 3);
        assertEq(c.disputingModels, 0);
        assertEq(c.avgConfidenceFor, 85); // (90+85+80)/3
        assertTrue(c.consensusReached);
        assertTrue(c.consensusSupports);
    }

    function test_GetConsensus_UnanimousDispute() public {
        _registerAllModels();

        vm.prank(claudeOperator);
        crossModel.attest(100, false, 95, "Fake");
        vm.prank(grokOperator);
        crossModel.attest(100, false, 90, "False");
        vm.prank(gptOperator);
        crossModel.attest(100, false, 85, "Incorrect");

        EMETCrossModel.Consensus memory c = crossModel.getConsensus(100);
        assertEq(c.supportingModels, 0);
        assertEq(c.disputingModels, 3);
        assertEq(c.avgConfidenceAgainst, 90); // (95+90+85)/3
        assertTrue(c.consensusReached);
        assertFalse(c.consensusSupports);
    }

    function test_GetConsensus_NoConsensusIfTooFewModels() public {
        _registerAllModels();

        vm.prank(claudeOperator);
        crossModel.attest(100, true, 90, "Valid");
        vm.prank(grokOperator);
        crossModel.attest(100, true, 85, "Confirmed");

        EMETCrossModel.Consensus memory c = crossModel.getConsensus(100);
        assertEq(c.supportingModels, 2);
        assertFalse(c.consensusReached);
    }

    function test_GetConsensus_NoConsensusIfLowConfidence() public {
        _registerAllModels();

        vm.prank(claudeOperator);
        crossModel.attest(100, true, 60, "Maybe");
        vm.prank(grokOperator);
        crossModel.attest(100, true, 50, "Uncertain");
        vm.prank(gptOperator);
        crossModel.attest(100, true, 55, "Possibly");

        EMETCrossModel.Consensus memory c = crossModel.getConsensus(100);
        assertEq(c.supportingModels, 3);
        assertEq(c.avgConfidenceFor, 55); // Below 70% threshold
        assertFalse(c.consensusReached);
    }

    function test_GetConsensus_MixedOpinions() public {
        _registerAllModels();

        vm.prank(claudeOperator);
        crossModel.attest(100, true, 90, "Valid");
        vm.prank(grokOperator);
        crossModel.attest(100, true, 85, "Valid");
        vm.prank(gptOperator);
        crossModel.attest(100, false, 80, "Invalid");
        vm.prank(llamaOperator);
        crossModel.attest(100, true, 75, "Valid");

        EMETCrossModel.Consensus memory c = crossModel.getConsensus(100);
        assertEq(c.supportingModels, 3);
        assertEq(c.disputingModels, 1);
        assertEq(c.avgConfidenceFor, 83); // (90+85+75)/3
        assertEq(c.avgConfidenceAgainst, 80);
        assertTrue(c.consensusReached);
        assertTrue(c.consensusSupports);
    }

    // ============ Reputation Tests ============

    function test_UpdateModelReputation_Success() public {
        vm.prank(claudeOperator);
        crossModel.registerModel("Claude", "anthropic", MIN_STAKE);

        vm.prank(governance);
        crossModel.updateModelReputation(1, 10);

        EMETCrossModel.Model memory model = crossModel.getModel(1);
        assertEq(model.reputation, 110);
    }

    function test_UpdateModelReputation_NegativeDelta() public {
        vm.prank(claudeOperator);
        crossModel.registerModel("Claude", "anthropic", MIN_STAKE);

        vm.prank(governance);
        crossModel.updateModelReputation(1, -30);

        EMETCrossModel.Model memory model = crossModel.getModel(1);
        assertEq(model.reputation, 70);
    }

    function test_UpdateModelReputation_FloorAtZero() public {
        vm.prank(claudeOperator);
        crossModel.registerModel("Claude", "anthropic", MIN_STAKE);

        vm.prank(governance);
        crossModel.updateModelReputation(1, -150);

        EMETCrossModel.Model memory model = crossModel.getModel(1);
        assertEq(model.reputation, 0);
    }

    function test_UpdateModelReputation_RevertIfNotGovernance() public {
        vm.prank(claudeOperator);
        crossModel.registerModel("Claude", "anthropic", MIN_STAKE);

        vm.prank(claudeOperator);
        vm.expectRevert(EMETCrossModel.OnlyGovernance.selector);
        crossModel.updateModelReputation(1, 10);
    }

    function test_UpdateModelReputation_EmitsEvent() public {
        vm.prank(claudeOperator);
        crossModel.registerModel("Claude", "anthropic", MIN_STAKE);

        vm.prank(governance);
        vm.expectEmit(true, false, false, true);
        emit EMETCrossModel.ReputationUpdated(1, 100, 90, -10);
        crossModel.updateModelReputation(1, -10);
    }

    // ============ Query Tests ============

    function test_GetAttestations_ReturnsAll() public {
        _registerAllModels();

        vm.prank(claudeOperator);
        crossModel.attest(100, true, 90, "Valid");
        vm.prank(grokOperator);
        crossModel.attest(100, false, 80, "Invalid");
        vm.prank(gptOperator);
        crossModel.attest(100, true, 85, "Valid");

        EMETCrossModel.Attestation[] memory attestations = crossModel.getAttestations(100);
        assertEq(attestations.length, 3);
        assertEq(attestations[0].modelId, 1);
        assertEq(attestations[1].modelId, 2);
        assertEq(attestations[2].modelId, 3);
    }

    function test_HasModelAttested() public {
        vm.prank(claudeOperator);
        crossModel.registerModel("Claude", "anthropic", MIN_STAKE);

        assertFalse(crossModel.hasModelAttested(100, 1));

        vm.prank(claudeOperator);
        crossModel.attest(100, true, 90, "Valid");

        assertTrue(crossModel.hasModelAttested(100, 1));
    }

    function test_GetModelByOperator() public {
        vm.prank(claudeOperator);
        crossModel.registerModel("Claude", "anthropic", MIN_STAKE);

        assertEq(crossModel.getModelByOperator(claudeOperator), 1);
        assertEq(crossModel.getModelByOperator(grokOperator), 0);
    }

    function test_GetActiveModels() public {
        _registerAllModels();

        uint256[] memory active = crossModel.getActiveModels();
        assertEq(active.length, 5);

        // Deactivate one
        vm.prank(claudeOperator);
        crossModel.deactivateModel();

        active = crossModel.getActiveModels();
        assertEq(active.length, 4);
    }

    function test_GetAttestationCount() public {
        _registerAllModels();

        assertEq(crossModel.getAttestationCount(100), 0);

        vm.prank(claudeOperator);
        crossModel.attest(100, true, 90, "Valid");
        vm.prank(grokOperator);
        crossModel.attest(100, false, 80, "Invalid");

        assertEq(crossModel.getAttestationCount(100), 2);
    }

    // ============ Architecture Diversity Tests ============

    function test_GetArchitectureDiversity() public {
        _registerAllModels();

        vm.prank(claudeOperator);
        crossModel.attest(100, true, 90, "Valid");
        vm.prank(grokOperator);
        crossModel.attest(100, true, 85, "Valid");
        vm.prank(gptOperator);
        crossModel.attest(100, false, 80, "Invalid");
        vm.prank(llamaOperator);
        crossModel.attest(100, true, 75, "Valid");

        (uint256 forArch, uint256 againstArch) = crossModel.getArchitectureDiversity(100);

        // 3 different architectures supporting (anthropic, xai, meta)
        assertEq(forArch, 3);
        // 1 architecture against (openai)
        assertEq(againstArch, 1);
    }

    function test_GetArchitectureDiversity_SameArchitecture() public {
        // Register multiple models with same architecture
        mockToken.mint(address(20), INITIAL_BALANCE);
        vm.prank(address(20));
        mockToken.approve(address(crossModel), type(uint256).max);

        vm.prank(claudeOperator);
        crossModel.registerModel("Claude-3", "anthropic", MIN_STAKE);
        vm.prank(address(20));
        crossModel.registerModel("Claude-2", "anthropic", MIN_STAKE);

        vm.prank(claudeOperator);
        crossModel.attest(100, true, 90, "Valid");
        vm.prank(address(20));
        crossModel.attest(100, true, 85, "Valid");

        (uint256 forArch,) = crossModel.getArchitectureDiversity(100);
        // Both are "anthropic", so only 1 unique architecture
        assertEq(forArch, 1);
    }

    // ============ Edge Cases ============

    function test_MultipleClaimsSameModel() public {
        vm.prank(claudeOperator);
        crossModel.registerModel("Claude", "anthropic", MIN_STAKE);

        vm.prank(claudeOperator);
        crossModel.attest(100, true, 90, "Claim 100 valid");
        vm.prank(claudeOperator);
        crossModel.attest(200, false, 80, "Claim 200 invalid");
        vm.prank(claudeOperator);
        crossModel.attest(300, true, 95, "Claim 300 valid");

        EMETCrossModel.Model memory model = crossModel.getModel(1);
        assertEq(model.totalAttestations, 3);

        assertTrue(crossModel.hasModelAttested(100, 1));
        assertTrue(crossModel.hasModelAttested(200, 1));
        assertTrue(crossModel.hasModelAttested(300, 1));
    }

    function test_ZeroConfidenceAllowed() public {
        vm.prank(claudeOperator);
        crossModel.registerModel("Claude", "anthropic", MIN_STAKE);

        vm.prank(claudeOperator);
        crossModel.attest(100, true, 0, "No confidence but still attesting");

        EMETCrossModel.Attestation memory a = crossModel.getAttestation(100, 1);
        assertEq(a.confidence, 0);
    }

    function test_BoundaryConfidence() public {
        vm.prank(claudeOperator);
        crossModel.registerModel("Claude", "anthropic", MIN_STAKE);

        vm.prank(claudeOperator);
        crossModel.attest(100, true, 100, "Maximum confidence");

        EMETCrossModel.Attestation memory a = crossModel.getAttestation(100, 1);
        assertEq(a.confidence, 100);
    }
}

// ============ Mock Token ============

contract MockEMET {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
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

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}
