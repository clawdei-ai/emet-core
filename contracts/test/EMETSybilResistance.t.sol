// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, console} from "forge-std/Test.sol";
import {EMETSybilResistance} from "../src/EMETSybilResistance.sol";
import {IEMET} from "../src/interfaces/IEMET.sol";

/// @title EMETSybilResistance Tests
contract EMETSybilResistanceTest is Test {
    EMETSybilResistance public sybil;
    MockEMETSR public mockToken;

    address public deployer = address(1);
    address public treasuryAddr = address(2);
    address public authorizedCaller = address(3);
    address public sponsor1 = address(10);
    address public sponsor2 = address(11);
    address public newAgent1 = address(20);
    address public newAgent2 = address(21);
    address public newAgent3 = address(22);
    address public newAgent4 = address(23);
    address public newAgent5 = address(24);
    address public newAgent6 = address(25);

    uint256 public constant INITIAL_BALANCE = 100_000 ether;

    function setUp() public {
        // Deploy mock token
        address emetAddress = 0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C;
        vm.etch(emetAddress, type(MockEMETSR).runtimeCode);
        mockToken = MockEMETSR(emetAddress);

        // Deploy sybil resistance
        vm.prank(deployer);
        sybil = new EMETSybilResistance(treasuryAddr);

        // Authorize caller
        vm.prank(deployer);
        sybil.setAuthorizedCaller(authorizedCaller, true);

        // Fund sponsors
        mockToken.mint(sponsor1, INITIAL_BALANCE);
        mockToken.mint(sponsor2, INITIAL_BALANCE);
        vm.prank(sponsor1);
        mockToken.approve(address(sybil), type(uint256).max);
        vm.prank(sponsor2);
        mockToken.approve(address(sybil), type(uint256).max);

        // Fund contract for graduation bonuses
        mockToken.mint(address(sybil), 50_000 ether);
    }

    // ============ Sponsorship Tests ============

    function test_Sponsor_Success() public {
        vm.prank(sponsor1);
        sybil.sponsor(newAgent1, 500 ether);

        EMETSybilResistance.Sponsorship memory sp = sybil.getSponsorship(newAgent1);
        assertEq(sp.sponsor, sponsor1);
        assertEq(sp.sponsee, newAgent1);
        assertEq(sp.stake, 500 ether);
        assertTrue(sp.active);
        assertFalse(sp.graduated);
        assertFalse(sp.slashed);
    }

    function test_Sponsor_HigherStake() public {
        vm.prank(sponsor1);
        sybil.sponsor(newAgent1, 2000 ether);

        EMETSybilResistance.Sponsorship memory sp = sybil.getSponsorship(newAgent1);
        assertEq(sp.stake, 2000 ether);
    }

    function test_Sponsor_InsufficientStake() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                EMETSybilResistance.InsufficientStake.selector,
                499 ether,
                500 ether
            )
        );
        vm.prank(sponsor1);
        sybil.sponsor(newAgent1, 499 ether);
    }

    function test_Sponsor_AlreadySponsored() public {
        vm.prank(sponsor1);
        sybil.sponsor(newAgent1, 500 ether);

        vm.expectRevert(
            abi.encodeWithSelector(EMETSybilResistance.AlreadySponsored.selector, newAgent1)
        );
        vm.prank(sponsor2);
        sybil.sponsor(newAgent1, 500 ether);
    }

    function test_Sponsor_CannotSponsorSelf() public {
        vm.expectRevert(EMETSybilResistance.CannotSponsorSelf.selector);
        vm.prank(sponsor1);
        sybil.sponsor(sponsor1, 500 ether);
    }

    function test_Sponsor_ZeroAddress() public {
        vm.expectRevert(EMETSybilResistance.ZeroAddress.selector);
        vm.prank(sponsor1);
        sybil.sponsor(address(0), 500 ether);
    }

    function test_Sponsor_BannedSponsee() public {
        // Create and slash a sponsorship to get sponsee banned
        vm.prank(sponsor1);
        sybil.sponsor(newAgent1, 500 ether);

        // Slash → bans the sponsee
        vm.prank(authorizedCaller);
        sybil.slashSponsor(newAgent1);

        // Already-sponsored check fires before banned check since wasSponsored is set
        // Test that the banned agent can't be re-sponsored (AlreadySponsored takes precedence)
        vm.expectRevert(
            abi.encodeWithSelector(EMETSybilResistance.AlreadySponsored.selector, newAgent1)
        );
        vm.prank(sponsor2);
        sybil.sponsor(newAgent1, 500 ether);

        // Verify the address IS banned
        assertTrue(sybil.isBanned(newAgent1));
    }

    function test_Sponsor_TokenTransfer() public {
        uint256 balBefore = mockToken.balanceOf(sponsor1);

        vm.prank(sponsor1);
        sybil.sponsor(newAgent1, 500 ether);

        assertEq(mockToken.balanceOf(sponsor1), balBefore - 500 ether);
        assertGe(mockToken.balanceOf(address(sybil)), 500 ether);
    }

    function test_Sponsor_UpdatesSponsorStats() public {
        vm.prank(sponsor1);
        sybil.sponsor(newAgent1, 500 ether);

        EMETSybilResistance.Sponsor memory sp = sybil.getSponsorStats(sponsor1);
        assertEq(sp.addr, sponsor1);
        assertEq(sp.totalSponsored, 1);
        assertEq(sp.slashedAmount, 0);
    }

    // ============ Rate Limiting Tests ============

    function test_RateLimiting_MaxPerEpoch() public {
        address[5] memory agents = [newAgent1, newAgent2, newAgent3, newAgent4, newAgent5];

        for (uint256 i = 0; i < 5; i++) {
            vm.prank(sponsor1);
            sybil.sponsor(agents[i], 500 ether);
        }

        // 6th should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                EMETSybilResistance.RateLimitExceeded.selector,
                sponsor1,
                5,
                5
            )
        );
        vm.prank(sponsor1);
        sybil.sponsor(newAgent6, 500 ether);
    }

    function test_RateLimiting_ResetsAfterEpoch() public {
        address[5] memory agents = [newAgent1, newAgent2, newAgent3, newAgent4, newAgent5];

        for (uint256 i = 0; i < 5; i++) {
            vm.prank(sponsor1);
            sybil.sponsor(agents[i], 500 ether);
        }

        // Move to next epoch
        vm.warp(block.timestamp + 31 days);

        // Should work in new epoch
        vm.prank(sponsor1);
        sybil.sponsor(newAgent6, 500 ether);
    }

    function test_CanSponsor_Success() public {
        (bool canDo, string memory reason) = sybil.canSponsor(sponsor1);
        assertTrue(canDo);
        assertEq(bytes(reason).length, 0);
    }

    function test_CanSponsor_RateLimited() public {
        address[5] memory agents = [newAgent1, newAgent2, newAgent3, newAgent4, newAgent5];

        for (uint256 i = 0; i < 5; i++) {
            vm.prank(sponsor1);
            sybil.sponsor(agents[i], 500 ether);
        }

        (bool canDo, string memory reason) = sybil.canSponsor(sponsor1);
        assertFalse(canDo);
        assertGt(bytes(reason).length, 0);
    }

    function test_GetEpochSponsorshipCount() public {
        assertEq(sybil.getEpochSponsorshipCount(sponsor1), 0);

        vm.prank(sponsor1);
        sybil.sponsor(newAgent1, 500 ether);

        assertEq(sybil.getEpochSponsorshipCount(sponsor1), 1);
    }

    // ============ Slashing Tests ============

    function test_SlashSponsor_Success() public {
        vm.prank(sponsor1);
        sybil.sponsor(newAgent1, 500 ether);

        uint256 treasuryBefore = mockToken.balanceOf(treasuryAddr);

        vm.prank(authorizedCaller);
        sybil.slashSponsor(newAgent1);

        // Sponsorship state
        EMETSybilResistance.Sponsorship memory sp = sybil.getSponsorship(newAgent1);
        assertTrue(sp.slashed);
        assertFalse(sp.active);

        // Sponsor stats
        EMETSybilResistance.Sponsor memory sponsor = sybil.getSponsorStats(sponsor1);
        assertEq(sponsor.slashedAmount, 500 ether);
        assertEq(sponsor.failedSponsees, 1);

        // Sponsee banned
        assertTrue(sybil.isBanned(newAgent1));

        // Stake sent to treasury
        assertEq(mockToken.balanceOf(treasuryAddr) - treasuryBefore, 500 ether);
    }

    function test_SlashSponsor_NotSponsored() public {
        vm.expectRevert(
            abi.encodeWithSelector(EMETSybilResistance.NotSponsored.selector, newAgent1)
        );
        vm.prank(authorizedCaller);
        sybil.slashSponsor(newAgent1);
    }

    function test_SlashSponsor_AlreadySlashed() public {
        vm.prank(sponsor1);
        sybil.sponsor(newAgent1, 500 ether);

        vm.prank(authorizedCaller);
        sybil.slashSponsor(newAgent1);

        vm.expectRevert(
            abi.encodeWithSelector(EMETSybilResistance.SponsorshipNotActive.selector, newAgent1)
        );
        vm.prank(authorizedCaller);
        sybil.slashSponsor(newAgent1);
    }

    function test_SlashSponsor_OnlyAuthorized() public {
        vm.prank(sponsor1);
        sybil.sponsor(newAgent1, 500 ether);

        vm.expectRevert(EMETSybilResistance.OnlyAuthorizedCaller.selector);
        vm.prank(sponsor1);
        sybil.slashSponsor(newAgent1);
    }

    function test_SlashSponsor_MultipleSlashes() public {
        vm.prank(sponsor1);
        sybil.sponsor(newAgent1, 500 ether);
        vm.prank(sponsor1);
        sybil.sponsor(newAgent2, 600 ether);

        vm.prank(authorizedCaller);
        sybil.slashSponsor(newAgent1);
        vm.prank(authorizedCaller);
        sybil.slashSponsor(newAgent2);

        EMETSybilResistance.Sponsor memory sp = sybil.getSponsorStats(sponsor1);
        assertEq(sp.slashedAmount, 1100 ether);
        assertEq(sp.failedSponsees, 2);
        assertEq(sybil.totalSlashes(), 2);
    }

    // ============ Graduation Tests ============

    function test_GraduateSponsor_Success() public {
        vm.prank(sponsor1);
        sybil.sponsor(newAgent1, 500 ether);

        uint256 sponsorBefore = mockToken.balanceOf(sponsor1);

        vm.prank(authorizedCaller);
        sybil.graduateSponsor(newAgent1);

        // Sponsorship state
        EMETSybilResistance.Sponsorship memory sp = sybil.getSponsorship(newAgent1);
        assertTrue(sp.graduated);
        assertFalse(sp.active);

        // Sponsor stats
        EMETSybilResistance.Sponsor memory sponsor = sybil.getSponsorStats(sponsor1);
        assertEq(sponsor.successfulSponsees, 1);

        // Sponsor gets stake back + 10% bonus = 550 ether
        uint256 expectedReturn = 500 ether + (500 ether * 1000 / 10_000);
        assertEq(mockToken.balanceOf(sponsor1) - sponsorBefore, expectedReturn);
    }

    function test_GraduateSponsor_NotSponsored() public {
        vm.expectRevert(
            abi.encodeWithSelector(EMETSybilResistance.NotSponsored.selector, newAgent1)
        );
        vm.prank(authorizedCaller);
        sybil.graduateSponsor(newAgent1);
    }

    function test_GraduateSponsor_AlreadyGraduated() public {
        vm.prank(sponsor1);
        sybil.sponsor(newAgent1, 500 ether);

        vm.prank(authorizedCaller);
        sybil.graduateSponsor(newAgent1);

        vm.expectRevert(
            abi.encodeWithSelector(EMETSybilResistance.SponsorshipNotActive.selector, newAgent1)
        );
        vm.prank(authorizedCaller);
        sybil.graduateSponsor(newAgent1);
    }

    function test_GraduateSponsor_OnlyAuthorized() public {
        vm.prank(sponsor1);
        sybil.sponsor(newAgent1, 500 ether);

        vm.expectRevert(EMETSybilResistance.OnlyAuthorizedCaller.selector);
        vm.prank(sponsor1);
        sybil.graduateSponsor(newAgent1);
    }

    function test_GraduateSponsor_AfterSlashFails() public {
        vm.prank(sponsor1);
        sybil.sponsor(newAgent1, 500 ether);

        vm.prank(authorizedCaller);
        sybil.slashSponsor(newAgent1);

        vm.expectRevert(
            abi.encodeWithSelector(EMETSybilResistance.SponsorshipNotActive.selector, newAgent1)
        );
        vm.prank(authorizedCaller);
        sybil.graduateSponsor(newAgent1);
    }

    // ============ View Function Tests ============

    function test_IsActivelySponsored() public {
        assertFalse(sybil.isActivelySponsored(newAgent1));

        vm.prank(sponsor1);
        sybil.sponsor(newAgent1, 500 ether);

        assertTrue(sybil.isActivelySponsored(newAgent1));
    }

    function test_IsBanned() public {
        assertFalse(sybil.isBanned(newAgent1));

        vm.prank(sponsor1);
        sybil.sponsor(newAgent1, 500 ether);
        vm.prank(authorizedCaller);
        sybil.slashSponsor(newAgent1);

        assertTrue(sybil.isBanned(newAgent1));
    }

    function test_TotalSponsorships() public {
        assertEq(sybil.totalSponsorships(), 0);

        vm.prank(sponsor1);
        sybil.sponsor(newAgent1, 500 ether);

        assertEq(sybil.totalSponsorships(), 1);
    }

    function test_TotalGraduations() public {
        vm.prank(sponsor1);
        sybil.sponsor(newAgent1, 500 ether);

        vm.prank(authorizedCaller);
        sybil.graduateSponsor(newAgent1);

        assertEq(sybil.totalGraduations(), 1);
    }

    // ============ Authorization Tests ============

    function test_SetAuthorizedCaller_OnlyDeployer() public {
        vm.expectRevert(EMETSybilResistance.OnlyDeployer.selector);
        vm.prank(sponsor1);
        sybil.setAuthorizedCaller(address(99), true);
    }

    function test_SetAuthorizedCaller_ZeroAddress() public {
        vm.expectRevert(EMETSybilResistance.ZeroAddress.selector);
        vm.prank(deployer);
        sybil.setAuthorizedCaller(address(0), true);
    }

    function test_SetAuthorizedCaller_Deauthorize() public {
        vm.prank(deployer);
        sybil.setAuthorizedCaller(authorizedCaller, false);

        vm.prank(sponsor1);
        sybil.sponsor(newAgent1, 500 ether);

        vm.expectRevert(EMETSybilResistance.OnlyAuthorizedCaller.selector);
        vm.prank(authorizedCaller);
        sybil.slashSponsor(newAgent1);
    }

    // ============ Constructor Tests ============

    function test_ZeroAddressConstructor() public {
        vm.expectRevert(EMETSybilResistance.ZeroAddress.selector);
        new EMETSybilResistance(address(0));
    }
}

// ============ Mock Token ============

contract MockEMETSR {
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
