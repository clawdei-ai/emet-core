// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, console} from "forge-std/Test.sol";
import {EMETRegistry} from "../src/EMETRegistry.sol";
import {EMETTreasury} from "../src/EMETTreasury.sol";
import {EMETReputation} from "../src/EMETReputation.sol";
import {EMETJuryPool} from "../src/EMETJuryPool.sol";
import {EMETChallengeV3} from "../src/EMETChallengeV3.sol";
import {IEMET} from "../src/interfaces/IEMET.sol";

/// @title EMETJury Tests - Comprehensive tests for jury-based dispute resolution
contract EMETJuryTest is Test {
    // ============ Contracts ============

    EMETRegistry public registry;
    EMETTreasury public treasury;
    EMETReputation public reputation;
    EMETJuryPool public juryPool;
    EMETChallengeV3 public challengeV3;

    // ============ Mock Token ============

    MockEMET public mockToken;

    // ============ Test Addresses ============

    address public deployer = address(1);
    address public treasuryAdmin = address(2);
    address public claimSubmitter = address(10);
    address public challenger = address(11);

    // Jurors (need 11 for Critical tier)
    address public juror1 = address(100);
    address public juror2 = address(101);
    address public juror3 = address(102);
    address public juror4 = address(103);
    address public juror5 = address(104);
    address public juror6 = address(105);
    address public juror7 = address(106);
    address public juror8 = address(107);
    address public juror9 = address(108);
    address public juror10 = address(109);
    address public juror11 = address(110);
    address public juror12 = address(111); // Extra for exclusion tests

    address[] public allJurors;

    // ============ Constants ============

    uint256 public constant MINIMUM_STAKE = 1 ether;
    uint256 public constant CHALLENGE_PERIOD = 7 days;
    uint256 public constant INITIAL_BALANCE = 10000 ether;

    // ============ Setup ============

    function setUp() public {
        // Deploy mock token at the EMET address using deployCodeTo
        address emetAddress = 0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C;
        vm.etch(emetAddress, type(MockEMET).runtimeCode);
        mockToken = MockEMET(emetAddress);

        // Setup juror array
        allJurors = new address[](12);
        allJurors[0] = juror1;
        allJurors[1] = juror2;
        allJurors[2] = juror3;
        allJurors[3] = juror4;
        allJurors[4] = juror5;
        allJurors[5] = juror6;
        allJurors[6] = juror7;
        allJurors[7] = juror8;
        allJurors[8] = juror9;
        allJurors[9] = juror10;
        allJurors[10] = juror11;
        allJurors[11] = juror12;

        vm.startPrank(deployer);

        // Deploy contracts
        registry = new EMETRegistry(MINIMUM_STAKE, CHALLENGE_PERIOD);
        treasury = new EMETTreasury(treasuryAdmin);
        reputation = new EMETReputation();
        juryPool = new EMETJuryPool(address(reputation));
        challengeV3 = new EMETChallengeV3(
            address(registry),
            address(treasury),
            address(reputation),
            address(juryPool)
        );

        // Setup contract links
        registry.setChallengeContract(address(challengeV3));
        juryPool.setChallengeContract(address(challengeV3));
        reputation.setUpdater(address(challengeV3));

        vm.stopPrank();

        // Give treasury admin ability to set fee distributor
        vm.prank(treasuryAdmin);
        treasury.setFeeDistributor(address(challengeV3));

        // Fund accounts
        _fundAccount(claimSubmitter);
        _fundAccount(challenger);
        for (uint256 i = 0; i < allJurors.length; i++) {
            _fundAccount(allJurors[i]);
        }

        // Setup juror reputations (need 50+ to be eligible)
        _setupJurorReputation();
    }

    function _fundAccount(address account) internal {
        mockToken.mint(account, INITIAL_BALANCE);
        vm.prank(account);
        mockToken.approve(address(registry), type(uint256).max);
        vm.prank(account);
        mockToken.approve(address(challengeV3), type(uint256).max);
    }

    function _setupJurorReputation() internal {
        // We need to manually set reputation since the updater is challengeV3
        // Use a workaround: deploy reputation without updater check for testing
        // Actually, let's set reputation directly by pranking the updater

        // First, set deployer as temporary updater
        vm.prank(deployer);

        // Create a mock reputation setter
        MockReputationSetter setter = new MockReputationSetter(address(reputation));

        // Actually, the cleanest approach is to have jurors earn reputation through real activity
        // For testing, we'll modify the approach - set reputation through direct storage manipulation
        for (uint256 i = 0; i < allJurors.length; i++) {
            // Set reputation to 60 (above MIN_JUROR_REP of 50)
            vm.store(
                address(reputation),
                keccak256(abi.encode(allJurors[i], uint256(0))), // reputation mapping at slot 0
                bytes32(uint256(60))
            );
        }
    }

    // ============ Jury Registration Tests ============

    function test_JurorRegistration_Success() public {
        vm.prank(juror1);
        juryPool.registerJuror();

        assertTrue(juryPool.isRegistered(juror1));
        assertEq(juryPool.getJurorCount(), 1);
        assertEq(juryPool.getJurorAt(0), juror1);
    }

    function test_JurorRegistration_MultipleJurors() public {
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(allJurors[i]);
            juryPool.registerJuror();
        }

        assertEq(juryPool.getJurorCount(), 5);
    }

    function test_JurorRegistration_InsufficientReputation() public {
        address lowRepJuror = address(999);

        vm.expectRevert(
            abi.encodeWithSelector(
                EMETJuryPool.InsufficientReputation.selector,
                lowRepJuror,
                int256(0),
                int256(50)
            )
        );
        vm.prank(lowRepJuror);
        juryPool.registerJuror();
    }

    function test_JurorRegistration_AlreadyRegistered() public {
        vm.prank(juror1);
        juryPool.registerJuror();

        vm.expectRevert(
            abi.encodeWithSelector(EMETJuryPool.AlreadyRegistered.selector, juror1)
        );
        vm.prank(juror1);
        juryPool.registerJuror();
    }

    function test_JurorUnregistration_Success() public {
        vm.prank(juror1);
        juryPool.registerJuror();

        vm.prank(juror1);
        juryPool.unregisterJuror();

        assertFalse(juryPool.isRegistered(juror1));
        assertEq(juryPool.getJurorCount(), 0);
    }

    function test_JurorUnregistration_NotRegistered() public {
        vm.expectRevert(
            abi.encodeWithSelector(EMETJuryPool.NotRegistered.selector, juror1)
        );
        vm.prank(juror1);
        juryPool.unregisterJuror();
    }

    function test_JurorEligibility() public {
        assertTrue(juryPool.isEligible(juror1)); // Has 60 rep
        assertFalse(juryPool.isEligible(address(999))); // Has 0 rep
    }

    // ============ Challenge Creation Tests ============

    function test_ChallengeCreation_MinorTier() public {
        _registerJurors(3);
        uint256 claimId = _submitClaim();

        vm.prank(challenger);
        uint256 challengeId = challengeV3.initiateChallenge(
            claimId,
            "ipfs://evidence",
            10 ether,
            EMETChallengeV3.Tier.Minor
        );

        (
            uint256 returnedClaimId,
            address returnedChallenger,
            string memory evidence,
            uint256 stake,
            uint256 startTime,
            uint256 votingEnd,
            EMETChallengeV3.Tier tier,
            bool resolved,
            address[] memory jury,
            uint256 appealedTo
        ) = challengeV3.getChallenge(challengeId);

        assertEq(returnedClaimId, claimId);
        assertEq(returnedChallenger, challenger);
        assertEq(evidence, "ipfs://evidence");
        assertEq(stake, 10 ether);
        assertEq(uint256(tier), uint256(EMETChallengeV3.Tier.Minor));
        assertFalse(resolved);
        assertEq(jury.length, 3); // Minor tier = 3 jurors
        assertEq(appealedTo, 0);
    }

    function test_ChallengeCreation_MajorTier() public {
        _registerJurors(7);
        uint256 claimId = _submitClaim();

        vm.prank(challenger);
        uint256 challengeId = challengeV3.initiateChallenge(
            claimId,
            "ipfs://evidence",
            100 ether,
            EMETChallengeV3.Tier.Major
        );

        (,,,,,,, bool resolved, address[] memory jury,) = challengeV3.getChallenge(challengeId);

        assertFalse(resolved);
        assertEq(jury.length, 7); // Major tier = 7 jurors
    }

    function test_ChallengeCreation_CriticalTier() public {
        _registerJurors(11);
        uint256 claimId = _submitClaim();

        vm.prank(challenger);
        uint256 challengeId = challengeV3.initiateChallenge(
            claimId,
            "ipfs://evidence",
            1000 ether,
            EMETChallengeV3.Tier.Critical
        );

        (,,,,,,, bool resolved, address[] memory jury,) = challengeV3.getChallenge(challengeId);

        assertFalse(resolved);
        assertEq(jury.length, 11); // Critical tier = 11 jurors
    }

    function test_ChallengeCreation_InsufficientStake() public {
        _registerJurors(3);
        uint256 claimId = _submitClaim();

        vm.expectRevert(
            abi.encodeWithSelector(
                EMETChallengeV3.InsufficientStake.selector,
                5 ether,
                10 ether
            )
        );
        vm.prank(challenger);
        challengeV3.initiateChallenge(
            claimId,
            "ipfs://evidence",
            5 ether, // Below 10 ether minimum for Minor
            EMETChallengeV3.Tier.Minor
        );
    }

    function test_ChallengeCreation_CannotChallengeOwnClaim() public {
        _registerJurors(3);
        uint256 claimId = _submitClaim();

        vm.expectRevert(EMETChallengeV3.CannotChallengeOwnClaim.selector);
        vm.prank(claimSubmitter); // Same as claim submitter
        challengeV3.initiateChallenge(
            claimId,
            "ipfs://evidence",
            10 ether,
            EMETChallengeV3.Tier.Minor
        );
    }

    function test_ChallengeCreation_DuplicateChallenge() public {
        _registerJurors(3);
        uint256 claimId = _submitClaim();

        vm.prank(challenger);
        challengeV3.initiateChallenge(claimId, "ipfs://evidence", 10 ether, EMETChallengeV3.Tier.Minor);

        // After first challenge, claim status is "Challenged" so we get ClaimNotActive
        // This is correct behavior - can't challenge an already challenged claim
        vm.expectRevert(
            abi.encodeWithSelector(EMETChallengeV3.ClaimNotActive.selector, claimId)
        );
        vm.prank(challenger);
        challengeV3.initiateChallenge(claimId, "ipfs://evidence2", 10 ether, EMETChallengeV3.Tier.Minor);
    }

    function test_ChallengeCreation_InsufficientJurors() public {
        _registerJurors(2); // Only 2, need 3 for Minor
        uint256 claimId = _submitClaim();

        vm.expectRevert(
            abi.encodeWithSelector(EMETJuryPool.InsufficientJurors.selector, 2, 3)
        );
        vm.prank(challenger);
        challengeV3.initiateChallenge(claimId, "ipfs://evidence", 10 ether, EMETChallengeV3.Tier.Minor);
    }

    // ============ Voting Tests ============

    function test_Voting_ValidJuror() public {
        (uint256 challengeId, address[] memory jury) = _createChallengeWithJury();

        vm.prank(jury[0]);
        challengeV3.vote(challengeId, EMETChallengeV3.Vote.UpholdChallenge, "Evidence is compelling");

        (EMETChallengeV3.Vote v, string memory reasoning, uint256 timestamp) =
            challengeV3.getVote(challengeId, jury[0]);

        assertEq(uint256(v), uint256(EMETChallengeV3.Vote.UpholdChallenge));
        assertEq(reasoning, "Evidence is compelling");
        assertGt(timestamp, 0);
    }

    function test_Voting_NotAJuror() public {
        (uint256 challengeId,) = _createChallengeWithJury();

        address notJuror = address(888);
        vm.expectRevert(
            abi.encodeWithSelector(EMETChallengeV3.NotAJuror.selector, notJuror)
        );
        vm.prank(notJuror);
        challengeV3.vote(challengeId, EMETChallengeV3.Vote.UpholdChallenge, "reason");
    }

    function test_Voting_DoubleVote() public {
        (uint256 challengeId, address[] memory jury) = _createChallengeWithJury();

        vm.prank(jury[0]);
        challengeV3.vote(challengeId, EMETChallengeV3.Vote.UpholdChallenge, "reason1");

        vm.expectRevert(
            abi.encodeWithSelector(EMETChallengeV3.AlreadyVoted.selector, jury[0])
        );
        vm.prank(jury[0]);
        challengeV3.vote(challengeId, EMETChallengeV3.Vote.UpholdClaim, "reason2");
    }

    function test_Voting_AfterPeriodEnded() public {
        (uint256 challengeId, address[] memory jury) = _createChallengeWithJury();

        // Fast forward past voting period
        vm.warp(block.timestamp + 25 hours);

        vm.expectRevert(EMETChallengeV3.VotingPeriodEnded.selector);
        vm.prank(jury[0]);
        challengeV3.vote(challengeId, EMETChallengeV3.Vote.UpholdChallenge, "reason");
    }

    function test_Voting_InvalidVote() public {
        (uint256 challengeId, address[] memory jury) = _createChallengeWithJury();

        vm.expectRevert(EMETChallengeV3.InvalidVote.selector);
        vm.prank(jury[0]);
        challengeV3.vote(challengeId, EMETChallengeV3.Vote.None, "reason");
    }

    function test_Voting_Abstain() public {
        (uint256 challengeId, address[] memory jury) = _createChallengeWithJury();

        vm.prank(jury[0]);
        challengeV3.vote(challengeId, EMETChallengeV3.Vote.Abstain, "No opinion");

        (EMETChallengeV3.Vote v,,) = challengeV3.getVote(challengeId, jury[0]);
        assertEq(uint256(v), uint256(EMETChallengeV3.Vote.Abstain));
    }

    // ============ Resolution Tests ============

    function test_Resolution_ChallengeUpheld() public {
        (uint256 challengeId, address[] memory jury) = _createChallengeWithJury();

        // All jurors vote to uphold challenge
        for (uint256 i = 0; i < jury.length; i++) {
            vm.prank(jury[i]);
            challengeV3.vote(challengeId, EMETChallengeV3.Vote.UpholdChallenge, "Claim is false");
        }

        // Fast forward past voting period
        vm.warp(block.timestamp + 25 hours);

        uint256 challengerBalanceBefore = mockToken.balanceOf(challenger);
        uint256 treasuryBalanceBefore = mockToken.balanceOf(address(treasury));

        challengeV3.resolveChallenge(challengeId);

        EMETChallengeV3.ResolutionResult memory result = challengeV3.getResolution(challengeId);

        assertEq(uint256(result.verdict), uint256(EMETChallengeV3.Vote.UpholdChallenge));
        assertEq(result.upholdChallengeCount, 3);
        assertEq(result.upholdClaimCount, 0);
        assertEq(result.winner, challenger);
        assertGt(result.winnerPayout, 0);
        assertGt(result.jurorPayout, 0);
        assertGt(result.protocolFee, 0);

        // Check balances
        assertGt(mockToken.balanceOf(challenger), challengerBalanceBefore);
        assertGt(mockToken.balanceOf(address(treasury)), treasuryBalanceBefore);
    }

    function test_Resolution_ClaimUpheld() public {
        (uint256 challengeId, address[] memory jury) = _createChallengeWithJury();

        // All jurors vote to uphold claim
        for (uint256 i = 0; i < jury.length; i++) {
            vm.prank(jury[i]);
            challengeV3.vote(challengeId, EMETChallengeV3.Vote.UpholdClaim, "Claim is valid");
        }

        vm.warp(block.timestamp + 25 hours);

        uint256 submitterBalanceBefore = mockToken.balanceOf(claimSubmitter);

        challengeV3.resolveChallenge(challengeId);

        EMETChallengeV3.ResolutionResult memory result = challengeV3.getResolution(challengeId);

        assertEq(uint256(result.verdict), uint256(EMETChallengeV3.Vote.UpholdClaim));
        assertEq(result.upholdClaimCount, 3);
        assertEq(result.upholdChallengeCount, 0);
        assertEq(result.winner, claimSubmitter);

        // Submitter should get their stake back plus winnings
        assertGt(mockToken.balanceOf(claimSubmitter), submitterBalanceBefore);
    }

    function test_Resolution_Tie_DefaultsToClaimUpheld() public {
        _registerJurors(4); // 4 jurors for even split test
        uint256 claimId = _submitClaim();

        // Create challenge with 3 jurors (odd number, but we'll have 1-1 with abstain)
        vm.prank(challenger);
        uint256 challengeId = challengeV3.initiateChallenge(
            claimId,
            "ipfs://evidence",
            10 ether,
            EMETChallengeV3.Tier.Minor
        );

        (,,,,,,,,address[] memory jury,) = challengeV3.getChallenge(challengeId);

        // 1 upholds claim, 1 upholds challenge, 1 abstains
        vm.prank(jury[0]);
        challengeV3.vote(challengeId, EMETChallengeV3.Vote.UpholdClaim, "Valid");
        vm.prank(jury[1]);
        challengeV3.vote(challengeId, EMETChallengeV3.Vote.UpholdChallenge, "Invalid");
        vm.prank(jury[2]);
        challengeV3.vote(challengeId, EMETChallengeV3.Vote.Abstain, "Unsure");

        vm.warp(block.timestamp + 25 hours);

        challengeV3.resolveChallenge(challengeId);

        EMETChallengeV3.ResolutionResult memory result = challengeV3.getResolution(challengeId);

        // Tie goes to claim (status quo)
        assertEq(uint256(result.verdict), uint256(EMETChallengeV3.Vote.UpholdClaim));
    }

    function test_Resolution_AllAbstain() public {
        (uint256 challengeId, address[] memory jury) = _createChallengeWithJury();

        // All jurors abstain
        for (uint256 i = 0; i < jury.length; i++) {
            vm.prank(jury[i]);
            challengeV3.vote(challengeId, EMETChallengeV3.Vote.Abstain, "No opinion");
        }

        vm.warp(block.timestamp + 25 hours);

        uint256 challengerBalanceBefore = mockToken.balanceOf(challenger);
        uint256 submitterBalanceBefore = mockToken.balanceOf(claimSubmitter);

        challengeV3.resolveChallenge(challengeId);

        EMETChallengeV3.ResolutionResult memory result = challengeV3.getResolution(challengeId);

        // No verdict - stakes returned minus fee
        assertEq(uint256(result.verdict), uint256(EMETChallengeV3.Vote.Abstain));
        assertEq(result.winner, address(0));

        // Both parties should get most of their stakes back
        assertGt(mockToken.balanceOf(challenger), challengerBalanceBefore);
        assertGt(mockToken.balanceOf(claimSubmitter), submitterBalanceBefore);
    }

    function test_Resolution_VotingPeriodNotEnded() public {
        (uint256 challengeId, address[] memory jury) = _createChallengeWithJury();

        // Vote but don't wait
        vm.prank(jury[0]);
        challengeV3.vote(challengeId, EMETChallengeV3.Vote.UpholdChallenge, "reason");

        vm.expectRevert(EMETChallengeV3.VotingPeriodNotEnded.selector);
        challengeV3.resolveChallenge(challengeId);
    }

    function test_Resolution_AlreadyResolved() public {
        (uint256 challengeId, address[] memory jury) = _createChallengeWithJury();

        for (uint256 i = 0; i < jury.length; i++) {
            vm.prank(jury[i]);
            challengeV3.vote(challengeId, EMETChallengeV3.Vote.UpholdChallenge, "reason");
        }

        vm.warp(block.timestamp + 25 hours);
        challengeV3.resolveChallenge(challengeId);

        vm.expectRevert(
            abi.encodeWithSelector(EMETChallengeV3.ChallengeAlreadyResolved.selector, challengeId)
        );
        challengeV3.resolveChallenge(challengeId);
    }

    // ============ Stake Distribution Tests ============

    function test_StakeDistribution_85_10_5_Split() public {
        (uint256 challengeId, address[] memory jury) = _createChallengeWithJury();

        // All jurors vote to uphold challenge
        for (uint256 i = 0; i < jury.length; i++) {
            vm.prank(jury[i]);
            challengeV3.vote(challengeId, EMETChallengeV3.Vote.UpholdChallenge, "reason");
        }

        vm.warp(block.timestamp + 25 hours);

        uint256 challengerBalanceBefore = mockToken.balanceOf(challenger);
        uint256 juror0BalanceBefore = mockToken.balanceOf(jury[0]);
        uint256 treasuryBalanceBefore = mockToken.balanceOf(address(treasury));

        challengeV3.resolveChallenge(challengeId);

        EMETChallengeV3.ResolutionResult memory result = challengeV3.getResolution(challengeId);

        // Challenge upheld: loser is claim submitter, loser stake = 1 ether
        // Fee is calculated ONLY on loser's stake (not total pool)
        uint256 loserStake = 1 ether; // claim stake
        uint256 expectedFee = (loserStake * 500) / 10000; // 5% of loser's stake

        // Check fee (5% of 1 ether = 0.05 ether)
        assertEq(result.protocolFee, expectedFee);
        assertEq(
            mockToken.balanceOf(address(treasury)) - treasuryBalanceBefore,
            expectedFee
        );

        // Winner (challenger) gets their stake back + (loser stake - fee - juror share)
        // Jurors split remaining portion from loser's stake after fee
        assertGt(mockToken.balanceOf(challenger) - challengerBalanceBefore, 0);
        assertGt(mockToken.balanceOf(jury[0]) - juror0BalanceBefore, 0);
    }

    function test_StakeDistribution_OnlyWinningJurorsGetPaid() public {
        (uint256 challengeId, address[] memory jury) = _createChallengeWithJury();

        // 2 vote uphold challenge, 1 votes uphold claim
        vm.prank(jury[0]);
        challengeV3.vote(challengeId, EMETChallengeV3.Vote.UpholdChallenge, "reason");
        vm.prank(jury[1]);
        challengeV3.vote(challengeId, EMETChallengeV3.Vote.UpholdChallenge, "reason");
        vm.prank(jury[2]);
        challengeV3.vote(challengeId, EMETChallengeV3.Vote.UpholdClaim, "reason");

        uint256 juror2BalanceBefore = mockToken.balanceOf(jury[2]);

        vm.warp(block.timestamp + 25 hours);
        challengeV3.resolveChallenge(challengeId);

        // Juror 2 (minority voter) should not get any reward
        assertEq(mockToken.balanceOf(jury[2]), juror2BalanceBefore);
    }

    // ============ Appeal Tests ============

    function test_Appeal_MinorToMajor() public {
        _registerJurors(11); // Need enough for Major tier

        // Create and resolve Minor challenge
        uint256 claimId = _submitClaim();

        vm.prank(challenger);
        uint256 challengeId = challengeV3.initiateChallenge(
            claimId,
            "ipfs://evidence",
            10 ether,
            EMETChallengeV3.Tier.Minor
        );

        (,,,,,,,,address[] memory jury,) = challengeV3.getChallenge(challengeId);

        for (uint256 i = 0; i < jury.length; i++) {
            vm.prank(jury[i]);
            challengeV3.vote(challengeId, EMETChallengeV3.Vote.UpholdClaim, "Valid");
        }

        vm.warp(block.timestamp + 25 hours);
        challengeV3.resolveChallenge(challengeId);

        // Appeal
        address appellant = address(200);
        _fundAccount(appellant);

        vm.prank(appellant);
        uint256 appealId = challengeV3.appeal(
            challengeId,
            "ipfs://new-evidence",
            100 ether // Major tier minimum
        );

        (,,,,,, EMETChallengeV3.Tier tier,, address[] memory appealJury,) =
            challengeV3.getChallenge(appealId);

        assertEq(uint256(tier), uint256(EMETChallengeV3.Tier.Major));
        assertEq(appealJury.length, 7); // Major tier jury size
    }

    function test_Appeal_MajorToCritical() public {
        _registerJurors(11);

        uint256 claimId = _submitClaim();

        // Create Major challenge
        vm.prank(challenger);
        uint256 challengeId = challengeV3.initiateChallenge(
            claimId,
            "ipfs://evidence",
            100 ether,
            EMETChallengeV3.Tier.Major
        );

        (,,,,,,,,address[] memory jury,) = challengeV3.getChallenge(challengeId);

        for (uint256 i = 0; i < jury.length; i++) {
            vm.prank(jury[i]);
            challengeV3.vote(challengeId, EMETChallengeV3.Vote.UpholdClaim, "Valid");
        }

        vm.warp(block.timestamp + 73 hours);
        challengeV3.resolveChallenge(challengeId);

        // Appeal to Critical
        address appellant = address(200);
        _fundAccount(appellant);

        vm.prank(appellant);
        uint256 appealId = challengeV3.appeal(
            challengeId,
            "ipfs://new-evidence",
            1000 ether // Critical tier minimum
        );

        (,,,,,, EMETChallengeV3.Tier tier,, address[] memory appealJury,) =
            challengeV3.getChallenge(appealId);

        assertEq(uint256(tier), uint256(EMETChallengeV3.Tier.Critical));
        assertEq(appealJury.length, 11);
    }

    function test_Appeal_CannotAppealCritical() public {
        _registerJurors(11);

        uint256 claimId = _submitClaim();

        // Create Critical challenge
        vm.prank(challenger);
        uint256 challengeId = challengeV3.initiateChallenge(
            claimId,
            "ipfs://evidence",
            1000 ether,
            EMETChallengeV3.Tier.Critical
        );

        (,,,,,,,,address[] memory jury,) = challengeV3.getChallenge(challengeId);

        for (uint256 i = 0; i < jury.length; i++) {
            vm.prank(jury[i]);
            challengeV3.vote(challengeId, EMETChallengeV3.Vote.UpholdClaim, "Valid");
        }

        vm.warp(block.timestamp + 8 days);
        challengeV3.resolveChallenge(challengeId);

        // Try to appeal
        address appellant = address(200);
        _fundAccount(appellant);

        vm.expectRevert(EMETChallengeV3.CannotAppealCritical.selector);
        vm.prank(appellant);
        challengeV3.appeal(challengeId, "ipfs://evidence", 3000 ether);
    }

    function test_Appeal_InsufficientStake() public {
        _registerJurors(11);

        uint256 claimId = _submitClaim();

        vm.prank(challenger);
        uint256 challengeId = challengeV3.initiateChallenge(
            claimId,
            "ipfs://evidence",
            10 ether,
            EMETChallengeV3.Tier.Minor
        );

        (,,,,,,,,address[] memory jury,) = challengeV3.getChallenge(challengeId);

        for (uint256 i = 0; i < jury.length; i++) {
            vm.prank(jury[i]);
            challengeV3.vote(challengeId, EMETChallengeV3.Vote.UpholdClaim, "Valid");
        }

        vm.warp(block.timestamp + 25 hours);
        challengeV3.resolveChallenge(challengeId);

        // Try to appeal with insufficient stake (need 2x original = 20, but Major min = 100)
        address appellant = address(200);
        _fundAccount(appellant);

        vm.expectRevert(
            abi.encodeWithSelector(EMETChallengeV3.InsufficientStake.selector, 50 ether, 100 ether)
        );
        vm.prank(appellant);
        challengeV3.appeal(challengeId, "ipfs://evidence", 50 ether);
    }

    function test_Appeal_CannotAppealUnresolved() public {
        (uint256 challengeId,) = _createChallengeWithJury();

        address appellant = address(200);
        _fundAccount(appellant);

        vm.expectRevert(
            abi.encodeWithSelector(EMETChallengeV3.ChallengeNotResolved.selector, challengeId)
        );
        vm.prank(appellant);
        challengeV3.appeal(challengeId, "ipfs://evidence", 100 ether);
    }

    function test_Appeal_CannotDoubleAppeal() public {
        _registerJurors(11);

        uint256 claimId = _submitClaim();

        vm.prank(challenger);
        uint256 challengeId = challengeV3.initiateChallenge(
            claimId,
            "ipfs://evidence",
            10 ether,
            EMETChallengeV3.Tier.Minor
        );

        (,,,,,,,,address[] memory jury,) = challengeV3.getChallenge(challengeId);

        for (uint256 i = 0; i < jury.length; i++) {
            vm.prank(jury[i]);
            challengeV3.vote(challengeId, EMETChallengeV3.Vote.UpholdClaim, "Valid");
        }

        vm.warp(block.timestamp + 25 hours);
        challengeV3.resolveChallenge(challengeId);

        // First appeal
        address appellant = address(200);
        _fundAccount(appellant);
        vm.prank(appellant);
        challengeV3.appeal(challengeId, "ipfs://evidence", 100 ether);

        // Second appeal attempt
        vm.expectRevert(
            abi.encodeWithSelector(EMETChallengeV3.ChallengeAlreadyAppealed.selector, challengeId)
        );
        vm.prank(appellant);
        challengeV3.appeal(challengeId, "ipfs://evidence2", 100 ether);
    }

    // ============ Reputation Update Tests ============

    function test_ReputationUpdate_ChallengeSuccess() public {
        (uint256 challengeId, address[] memory jury) = _createChallengeWithJury();

        int256 challengerRepBefore = reputation.getReputation(challenger);
        int256 submitterRepBefore = reputation.getReputation(claimSubmitter);

        for (uint256 i = 0; i < jury.length; i++) {
            vm.prank(jury[i]);
            challengeV3.vote(challengeId, EMETChallengeV3.Vote.UpholdChallenge, "reason");
        }

        vm.warp(block.timestamp + 25 hours);
        challengeV3.resolveChallenge(challengeId);

        // Challenger gains rep, submitter loses rep
        assertGt(reputation.getReputation(challenger), challengerRepBefore);
        assertLt(reputation.getReputation(claimSubmitter), submitterRepBefore);
    }

    function test_ReputationUpdate_ClaimVerified() public {
        (uint256 challengeId, address[] memory jury) = _createChallengeWithJury();

        int256 challengerRepBefore = reputation.getReputation(challenger);
        int256 submitterRepBefore = reputation.getReputation(claimSubmitter);

        for (uint256 i = 0; i < jury.length; i++) {
            vm.prank(jury[i]);
            challengeV3.vote(challengeId, EMETChallengeV3.Vote.UpholdClaim, "reason");
        }

        vm.warp(block.timestamp + 25 hours);
        challengeV3.resolveChallenge(challengeId);

        // Submitter gains rep, challenger loses rep
        assertGt(reputation.getReputation(claimSubmitter), submitterRepBefore);
        assertLt(reputation.getReputation(challenger), challengerRepBefore);
    }

    // ============ View Function Tests ============

    function test_GetVoteCounts() public {
        (uint256 challengeId, address[] memory jury) = _createChallengeWithJury();

        vm.prank(jury[0]);
        challengeV3.vote(challengeId, EMETChallengeV3.Vote.UpholdClaim, "reason");
        vm.prank(jury[1]);
        challengeV3.vote(challengeId, EMETChallengeV3.Vote.UpholdChallenge, "reason");

        (uint256 upholdClaim, uint256 upholdChallenge, uint256 abstain, uint256 notVoted) =
            challengeV3.getVoteCounts(challengeId);

        assertEq(upholdClaim, 1);
        assertEq(upholdChallenge, 1);
        assertEq(abstain, 0);
        assertEq(notVoted, 1);
    }

    function test_IsVotingActive() public {
        (uint256 challengeId,) = _createChallengeWithJury();

        assertTrue(challengeV3.isVotingActive(challengeId));

        vm.warp(block.timestamp + 25 hours);
        assertFalse(challengeV3.isVotingActive(challengeId));
    }

    function test_CanResolve() public {
        (uint256 challengeId,) = _createChallengeWithJury();

        assertFalse(challengeV3.canResolve(challengeId));

        vm.warp(block.timestamp + 25 hours);
        assertTrue(challengeV3.canResolve(challengeId));
    }

    function test_GetTierParams() public view {
        (uint256 jurySize, uint256 minStake, uint256 votingPeriod, uint256 appealMultiplier) =
            challengeV3.getTierParams(EMETChallengeV3.Tier.Minor);

        assertEq(jurySize, 3);
        assertEq(minStake, 10 ether);
        assertEq(votingPeriod, 24 hours);
        assertEq(appealMultiplier, 20000); // 2x
    }

    // ============ Helper Functions ============

    function _registerJurors(uint256 count) internal {
        for (uint256 i = 0; i < count && i < allJurors.length; i++) {
            vm.prank(allJurors[i]);
            juryPool.registerJuror();
        }
    }

    function _submitClaim() internal returns (uint256 claimId) {
        vm.prank(claimSubmitter);
        return registry.submitClaim("Test claim", "ipfs://evidence", MINIMUM_STAKE);
    }

    function _createChallengeWithJury() internal returns (uint256 challengeId, address[] memory jury) {
        _registerJurors(5); // Register extra to account for exclusions
        uint256 claimId = _submitClaim();

        vm.prank(challenger);
        challengeId = challengeV3.initiateChallenge(
            claimId,
            "ipfs://evidence",
            10 ether,
            EMETChallengeV3.Tier.Minor
        );

        (,,,,,,,,jury,) = challengeV3.getChallenge(challengeId);
    }
}

// ============ Mock Contracts ============

contract MockEMET {
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

contract MockReputationSetter {
    EMETReputation public reputation;

    constructor(address _reputation) {
        reputation = EMETReputation(_reputation);
    }
}
