// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, console} from "forge-std/Test.sol";
import {EMETRegistry} from "../src/EMETRegistry.sol";
import {EMETBootstrap} from "../src/EMETBootstrap.sol";
import {IEMET} from "../src/interfaces/IEMET.sol";

/// @notice Mock EMET token for testing
contract MockEMET {
    string public name = "EMET Token";
    string public symbol = "EMET";
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
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract EMETEconomicsV2Test is Test {
    // Contracts
    EMETRegistry public registry;
    EMETBootstrap public bootstrap;
    MockEMET public emet;
    
    // Test accounts
    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public treasury = 0xe1230E68818CCE66275Ad95E1bC79517Ac1ae502;
    
    // Constants
    uint256 public constant MINIMUM_STAKE = 100e18;
    uint256 public constant CHALLENGE_PERIOD = 7 days;
    uint256 public constant DEFAULT_CLAIM_FEE = 10e18;
    
    function setUp() public {
        // Deploy mock EMET at expected address
        emet = new MockEMET();
        address expectedEMET = 0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C;
        vm.etch(expectedEMET, address(emet).code);
        emet = MockEMET(expectedEMET);
        
        // Deploy registry as owner
        vm.prank(owner);
        registry = new EMETRegistry(MINIMUM_STAKE, CHALLENGE_PERIOD);
        
        // Deploy bootstrap with registry
        vm.prank(owner);
        bootstrap = new EMETBootstrap(address(registry));
        
        // Fund test accounts
        emet.mint(alice, 100_000e18);
        emet.mint(bob, 100_000e18);
        emet.mint(treasury, 0); // Initialize treasury with 0 balance
        
        // Fund bootstrap with full reserve
        emet.mint(address(bootstrap), 400_000_000e18);
        
        // Approve contracts
        vm.prank(alice);
        emet.approve(address(registry), type(uint256).max);
        vm.prank(bob);
        emet.approve(address(registry), type(uint256).max);
    }

    // ============ Claim Fee Tests ============
    
    function test_ClaimFee_DefaultValue() public view {
        assertEq(registry.claimFee(), DEFAULT_CLAIM_FEE);
    }
    
    function test_ClaimFee_DeductedOnSubmission() public {
        uint256 aliceBalanceBefore = emet.balanceOf(alice);
        uint256 treasuryBalanceBefore = emet.balanceOf(treasury);
        
        vm.prank(alice);
        registry.submitClaim("Test claim", "ipfs://test", MINIMUM_STAKE);
        
        // Alice should have paid stake + fee
        assertEq(emet.balanceOf(alice), aliceBalanceBefore - MINIMUM_STAKE - DEFAULT_CLAIM_FEE);
        
        // Treasury should have received the fee
        assertEq(emet.balanceOf(treasury), treasuryBalanceBefore + DEFAULT_CLAIM_FEE);
    }
    
    function test_ClaimFee_EmitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit EMETRegistry.ClaimFeePaid(0, alice, DEFAULT_CLAIM_FEE);
        registry.submitClaim("Test claim", "ipfs://test", MINIMUM_STAKE);
    }
    
    function test_ClaimFee_OwnerCanUpdate() public {
        uint256 newFee = 20e18;
        
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit EMETRegistry.ClaimFeeUpdated(DEFAULT_CLAIM_FEE, newFee);
        registry.setClaimFee(newFee);
        
        assertEq(registry.claimFee(), newFee);
    }
    
    function test_ClaimFee_NonOwnerCannotUpdate() public {
        vm.prank(alice);
        vm.expectRevert(EMETRegistry.OnlyOwner.selector);
        registry.setClaimFee(20e18);
    }
    
    function test_ClaimFee_CanBeSetToZero() public {
        vm.prank(owner);
        registry.setClaimFee(0);
        
        uint256 treasuryBalanceBefore = emet.balanceOf(treasury);
        
        vm.prank(alice);
        registry.submitClaim("Test claim", "ipfs://test", MINIMUM_STAKE);
        
        // Treasury should not receive anything
        assertEq(emet.balanceOf(treasury), treasuryBalanceBefore);
    }
    
    function test_ClaimFee_UpdatedFeeApplies() public {
        uint256 newFee = 50e18;
        vm.prank(owner);
        registry.setClaimFee(newFee);
        
        uint256 treasuryBalanceBefore = emet.balanceOf(treasury);
        
        vm.prank(alice);
        registry.submitClaim("Test claim", "ipfs://test", MINIMUM_STAKE);
        
        assertEq(emet.balanceOf(treasury), treasuryBalanceBefore + newFee);
    }

    // ============ Verified Claims Count Tests ============
    
    function test_VerifiedClaimsCount_InitiallyZero() public view {
        assertEq(registry.getVerifiedClaimsCount(alice), 0);
    }
    
    function test_VerifiedClaimsCount_IncrementedOnUncontested() public {
        vm.prank(alice);
        uint256 claimId = registry.submitClaim("Test claim", "ipfs://test", MINIMUM_STAKE);
        
        // Fast forward past challenge period
        vm.warp(block.timestamp + CHALLENGE_PERIOD + 1);
        
        registry.verifyUnchallenged(claimId);
        
        assertEq(registry.getVerifiedClaimsCount(alice), 1);
    }
    
    function test_VerifiedClaimsCount_MultipleClaimsAccumulate() public {
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(alice);
            uint256 claimId = registry.submitClaim(
                string(abi.encodePacked("Claim ", i)),
                "ipfs://test",
                MINIMUM_STAKE
            );
            
            vm.warp(block.timestamp + CHALLENGE_PERIOD + 1);
            registry.verifyUnchallenged(claimId);
        }
        
        assertEq(registry.getVerifiedClaimsCount(alice), 5);
    }

    // ============ Bootstrap Airdrop Tests ============
    
    function test_Bootstrap_AirdropEligibility_NotEnoughClaims() public {
        (bool eligible, uint256 claims, string memory reason) = 
            bootstrap.checkAirdropEligibility(alice);
        
        assertFalse(eligible);
        assertEq(claims, 0);
        assertEq(reason, "Insufficient verified claims");
    }
    
    function test_Bootstrap_AirdropEligibility_Eligible() public {
        // Create 10 verified claims for alice
        _createVerifiedClaims(alice, 10);
        
        (bool eligible, uint256 claims, string memory reason) = 
            bootstrap.checkAirdropEligibility(alice);
        
        assertTrue(eligible);
        assertEq(claims, 10);
        assertEq(reason, "Eligible");
    }
    
    function test_Bootstrap_ClaimAirdrop_Success() public {
        _createVerifiedClaims(alice, 10);
        
        uint256 aliceBalanceBefore = emet.balanceOf(alice);
        
        vm.prank(alice);
        bootstrap.claimAirdrop();
        
        assertEq(emet.balanceOf(alice), aliceBalanceBefore + 40_000e18);
        assertTrue(bootstrap.hasClaimedAirdrop(alice));
        assertEq(bootstrap.airdropRecipientCount(), 1);
    }
    
    function test_Bootstrap_ClaimAirdrop_EmitsEvent() public {
        _createVerifiedClaims(alice, 15);
        
        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit EMETBootstrap.AirdropClaimed(alice, 40_000e18, 15);
        bootstrap.claimAirdrop();
    }
    
    function test_Bootstrap_ClaimAirdrop_CannotClaimTwice() public {
        _createVerifiedClaims(alice, 10);
        
        vm.prank(alice);
        bootstrap.claimAirdrop();
        
        vm.prank(alice);
        vm.expectRevert(EMETBootstrap.AlreadyClaimed.selector);
        bootstrap.claimAirdrop();
    }
    
    function test_Bootstrap_ClaimAirdrop_InsufficientClaims() public {
        _createVerifiedClaims(alice, 5); // Only 5, need 10
        
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                EMETBootstrap.InsufficientVerifiedClaims.selector,
                5,
                10
            )
        );
        bootstrap.claimAirdrop();
    }

    // ============ Bootstrap Vesting Tests ============
    
    function test_Bootstrap_VestingQuarter_Initial() public view {
        assertEq(bootstrap.getCurrentQuarter(), 1);
    }
    
    function test_Bootstrap_VestingQuarter_After90Days() public {
        vm.warp(block.timestamp + 90 days);
        assertEq(bootstrap.getCurrentQuarter(), 2);
    }
    
    function test_Bootstrap_VestingQuarter_CapsAt4() public {
        vm.warp(block.timestamp + 500 days); // Way past 4 quarters
        assertEq(bootstrap.getCurrentQuarter(), 4);
    }
    
    function test_Bootstrap_GrantVesting_FirstQuarter() public {
        (uint256 vested, uint256 disbursed, uint256 available) = 
            bootstrap.getGrantVestingStatus();
        
        // First quarter: 25% of 60M = 15M
        assertEq(vested, 15_000_000e18);
        assertEq(disbursed, 0);
        assertEq(available, 15_000_000e18);
    }
    
    function test_Bootstrap_GrantVesting_SecondQuarter() public {
        vm.warp(block.timestamp + 90 days);
        
        (uint256 vested, uint256 disbursed, uint256 available) = 
            bootstrap.getGrantVestingStatus();
        
        // Second quarter: 50% of 60M = 30M
        assertEq(vested, 30_000_000e18);
        assertEq(disbursed, 0);
        assertEq(available, 30_000_000e18);
    }
    
    function test_Bootstrap_DisburseGrant_Success() public {
        address recipient = makeAddr("grantRecipient");
        uint256 amount = 1_000_000e18; // 1M EMET
        
        vm.prank(owner);
        bootstrap.disburseGrant(recipient, amount, "Development milestone 1");
        
        assertEq(emet.balanceOf(recipient), amount);
        assertEq(bootstrap.totalGrantsDisbursed(), amount);
    }
    
    function test_Bootstrap_DisburseGrant_ExceedsVested() public {
        address recipient = makeAddr("grantRecipient");
        uint256 amount = 20_000_000e18; // 20M, but only 15M vested in Q1
        
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                EMETBootstrap.InsufficientProgramBalance.selector,
                "developerGrants",
                amount,
                15_000_000e18
            )
        );
        bootstrap.disburseGrant(recipient, amount, "Too much");
    }
    
    function test_Bootstrap_DisburseGrant_NonOwnerFails() public {
        vm.prank(alice);
        vm.expectRevert(EMETBootstrap.OnlyOwner.selector);
        bootstrap.disburseGrant(alice, 1e18, "Attempt");
    }

    // ============ Bootstrap Jury Incentives Tests ============
    
    function test_Bootstrap_JuryIncentive_Success() public {
        address juror = makeAddr("juror");
        uint256 amount = 100e18;
        
        vm.prank(owner);
        bootstrap.distributeJuryIncentive(juror, amount);
        
        assertEq(emet.balanceOf(juror), amount);
        assertEq(bootstrap.totalJuryDisbursed(), amount);
    }
    
    function test_Bootstrap_JuryIncentive_Batch() public {
        address[] memory jurors = new address[](3);
        jurors[0] = makeAddr("juror1");
        jurors[1] = makeAddr("juror2");
        jurors[2] = makeAddr("juror3");
        
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e18;
        amounts[1] = 200e18;
        amounts[2] = 150e18;
        
        vm.prank(owner);
        bootstrap.distributeJuryIncentiveBatch(jurors, amounts);
        
        assertEq(emet.balanceOf(jurors[0]), 100e18);
        assertEq(emet.balanceOf(jurors[1]), 200e18);
        assertEq(emet.balanceOf(jurors[2]), 150e18);
        assertEq(bootstrap.totalJuryDisbursed(), 450e18);
    }

    // ============ Bootstrap Learning Rewards Tests ============
    
    function test_Bootstrap_LearningReward_Success() public {
        address learner = makeAddr("learner");
        uint256 amount = 500e18;
        
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit EMETBootstrap.LearningRewardPaid(learner, amount, "Code Review Capability");
        bootstrap.distributeLearningReward(learner, amount, "Code Review Capability");
        
        assertEq(emet.balanceOf(learner), amount);
        assertEq(bootstrap.totalLearningDisbursed(), amount);
    }

    // ============ Bootstrap Strategic Reserve Tests ============
    
    function test_Bootstrap_StrategicReserve_OwnerOnly() public {
        address recipient = makeAddr("strategic");
        
        vm.prank(owner);
        bootstrap.disburseStrategic(recipient, 1_000_000e18, "Partnership deal");
        
        assertEq(emet.balanceOf(recipient), 1_000_000e18);
    }

    // ============ Bootstrap Program Balances Tests ============
    
    function test_Bootstrap_InitialBalances() public view {
        (
            uint256 earlyAdopter,
            uint256 developerGrants,
            uint256 juryIncentives,
            uint256 proofOfLearning,
            uint256 strategicReserve,
            uint256 unallocated
        ) = bootstrap.getProgramBalances();
        
        assertEq(earlyAdopter, 40_000_000e18);
        assertEq(developerGrants, 60_000_000e18);
        assertEq(juryIncentives, 20_000_000e18);
        assertEq(proofOfLearning, 20_000_000e18);
        assertEq(strategicReserve, 20_000_000e18);
        assertEq(unallocated, 240_000_000e18);
    }
    
    function test_Bootstrap_Balance() public view {
        assertEq(bootstrap.balance(), 400_000_000e18);
    }

    // ============ Ownership Tests ============
    
    function test_Registry_TransferOwnership() public {
        address newOwner = makeAddr("newOwner");
        
        vm.prank(owner);
        registry.transferOwnership(newOwner);
        
        assertEq(registry.owner(), newOwner);
    }
    
    function test_Bootstrap_TransferOwnership() public {
        address newOwner = makeAddr("newOwner");
        
        vm.prank(owner);
        bootstrap.transferOwnership(newOwner);
        
        assertEq(bootstrap.owner(), newOwner);
    }

    // ============ Helper Functions ============
    
    function _createVerifiedClaims(address submitter, uint256 count) internal {
        for (uint256 i = 0; i < count; i++) {
            vm.prank(submitter);
            uint256 claimId = registry.submitClaim(
                string(abi.encodePacked("Verified Claim ", i)),
                "ipfs://test",
                MINIMUM_STAKE
            );
            
            vm.warp(block.timestamp + CHALLENGE_PERIOD + 1);
            registry.verifyUnchallenged(claimId);
        }
    }
}
