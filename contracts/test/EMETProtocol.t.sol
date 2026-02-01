// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, console} from "forge-std/Test.sol";
import {EMETRegistry} from "../src/EMETRegistry.sol";
import {EMETStake} from "../src/EMETStake.sol";
import {EMETChallenge} from "../src/EMETChallenge.sol";
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

contract EMETProtocolTest is Test {
    // Contracts
    EMETRegistry public registry;
    EMETStake public stakeContract;
    EMETChallenge public challengeContract;
    MockEMET public emet;
    
    // Test accounts
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    
    // Constants
    uint256 public constant MINIMUM_STAKE = 100e18;
    uint256 public constant CHALLENGE_PERIOD = 7 days;
    uint256 public constant MINIMUM_CHALLENGE_STAKE = 50e18;
    
    function setUp() public {
        // Deploy mock EMET
        emet = new MockEMET();
        
        // We need to deploy at the expected address for the contracts to work
        // For testing, we'll use vm.etch to put our mock at the expected address
        address expectedEMET = 0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C;
        vm.etch(expectedEMET, address(emet).code);
        
        // Re-point emet to the expected address
        emet = MockEMET(expectedEMET);
        
        // Deploy protocol contracts
        registry = new EMETRegistry(MINIMUM_STAKE, CHALLENGE_PERIOD);
        stakeContract = new EMETStake(address(registry));
        challengeContract = new EMETChallenge(
            address(registry),
            address(stakeContract),
            MINIMUM_CHALLENGE_STAKE
        );
        
        // Link contracts
        registry.setChallengeContract(address(challengeContract));
        stakeContract.setChallengeContract(address(challengeContract));
        
        // Fund test accounts
        emet.mint(alice, 10000e18);
        emet.mint(bob, 10000e18);
        emet.mint(charlie, 10000e18);
        
        // Approve contracts
        vm.prank(alice);
        emet.approve(address(registry), type(uint256).max);
        vm.prank(alice);
        emet.approve(address(stakeContract), type(uint256).max);
        vm.prank(alice);
        emet.approve(address(challengeContract), type(uint256).max);
        
        vm.prank(bob);
        emet.approve(address(registry), type(uint256).max);
        vm.prank(bob);
        emet.approve(address(stakeContract), type(uint256).max);
        vm.prank(bob);
        emet.approve(address(challengeContract), type(uint256).max);
        
        vm.prank(charlie);
        emet.approve(address(registry), type(uint256).max);
        vm.prank(charlie);
        emet.approve(address(stakeContract), type(uint256).max);
        vm.prank(charlie);
        emet.approve(address(challengeContract), type(uint256).max);
    }
    
    // ============ Registry Tests ============
    
    function test_SubmitClaim() public {
        bytes32 claimHash = keccak256("Test claim");
        string memory evidenceURI = "ipfs://QmTest";
        
        vm.prank(alice);
        uint256 claimId = registry.submitClaim(claimHash, evidenceURI, MINIMUM_STAKE);
        
        assertEq(claimId, 0);
        assertEq(registry.claimCount(), 1);
        
        EMETRegistry.Claim memory claim = registry.getClaim(claimId);
        assertEq(claim.claimHash, claimHash);
        assertEq(claim.submitter, alice);
        assertEq(claim.stake, MINIMUM_STAKE);
        assertEq(uint256(claim.status), uint256(EMETRegistry.ClaimStatus.Active));
    }
    
    function test_SubmitClaim_InsufficientStake() public {
        bytes32 claimHash = keccak256("Test claim");
        string memory evidenceURI = "ipfs://QmTest";
        
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                EMETRegistry.InsufficientStake.selector,
                50e18,
                MINIMUM_STAKE
            )
        );
        registry.submitClaim(claimHash, evidenceURI, 50e18);
    }
    
    function test_VerifyUnchallenged() public {
        bytes32 claimHash = keccak256("Test claim");
        
        vm.prank(alice);
        uint256 claimId = registry.submitClaim(claimHash, "ipfs://test", MINIMUM_STAKE);
        
        uint256 balanceBefore = emet.balanceOf(alice);
        
        // Fast forward past challenge period
        vm.warp(block.timestamp + CHALLENGE_PERIOD + 1);
        
        registry.verifyUnchallenged(claimId);
        
        EMETRegistry.Claim memory claim = registry.getClaim(claimId);
        assertEq(uint256(claim.status), uint256(EMETRegistry.ClaimStatus.Verified));
        
        // Stake should be returned
        assertEq(emet.balanceOf(alice), balanceBefore + MINIMUM_STAKE);
    }
    
    // ============ Challenge Tests ============
    
    function test_InitiateChallenge() public {
        // Alice submits claim
        vm.prank(alice);
        uint256 claimId = registry.submitClaim(keccak256("claim"), "ipfs://test", MINIMUM_STAKE);
        
        // Bob challenges
        vm.prank(bob);
        challengeContract.initiateChallenge(claimId, MINIMUM_CHALLENGE_STAKE);
        
        EMETRegistry.Claim memory claim = registry.getClaim(claimId);
        assertEq(uint256(claim.status), uint256(EMETRegistry.ClaimStatus.Challenged));
        assertGt(claim.challengeEnd, block.timestamp);
        
        (address challenger, uint256 stake,,) = challengeContract.getChallenge(claimId);
        assertEq(challenger, bob);
        assertEq(stake, MINIMUM_CHALLENGE_STAKE);
    }
    
    function test_CannotChallengeSelf() public {
        vm.prank(alice);
        uint256 claimId = registry.submitClaim(keccak256("claim"), "ipfs://test", MINIMUM_STAKE);
        
        vm.prank(alice);
        vm.expectRevert(EMETChallenge.CannotChallengeOwnClaim.selector);
        challengeContract.initiateChallenge(claimId, MINIMUM_CHALLENGE_STAKE);
    }
    
    function test_ResolveChallenge_ClaimVerified() public {
        // Alice submits claim with 100 EMET
        vm.prank(alice);
        uint256 claimId = registry.submitClaim(keccak256("claim"), "ipfs://test", MINIMUM_STAKE);
        
        // Bob challenges with 50 EMET
        vm.prank(bob);
        challengeContract.initiateChallenge(claimId, MINIMUM_CHALLENGE_STAKE);
        
        // Charlie supports claim with 100 EMET
        vm.prank(charlie);
        stakeContract.stakeFor(claimId, 100e18);
        
        // Total for: 100 (claim) + 100 (charlie) = 200
        // Total against: 50 (bob) = 50
        // Claim should be verified
        
        // Fast forward past challenge period
        vm.warp(block.timestamp + CHALLENGE_PERIOD + 1);
        
        challengeContract.resolveChallenge(claimId);
        
        EMETRegistry.Claim memory claim = registry.getClaim(claimId);
        assertEq(uint256(claim.status), uint256(EMETRegistry.ClaimStatus.Verified));
    }
    
    function test_ResolveChallenge_ClaimRejected() public {
        // Alice submits claim with 100 EMET
        vm.prank(alice);
        uint256 claimId = registry.submitClaim(keccak256("claim"), "ipfs://test", MINIMUM_STAKE);
        
        // Bob challenges with 150 EMET (more than claim stake)
        vm.prank(bob);
        challengeContract.initiateChallenge(claimId, 150e18);
        
        // Total for: 100 (claim) = 100
        // Total against: 150 (bob) = 150
        // Claim should be rejected
        
        vm.warp(block.timestamp + CHALLENGE_PERIOD + 1);
        
        challengeContract.resolveChallenge(claimId);
        
        EMETRegistry.Claim memory claim = registry.getClaim(claimId);
        assertEq(uint256(claim.status), uint256(EMETRegistry.ClaimStatus.Rejected));
    }
    
    // ============ Stake Tests ============
    
    function test_StakeFor() public {
        vm.prank(alice);
        uint256 claimId = registry.submitClaim(keccak256("claim"), "ipfs://test", MINIMUM_STAKE);
        
        vm.prank(bob);
        stakeContract.stakeFor(claimId, 50e18);
        
        (uint256 totalFor, uint256 totalAgainst) = stakeContract.getStakeTotals(claimId);
        assertEq(totalFor, 50e18);
        assertEq(totalAgainst, 0);
        
        (uint256 userFor,) = stakeContract.getUserStakes(claimId, bob);
        assertEq(userFor, 50e18);
    }
    
    function test_Withdraw_Winner() public {
        // Setup: Alice claims, Bob challenges, Charlie supports, claim verified
        vm.prank(alice);
        uint256 claimId = registry.submitClaim(keccak256("claim"), "ipfs://test", MINIMUM_STAKE);
        
        vm.prank(bob);
        challengeContract.initiateChallenge(claimId, 100e18);
        
        vm.prank(charlie);
        stakeContract.stakeFor(claimId, 100e18);
        
        uint256 charlieBalanceBefore = emet.balanceOf(charlie);
        
        vm.warp(block.timestamp + CHALLENGE_PERIOD + 1);
        challengeContract.resolveChallenge(claimId);
        
        // Charlie withdraws (winner)
        vm.prank(charlie);
        stakeContract.withdraw(claimId);
        
        // Charlie should get stake back + share of losers
        uint256 charlieBalanceAfter = emet.balanceOf(charlie);
        assertGt(charlieBalanceAfter, charlieBalanceBefore);
    }
    
    // ============ View Function Tests ============
    
    function test_CanVerifyUnchallenged() public {
        vm.prank(alice);
        uint256 claimId = registry.submitClaim(keccak256("claim"), "ipfs://test", MINIMUM_STAKE);
        
        assertFalse(registry.canVerifyUnchallenged(claimId));
        
        vm.warp(block.timestamp + CHALLENGE_PERIOD + 1);
        
        assertTrue(registry.canVerifyUnchallenged(claimId));
    }
    
    function test_GetCurrentStanding() public {
        vm.prank(alice);
        uint256 claimId = registry.submitClaim(keccak256("claim"), "ipfs://test", MINIMUM_STAKE);
        
        vm.prank(bob);
        challengeContract.initiateChallenge(claimId, 50e18);
        
        (uint256 effectiveFor, uint256 against, string memory winner) = 
            challengeContract.getCurrentStanding(claimId);
        
        assertEq(effectiveFor, MINIMUM_STAKE); // claim stake
        assertEq(against, 50e18);
        assertEq(winner, "for");
    }
}
