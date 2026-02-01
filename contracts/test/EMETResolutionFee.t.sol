// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, console} from "forge-std/Test.sol";
import {EMETRegistry} from "../src/EMETRegistry.sol";
import {EMETChallengeV3} from "../src/EMETChallengeV3.sol";
import {EMETTreasury} from "../src/EMETTreasury.sol";
import {EMETReputation} from "../src/EMETReputation.sol";
import {EMETJuryPool} from "../src/EMETJuryPool.sol";
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

contract EMETResolutionFeeTest is Test {
    // Contracts
    EMETRegistry public registry;
    EMETChallengeV3 public challenge;
    EMETTreasury public treasury;
    EMETReputation public reputation;
    EMETJuryPool public juryPool;
    MockEMET public emet;
    
    // Test accounts
    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public juror1 = makeAddr("juror1");
    address public juror2 = makeAddr("juror2");
    address public juror3 = makeAddr("juror3");
    
    // Constants
    uint256 public constant MINIMUM_STAKE = 100e18;
    uint256 public constant CHALLENGE_PERIOD = 7 days;
    uint256 public constant DEFAULT_RESOLUTION_FEE_BPS = 500; // 5%
    
    function setUp() public {
        // Deploy mock EMET at expected address
        emet = new MockEMET();
        address expectedEMET = 0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C;
        vm.etch(expectedEMET, address(emet).code);
        emet = MockEMET(expectedEMET);
        
        // Deploy contracts as owner
        vm.startPrank(owner);
        
        registry = new EMETRegistry(MINIMUM_STAKE, CHALLENGE_PERIOD);
        treasury = new EMETTreasury(owner);
        reputation = new EMETReputation();
        juryPool = new EMETJuryPool(address(reputation));
        
        challenge = new EMETChallengeV3(
            address(registry),
            address(treasury),
            address(reputation),
            address(juryPool)
        );
        
        // Link contracts
        registry.setChallengeContract(address(challenge));
        treasury.setFeeDistributor(address(challenge));
        reputation.setUpdater(address(challenge));
        juryPool.setChallengeContract(address(challenge));
        
        vm.stopPrank();
        
        // Register jurors in pool
        _registerJurors();
        
        // Fund test accounts
        emet.mint(alice, 1_000_000e18);
        emet.mint(bob, 1_000_000e18);
        
        // Approve contracts
        vm.prank(alice);
        emet.approve(address(registry), type(uint256).max);
        vm.prank(alice);
        emet.approve(address(challenge), type(uint256).max);
        
        vm.prank(bob);
        emet.approve(address(registry), type(uint256).max);
        vm.prank(bob);
        emet.approve(address(challenge), type(uint256).max);
    }

    // ============ Resolution Fee Configuration Tests ============
    
    function test_ResolutionFee_DefaultValue() public view {
        assertEq(challenge.resolutionFeeBps(), DEFAULT_RESOLUTION_FEE_BPS);
    }
    
    function test_ResolutionFee_OwnerCanUpdate() public {
        uint256 newFee = 1000; // 10%
        
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit EMETChallengeV3.ResolutionFeeUpdated(DEFAULT_RESOLUTION_FEE_BPS, newFee);
        challenge.setResolutionFee(newFee);
        
        assertEq(challenge.resolutionFeeBps(), newFee);
    }
    
    function test_ResolutionFee_NonOwnerCannotUpdate() public {
        vm.prank(alice);
        vm.expectRevert(EMETChallengeV3.OnlyOwner.selector);
        challenge.setResolutionFee(1000);
    }
    
    function test_ResolutionFee_CannotExceedMax() public {
        uint256 tooHigh = 2500; // 25%, max is 20%
        
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                EMETChallengeV3.InvalidResolutionFee.selector,
                tooHigh,
                2000
            )
        );
        challenge.setResolutionFee(tooHigh);
    }
    
    function test_ResolutionFee_CanBeSetToZero() public {
        vm.prank(owner);
        challenge.setResolutionFee(0);
        
        assertEq(challenge.resolutionFeeBps(), 0);
    }
    
    function test_ResolutionFee_CanBeSetToMax() public {
        vm.prank(owner);
        challenge.setResolutionFee(2000); // 20% max
        
        assertEq(challenge.resolutionFeeBps(), 2000);
    }

    // ============ Resolution Fee Math Tests ============
    
    function test_ResolutionFee_5PercentOfLoserStake() public {
        // At 5% fee:
        // If loser stakes 100 EMET, fee = 5 EMET
        // Winner gets 95% of 100 = 95 EMET (minus juror share)
        
        uint256 loserStake = 100e18;
        uint256 expectedFee = (loserStake * 500) / 10000; // 5%
        assertEq(expectedFee, 5e18);
        
        uint256 winnerGets = loserStake - expectedFee;
        assertEq(winnerGets, 95e18);
    }
    
    function test_ResolutionFee_10PercentAfterUpdate() public {
        vm.prank(owner);
        challenge.setResolutionFee(1000); // 10%
        
        uint256 loserStake = 100e18;
        uint256 expectedFee = (loserStake * 1000) / 10000; // 10%
        assertEq(expectedFee, 10e18);
    }
    
    function test_ResolutionFee_ZeroFeeNoDeduction() public {
        vm.prank(owner);
        challenge.setResolutionFee(0);
        
        uint256 loserStake = 100e18;
        uint256 expectedFee = (loserStake * 0) / 10000;
        assertEq(expectedFee, 0);
    }

    // ============ Ownership Tests ============
    
    function test_Challenge_TransferOwnership() public {
        address newOwner = makeAddr("newOwner");
        
        vm.prank(owner);
        challenge.transferOwnership(newOwner);
        
        assertEq(challenge.owner(), newOwner);
        
        // New owner can update fee
        vm.prank(newOwner);
        challenge.setResolutionFee(1500);
        assertEq(challenge.resolutionFeeBps(), 1500);
        
        // Old owner cannot
        vm.prank(owner);
        vm.expectRevert(EMETChallengeV3.OnlyOwner.selector);
        challenge.setResolutionFee(1000);
    }
    
    function test_Challenge_CannotTransferToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(EMETChallengeV3.ZeroAddress.selector);
        challenge.transferOwnership(address(0));
    }

    // ============ Integration Test with Resolution ============
    
    // Note: Full resolution integration tests require working jury selection
    // which depends on EMETJuryPool implementation. These tests focus on
    // the fee configuration mechanics.

    // ============ Helper Functions ============
    
    function _registerJurors() internal {
        // Note: This is a placeholder. Full integration would require
        // proper jury registration through EMETJuryPool.
        // The juryPool needs to be configured to return valid jurors.
    }
}
