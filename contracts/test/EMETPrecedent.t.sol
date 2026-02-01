// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, console} from "forge-std/Test.sol";
import {EMETPrecedent} from "../src/EMETPrecedent.sol";

/// @title EMETPrecedent Tests - Precedent registry functionality
contract EMETPrecedentTest is Test {
    EMETPrecedent public precedent;

    address public deployer = address(1);
    address public recorder = address(2);
    address public unauthorized = address(3);

    function setUp() public {
        vm.startPrank(deployer);
        precedent = new EMETPrecedent();
        precedent.setRecorder(recorder);
        vm.stopPrank();
    }

    // ============ Setup Tests ============

    function test_Constructor_SetsDeployer() public view {
        assertEq(precedent.deployer(), deployer);
    }

    function test_SetRecorder_Success() public view {
        assertEq(precedent.recorder(), recorder);
    }

    function test_SetRecorder_RevertIfNotDeployer() public {
        EMETPrecedent newPrecedent = new EMETPrecedent();
        vm.prank(unauthorized);
        vm.expectRevert(EMETPrecedent.OnlyDeployer.selector);
        newPrecedent.setRecorder(recorder);
    }

    function test_SetRecorder_RevertIfAlreadySet() public {
        vm.prank(deployer);
        vm.expectRevert(EMETPrecedent.RecorderAlreadySet.selector);
        precedent.setRecorder(address(4));
    }

    function test_SetRecorder_RevertIfZeroAddress() public {
        EMETPrecedent newPrecedent = new EMETPrecedent();
        vm.prank(address(this));
        vm.expectRevert(EMETPrecedent.ZeroAddress.selector);
        newPrecedent.setRecorder(address(0));
    }

    // ============ Recording Tests ============

    function test_RecordPrecedent_Success() public {
        string[] memory reasonings = new string[](3);
        reasonings[0] = "Evidence is solid";
        reasonings[1] = "Claim matches facts";
        reasonings[2] = "Abstaining due to uncertainty";

        vm.prank(recorder);
        uint256 id = precedent.recordPrecedent(
            1, // challengeId
            10, // claimId
            keccak256("The earth is round"),
            "Multiple satellite images prove curvature",
            EMETPrecedent.Verdict.UpholdClaim,
            EMETPrecedent.Tier.Major,
            5, // upholdClaimVotes
            2, // upholdChallengeVotes
            1, // abstainVotes
            reasonings
        );

        assertEq(id, 0);
        assertEq(precedent.precedentCount(), 1);

        EMETPrecedent.Precedent memory p = precedent.getPrecedent(0);
        assertEq(p.challengeId, 1);
        assertEq(p.claimId, 10);
        assertEq(p.claimHash, keccak256("The earth is round"));
        assertEq(p.evidence, "Multiple satellite images prove curvature");
        assertEq(uint8(p.verdict), uint8(EMETPrecedent.Verdict.UpholdClaim));
        assertEq(uint8(p.tier), uint8(EMETPrecedent.Tier.Major));
        assertEq(p.upholdClaimVotes, 5);
        assertEq(p.upholdChallengeVotes, 2);
        assertEq(p.abstainVotes, 1);
        assertEq(p.jurorReasonings.length, 3);
        assertEq(p.jurorReasonings[0], "Evidence is solid");
    }

    function test_RecordPrecedent_RevertIfNotRecorder() public {
        string[] memory reasonings = new string[](0);

        vm.prank(unauthorized);
        vm.expectRevert(EMETPrecedent.OnlyRecorder.selector);
        precedent.recordPrecedent(
            1, 10, bytes32(0), "", EMETPrecedent.Verdict.UpholdClaim,
            EMETPrecedent.Tier.Minor, 3, 0, 0, reasonings
        );
    }

    function test_RecordPrecedent_RevertIfInvalidVerdict() public {
        string[] memory reasonings = new string[](0);

        vm.prank(recorder);
        vm.expectRevert(EMETPrecedent.InvalidVerdict.selector);
        precedent.recordPrecedent(
            1, 10, bytes32(0), "", EMETPrecedent.Verdict.None,
            EMETPrecedent.Tier.Minor, 0, 0, 3, reasonings
        );
    }

    function test_RecordPrecedent_EmitsEvent() public {
        string[] memory reasonings = new string[](0);
        bytes32 claimHash = keccak256("Test claim");

        vm.prank(recorder);
        vm.expectEmit(true, true, true, true);
        emit EMETPrecedent.PrecedentRecorded(
            0, 1, 10, claimHash,
            EMETPrecedent.Verdict.UpholdChallenge,
            EMETPrecedent.Tier.Critical,
            block.timestamp
        );

        precedent.recordPrecedent(
            1, 10, claimHash, "Evidence",
            EMETPrecedent.Verdict.UpholdChallenge,
            EMETPrecedent.Tier.Critical,
            2, 9, 0, reasonings
        );
    }

    // ============ Query by Claim ID Tests ============

    function test_GetPrecedentsForClaim_ReturnsPrecedents() public {
        string[] memory reasonings = new string[](1);
        reasonings[0] = "Valid";

        // Record two precedents for same claim
        vm.startPrank(recorder);
        precedent.recordPrecedent(
            1, 100, keccak256("Claim A"), "Evidence 1",
            EMETPrecedent.Verdict.UpholdClaim, EMETPrecedent.Tier.Minor,
            3, 0, 0, reasonings
        );
        precedent.recordPrecedent(
            2, 100, keccak256("Claim A"), "Evidence 2",
            EMETPrecedent.Verdict.UpholdChallenge, EMETPrecedent.Tier.Major,
            2, 5, 0, reasonings
        );
        // Different claim
        precedent.recordPrecedent(
            3, 200, keccak256("Claim B"), "Evidence 3",
            EMETPrecedent.Verdict.UpholdClaim, EMETPrecedent.Tier.Minor,
            3, 0, 0, reasonings
        );
        vm.stopPrank();

        EMETPrecedent.Precedent[] memory results = precedent.getPrecedentsForClaim(100);
        assertEq(results.length, 2);
        assertEq(results[0].challengeId, 1);
        assertEq(results[1].challengeId, 2);
    }

    function test_GetPrecedentsForClaim_EmptyIfNone() public view {
        EMETPrecedent.Precedent[] memory results = precedent.getPrecedentsForClaim(999);
        assertEq(results.length, 0);
    }

    function test_GetPrecedentIdsForClaim() public {
        string[] memory reasonings = new string[](0);

        vm.startPrank(recorder);
        precedent.recordPrecedent(
            1, 50, bytes32(0), "", EMETPrecedent.Verdict.UpholdClaim,
            EMETPrecedent.Tier.Minor, 3, 0, 0, reasonings
        );
        precedent.recordPrecedent(
            2, 50, bytes32(0), "", EMETPrecedent.Verdict.UpholdChallenge,
            EMETPrecedent.Tier.Minor, 0, 3, 0, reasonings
        );
        vm.stopPrank();

        uint256[] memory ids = precedent.getPrecedentIdsForClaim(50);
        assertEq(ids.length, 2);
        assertEq(ids[0], 0);
        assertEq(ids[1], 1);
    }

    // ============ Query by Hash Tests ============

    function test_GetPrecedentsByHash_ReturnsSimilarClaims() public {
        string[] memory reasonings = new string[](0);
        bytes32 hash1 = keccak256("Sky is blue");
        bytes32 hash2 = keccak256("Water is wet");

        vm.startPrank(recorder);
        // Same hash, different claims
        precedent.recordPrecedent(
            1, 10, hash1, "Photo evidence",
            EMETPrecedent.Verdict.UpholdClaim, EMETPrecedent.Tier.Minor,
            3, 0, 0, reasonings
        );
        precedent.recordPrecedent(
            2, 20, hash1, "Video evidence",
            EMETPrecedent.Verdict.UpholdClaim, EMETPrecedent.Tier.Major,
            7, 0, 0, reasonings
        );
        // Different hash
        precedent.recordPrecedent(
            3, 30, hash2, "Touch test",
            EMETPrecedent.Verdict.UpholdClaim, EMETPrecedent.Tier.Minor,
            3, 0, 0, reasonings
        );
        vm.stopPrank();

        EMETPrecedent.Precedent[] memory results = precedent.getPrecedentsByHash(hash1);
        assertEq(results.length, 2);
        assertEq(results[0].claimId, 10);
        assertEq(results[1].claimId, 20);

        // Different hash should have 1 result
        EMETPrecedent.Precedent[] memory results2 = precedent.getPrecedentsByHash(hash2);
        assertEq(results2.length, 1);
    }

    function test_GetPrecedentIdsByHash() public {
        string[] memory reasonings = new string[](0);
        bytes32 hash = keccak256("Test hash");

        vm.startPrank(recorder);
        precedent.recordPrecedent(
            1, 10, hash, "", EMETPrecedent.Verdict.UpholdClaim,
            EMETPrecedent.Tier.Minor, 3, 0, 0, reasonings
        );
        precedent.recordPrecedent(
            2, 20, hash, "", EMETPrecedent.Verdict.UpholdClaim,
            EMETPrecedent.Tier.Minor, 3, 0, 0, reasonings
        );
        vm.stopPrank();

        uint256[] memory ids = precedent.getPrecedentIdsByHash(hash);
        assertEq(ids.length, 2);
    }

    // ============ Single Precedent Queries ============

    function test_GetPrecedent_Success() public {
        string[] memory reasonings = new string[](2);
        reasonings[0] = "First reason";
        reasonings[1] = "Second reason";

        vm.prank(recorder);
        precedent.recordPrecedent(
            5, 50, keccak256("Test"), "Test evidence",
            EMETPrecedent.Verdict.UpholdChallenge, EMETPrecedent.Tier.Critical,
            1, 10, 0, reasonings
        );

        EMETPrecedent.Precedent memory p = precedent.getPrecedent(0);
        assertEq(p.challengeId, 5);
        assertEq(p.claimId, 50);
        assertEq(uint8(p.verdict), uint8(EMETPrecedent.Verdict.UpholdChallenge));
        assertEq(p.jurorReasonings.length, 2);
    }

    function test_GetPrecedent_RevertIfNotExists() public {
        vm.expectRevert(abi.encodeWithSelector(EMETPrecedent.PrecedentDoesNotExist.selector, 0));
        precedent.getPrecedent(0);
    }

    // ============ Count Queries ============

    function test_GetPrecedentCountForClaim() public {
        string[] memory reasonings = new string[](0);

        vm.startPrank(recorder);
        precedent.recordPrecedent(
            1, 100, bytes32(0), "", EMETPrecedent.Verdict.UpholdClaim,
            EMETPrecedent.Tier.Minor, 3, 0, 0, reasonings
        );
        precedent.recordPrecedent(
            2, 100, bytes32(0), "", EMETPrecedent.Verdict.UpholdChallenge,
            EMETPrecedent.Tier.Minor, 0, 3, 0, reasonings
        );
        vm.stopPrank();

        assertEq(precedent.getPrecedentCountForClaim(100), 2);
        assertEq(precedent.getPrecedentCountForClaim(999), 0);
    }

    function test_GetPrecedentCountByHash() public {
        string[] memory reasonings = new string[](0);
        bytes32 hash = keccak256("Common claim");

        vm.startPrank(recorder);
        for (uint256 i = 0; i < 5; i++) {
            precedent.recordPrecedent(
                i, i * 10, hash, "", EMETPrecedent.Verdict.UpholdClaim,
                EMETPrecedent.Tier.Minor, 3, 0, 0, reasonings
            );
        }
        vm.stopPrank();

        assertEq(precedent.getPrecedentCountByHash(hash), 5);
    }

    // ============ Challenge Lookup ============

    function test_HasPrecedentForChallenge_ReturnsTrue() public {
        string[] memory reasonings = new string[](0);

        vm.prank(recorder);
        precedent.recordPrecedent(
            42, 100, bytes32(0), "", EMETPrecedent.Verdict.UpholdClaim,
            EMETPrecedent.Tier.Minor, 3, 0, 0, reasonings
        );

        (bool exists, uint256 id) = precedent.hasPrecedentForChallenge(42);
        assertTrue(exists);
        assertEq(id, 0);
    }

    function test_HasPrecedentForChallenge_ReturnsFalse() public view {
        (bool exists, uint256 id) = precedent.hasPrecedentForChallenge(999);
        assertFalse(exists);
        assertEq(id, 0);
    }

    // ============ Statistics ============

    function test_GetStats() public {
        string[] memory reasonings = new string[](0);

        vm.startPrank(recorder);
        // 3 upheld claims
        for (uint256 i = 0; i < 3; i++) {
            precedent.recordPrecedent(
                i, i, bytes32(0), "", EMETPrecedent.Verdict.UpholdClaim,
                EMETPrecedent.Tier.Minor, 3, 0, 0, reasonings
            );
        }
        // 2 upheld challenges
        for (uint256 i = 3; i < 5; i++) {
            precedent.recordPrecedent(
                i, i, bytes32(0), "", EMETPrecedent.Verdict.UpholdChallenge,
                EMETPrecedent.Tier.Minor, 0, 3, 0, reasonings
            );
        }
        // 1 abstain
        precedent.recordPrecedent(
            5, 5, bytes32(0), "", EMETPrecedent.Verdict.Abstain,
            EMETPrecedent.Tier.Minor, 0, 0, 3, reasonings
        );
        vm.stopPrank();

        (uint256 total, uint256 upheldClaims, uint256 upheldChallenges) = precedent.getStats();
        assertEq(total, 6);
        assertEq(upheldClaims, 3);
        assertEq(upheldChallenges, 2);
    }

    // ============ Edge Cases ============

    function test_MultiplePrecedentsSameChallenge() public {
        // This shouldn't happen in practice (each challenge resolves once)
        // but the contract allows it - could add a guard if needed
        string[] memory reasonings = new string[](0);

        vm.startPrank(recorder);
        precedent.recordPrecedent(
            1, 10, bytes32(0), "", EMETPrecedent.Verdict.UpholdClaim,
            EMETPrecedent.Tier.Minor, 3, 0, 0, reasonings
        );
        precedent.recordPrecedent(
            1, 10, bytes32(0), "", EMETPrecedent.Verdict.UpholdChallenge,
            EMETPrecedent.Tier.Minor, 0, 3, 0, reasonings
        );
        vm.stopPrank();

        assertEq(precedent.precedentCount(), 2);
    }

    function test_EmptyJurorReasonings() public {
        string[] memory reasonings = new string[](0);

        vm.prank(recorder);
        precedent.recordPrecedent(
            1, 10, bytes32(0), "Evidence",
            EMETPrecedent.Verdict.UpholdClaim, EMETPrecedent.Tier.Minor,
            3, 0, 0, reasonings
        );

        EMETPrecedent.Precedent memory p = precedent.getPrecedent(0);
        assertEq(p.jurorReasonings.length, 0);
    }

    function test_LongEvidence() public {
        string[] memory reasonings = new string[](0);
        string memory longEvidence = "This is a very long piece of evidence that goes on and on and contains detailed analysis of the claim in question. It includes references to multiple sources, statistical data, expert opinions, and comprehensive reasoning that supports or refutes the claim being challenged.";

        vm.prank(recorder);
        precedent.recordPrecedent(
            1, 10, bytes32(0), longEvidence,
            EMETPrecedent.Verdict.UpholdClaim, EMETPrecedent.Tier.Critical,
            10, 1, 0, reasonings
        );

        EMETPrecedent.Precedent memory p = precedent.getPrecedent(0);
        assertEq(p.evidence, longEvidence);
    }
}
