// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "forge-std/Test.sol";
import "../src/EMETScorecard.sol";
import "../src/EMETTrustGate.sol";
import "../src/EMETAgentProfile.sol";
import "../src/EMETReputation.sol";

/// @title EMETScorecardTest — Comprehensive tests for EMETScorecard aggregator
/// @notice Tests tier computation, trust score formula, policy checks, peek/score/check helpers,
///         events, constructor validation, edge cases, and multi-agent batch patterns.
contract EMETScorecardTest is Test {

    EMETAgentProfile internal profile;
    EMETReputation   internal reputation;
    EMETTrustGate    internal gate;
    EMETScorecard    internal scorecard;

    address internal updater = address(0xAB01);

    // Test agents
    address internal agentPlatinum = address(0x1111); // 20+ claims, 90%+ accuracy, rep 100+
    address internal agentGold     = address(0x2222); // 10+ claims, 75%+ accuracy, rep 50+
    address internal agentSilver   = address(0x3333); // 5+ claims, 60%+ accuracy, rep 0+
    address internal agentBronze   = address(0x4444); // 3+ claims, 50%+ accuracy, rep >= -10
    address internal agentUnrated  = address(0x5555); // < 3 claims
    address internal agentSlashed  = address(0x6666); // below bronze thresholds
    address internal agentNegRep   = address(0x7777); // heavily negative reputation

    // ============ Setup ============

    function setUp() public {
        profile    = new EMETAgentProfile();
        reputation = new EMETReputation();
        gate       = new EMETTrustGate(address(profile), address(reputation));
        scorecard  = new EMETScorecard(address(profile), address(reputation), address(gate));

        profile.setUpdater(updater);
        reputation.setUpdater(updater);

        _seedPlatinum();
        _seedGold();
        _seedSilver();
        _seedBronze();
        _seedUnrated();
        _seedSlashed();
        _seedNegRep();
    }

    // ============ Seed helpers ============

    /// @dev Platinum: 22 correct, 1 slashed → ~95.7% accuracy, rep +190
    function _seedPlatinum() internal {
        vm.startPrank(updater);
        for (uint256 i = 0; i < 22; i++) {
            profile.recordCorrectClaim(agentPlatinum, 0.01 ether);
            reputation.recordClaimVerified(agentPlatinum);
        }
        profile.recordSlashedClaim(agentPlatinum, 0.01 ether);
        reputation.recordClaimRejected(agentPlatinum);
        vm.stopPrank();
    }

    /// @dev Gold: 12 correct, 2 slashed → ~85.7% accuracy, rep +100
    function _seedGold() internal {
        vm.startPrank(updater);
        for (uint256 i = 0; i < 12; i++) {
            profile.recordCorrectClaim(agentGold, 0.008 ether);
            reputation.recordClaimVerified(agentGold);
        }
        for (uint256 i = 0; i < 2; i++) {
            profile.recordSlashedClaim(agentGold, 0.008 ether);
            reputation.recordClaimRejected(agentGold);
        }
        vm.stopPrank();
    }

    /// @dev Silver: 6 correct, 2 slashed → 75% accuracy, rep +20
    function _seedSilver() internal {
        vm.startPrank(updater);
        for (uint256 i = 0; i < 6; i++) {
            profile.recordCorrectClaim(agentSilver, 0.005 ether);
            reputation.recordClaimVerified(agentSilver);
        }
        for (uint256 i = 0; i < 2; i++) {
            profile.recordSlashedClaim(agentSilver, 0.005 ether);
            reputation.recordClaimRejected(agentSilver);
        }
        vm.stopPrank();
    }

    /// @dev Bronze: 3 correct, 2 slashed → 60% accuracy, rep -10 (net: 3*10 + 2*(-20) = -10)
    ///      Passes Bronze (claims>=3, accuracy>=50%, rep>=-10) but fails Silver (rep<0).
    function _seedBronze() internal {
        vm.startPrank(updater);
        for (uint256 i = 0; i < 3; i++) {
            profile.recordCorrectClaim(agentBronze, 0.002 ether);
            reputation.recordClaimVerified(agentBronze);
        }
        for (uint256 i = 0; i < 2; i++) {
            profile.recordSlashedClaim(agentBronze, 0.002 ether);
            reputation.recordClaimRejected(agentBronze);
        }
        vm.stopPrank();
    }

    /// @dev Unrated: 2 correct claims only
    function _seedUnrated() internal {
        vm.startPrank(updater);
        profile.recordCorrectClaim(agentUnrated, 0.001 ether);
        reputation.recordClaimVerified(agentUnrated);
        profile.recordCorrectClaim(agentUnrated, 0.001 ether);
        reputation.recordClaimVerified(agentUnrated);
        vm.stopPrank();
    }

    /// @dev Slashed: 3 claims but all slashed → 0% accuracy, falls below bronze
    function _seedSlashed() internal {
        vm.startPrank(updater);
        for (uint256 i = 0; i < 3; i++) {
            profile.recordSlashedClaim(agentSlashed, 0.005 ether);
            reputation.recordClaimRejected(agentSlashed);
        }
        vm.stopPrank();
    }

    /// @dev NegRep: 3 correct but then 5 slashes → deeply negative rep, 37.5% accuracy
    function _seedNegRep() internal {
        vm.startPrank(updater);
        for (uint256 i = 0; i < 3; i++) {
            profile.recordCorrectClaim(agentNegRep, 0.003 ether);
            reputation.recordClaimVerified(agentNegRep);
        }
        for (uint256 i = 0; i < 5; i++) {
            profile.recordSlashedClaim(agentNegRep, 0.003 ether);
            reputation.recordClaimRejected(agentNegRep);
        }
        vm.stopPrank();
    }

    // ============ Constructor validation ============

    function test_Constructor_ZeroAgentProfile_Reverts() public {
        vm.expectRevert("EMETScorecard: zero agentProfile");
        new EMETScorecard(address(0), address(reputation), address(gate));
    }

    function test_Constructor_ZeroReputation_Reverts() public {
        vm.expectRevert("EMETScorecard: zero reputation");
        new EMETScorecard(address(profile), address(0), address(gate));
    }

    function test_Constructor_ZeroTrustGate_Reverts() public {
        vm.expectRevert("EMETScorecard: zero trustGate");
        new EMETScorecard(address(profile), address(reputation), address(0));
    }

    function test_Constructor_StoresAddresses() public view {
        assertEq(address(scorecard.agentProfile()), address(profile));
        assertEq(address(scorecard.reputation()),   address(reputation));
        assertEq(address(scorecard.trustGate()),    address(gate));
    }

    // ============ Tier computation ============

    function test_Tier_Platinum() public view {
        assertEq(uint8(scorecard.tierOf(agentPlatinum)), uint8(EMETScorecard.Tier.PLATINUM));
    }

    function test_Tier_Gold() public view {
        assertEq(uint8(scorecard.tierOf(agentGold)), uint8(EMETScorecard.Tier.GOLD));
    }

    function test_Tier_Silver() public view {
        assertEq(uint8(scorecard.tierOf(agentSilver)), uint8(EMETScorecard.Tier.SILVER));
    }

    function test_Tier_Bronze() public view {
        assertEq(uint8(scorecard.tierOf(agentBronze)), uint8(EMETScorecard.Tier.BRONZE));
    }

    function test_Tier_Unrated_TooFewClaims() public view {
        assertEq(uint8(scorecard.tierOf(agentUnrated)), uint8(EMETScorecard.Tier.UNRATED));
    }

    function test_Tier_Unrated_ZeroHistory() public view {
        address nobody = address(0x9999);
        assertEq(uint8(scorecard.tierOf(nobody)), uint8(EMETScorecard.Tier.UNRATED));
    }

    function test_Tier_Unrated_AllSlashed() public view {
        // agentSlashed: 3 claims, 0% accuracy → fails Bronze min accuracy
        assertEq(uint8(scorecard.tierOf(agentSlashed)), uint8(EMETScorecard.Tier.UNRATED));
    }

    function test_Tier_Unrated_NegativeRepBelowBronze() public view {
        // agentNegRep: 37.5% accuracy → below Bronze min (50%)
        assertEq(uint8(scorecard.tierOf(agentNegRep)), uint8(EMETScorecard.Tier.UNRATED));
    }

    // ============ Trust score: UNRATED = 0 ============

    function test_TrustScore_Unrated_IsZero() public view {
        assertEq(scorecard.trustScoreOf(agentUnrated), 0);
    }

    function test_TrustScore_NoHistory_IsZero() public view {
        assertEq(scorecard.trustScoreOf(address(0xDEAD)), 0);
    }

    function test_TrustScore_AllSlashed_IsZero() public view {
        assertEq(scorecard.trustScoreOf(agentSlashed), 0);
    }

    // ============ Trust score: ordering ============

    function test_TrustScore_Platinum_GreaterThan_Gold() public view {
        assertGt(scorecard.trustScoreOf(agentPlatinum), scorecard.trustScoreOf(agentGold));
    }

    function test_TrustScore_Gold_GreaterThan_Silver() public view {
        assertGt(scorecard.trustScoreOf(agentGold), scorecard.trustScoreOf(agentSilver));
    }

    function test_TrustScore_Silver_GreaterThan_Bronze() public view {
        assertGt(scorecard.trustScoreOf(agentSilver), scorecard.trustScoreOf(agentBronze));
    }

    function test_TrustScore_Bronze_GreaterThan_Zero() public view {
        assertGt(scorecard.trustScoreOf(agentBronze), 0);
    }

    function test_TrustScore_Max_Is_1000() public view {
        // Even platinum shouldn't exceed 1000
        assertLe(scorecard.trustScoreOf(agentPlatinum), 1_000);
    }

    // ============ peek() vs score() ============

    function test_Peek_ReturnsSameAsScore_NoSideEffect() public {
        EMETScorecard.Score memory viaView  = scorecard.peek(agentGold);
        EMETScorecard.Score memory viaTx    = scorecard.score(agentGold);

        assertEq(viaView.accuracyBps,   viaTx.accuracyBps);
        assertEq(viaView.totalClaims,   viaTx.totalClaims);
        assertEq(viaView.reputation,    viaTx.reputation);
        assertEq(uint8(viaView.tier),   uint8(viaTx.tier));
        assertEq(viaView.trustScore,    viaTx.trustScore);
    }

    // ============ score() emits event ============

    function test_Score_EmitsScorecardQueried() public {
        EMETScorecard.Score memory s = scorecard.peek(agentGold);
        vm.expectEmit(true, true, false, true);
        emit EMETScorecard.ScorecardQueried(address(this), agentGold, s.tier, s.trustScore);
        scorecard.score(agentGold);
    }

    // ============ peek() does NOT emit ============

    function test_Peek_NoEvent() public {
        // Record log count before — peek should emit nothing
        vm.recordLogs();
        scorecard.peek(agentGold);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0);
    }

    // ============ Policy checks (check() wrapper) ============

    function test_Check_Platinum_PassesStrict() public view {
        (bool passes, ) = scorecard.check(agentPlatinum, EMETTrustGate.Policy.STRICT);
        assertTrue(passes);
    }

    function test_Check_Gold_PassesStandard() public view {
        (bool passes, ) = scorecard.check(agentGold, EMETTrustGate.Policy.STANDARD);
        assertTrue(passes);
    }

    function test_Check_Unrated_FailsStandard() public view {
        (bool passes, ) = scorecard.check(agentUnrated, EMETTrustGate.Policy.STANDARD);
        assertFalse(passes);
    }

    function test_Check_Unrated_PassesLenient() public view {
        (bool passes, ) = scorecard.check(agentUnrated, EMETTrustGate.Policy.LENIENT);
        assertTrue(passes);
    }

    // ============ Score struct fields ============

    function test_ScoreStruct_Platinum_PolicyFields() public view {
        EMETScorecard.Score memory s = scorecard.peek(agentPlatinum);
        assertTrue(s.passesLenient);
        assertTrue(s.passesStandard);
        assertTrue(s.passesStrict);
    }

    function test_ScoreStruct_Unrated_FailsAllPolicies() public view {
        address nobody = address(0xBBBB);
        EMETScorecard.Score memory s = scorecard.peek(nobody);
        assertFalse(s.passesLenient);
        assertFalse(s.passesStandard);
        assertFalse(s.passesStrict);
    }

    function test_ScoreStruct_Platinum_Accuracy() public view {
        EMETScorecard.Score memory s = scorecard.peek(agentPlatinum);
        // 22 correct, 1 slashed = 23 total → 95.65%
        assertGt(s.accuracyBps, 9_000); // > 90%
        assertLe(s.accuracyBps, 10_000);
    }

    function test_ScoreStruct_TotalClaims() public view {
        EMETScorecard.Score memory s = scorecard.peek(agentGold);
        assertEq(s.totalClaims, 14); // 12 correct + 2 slashed
    }

    function test_ScoreStruct_CorrectClaims() public view {
        EMETScorecard.Score memory s = scorecard.peek(agentGold);
        assertEq(s.correctClaims, 12);
    }

    function test_ScoreStruct_SlashCount() public view {
        EMETScorecard.Score memory s = scorecard.peek(agentGold);
        assertEq(s.slashCount, 2);
    }

    function test_ScoreStruct_ReputationPositive() public view {
        EMETScorecard.Score memory s = scorecard.peek(agentGold);
        assertGt(s.reputation, 0);
    }

    function test_ScoreStruct_RiskAppetite_HighStakes() public view {
        // agentPlatinum stakes 0.01 ETH average → High risk appetite
        EMETScorecard.Score memory s = scorecard.peek(agentPlatinum);
        assertEq(uint8(s.riskAppetite), uint8(EMETAgentProfile.RiskAppetite.High));
    }

    // ============ tierOf and trustScoreOf consistency ============

    function test_TierOf_ConsistentWithPeek() public view {
        EMETScorecard.Tier t1 = scorecard.tierOf(agentSilver);
        EMETScorecard.Score memory s = scorecard.peek(agentSilver);
        assertEq(uint8(t1), uint8(s.tier));
    }

    function test_TrustScoreOf_ConsistentWithPeek() public view {
        uint256 ts1 = scorecard.trustScoreOf(agentSilver);
        EMETScorecard.Score memory s = scorecard.peek(agentSilver);
        assertEq(ts1, s.trustScore);
    }

    // ============ Multi-agent comparison pattern ============

    function test_MultiAgent_RankOrdering() public view {
        uint256 tsPlatinum = scorecard.trustScoreOf(agentPlatinum);
        uint256 tsGold     = scorecard.trustScoreOf(agentGold);
        uint256 tsSilver   = scorecard.trustScoreOf(agentSilver);
        uint256 tsBronze   = scorecard.trustScoreOf(agentBronze);
        uint256 tsUnrated  = scorecard.trustScoreOf(agentUnrated);

        assertGt(tsPlatinum, tsGold);
        assertGt(tsGold,     tsSilver);
        assertGt(tsSilver,   tsBronze);
        assertGt(tsBronze,   tsUnrated);
        assertEq(tsUnrated,  0);
    }

    // ============ Trust score formula bounds ============

    function test_TrustScore_NeverExceeds1000() public view {
        uint256[7] memory scores = [
            scorecard.trustScoreOf(agentPlatinum),
            scorecard.trustScoreOf(agentGold),
            scorecard.trustScoreOf(agentSilver),
            scorecard.trustScoreOf(agentBronze),
            scorecard.trustScoreOf(agentUnrated),
            scorecard.trustScoreOf(agentSlashed),
            scorecard.trustScoreOf(agentNegRep)
        ];
        for (uint256 i = 0; i < 7; i++) {
            assertLe(scores[i], 1_000);
        }
    }

    // ============ Constants sanity ============

    function test_Constants_WeightsSumTo100() public view {
        assertEq(
            scorecard.WEIGHT_ACCURACY() + scorecard.WEIGHT_REPUTATION() + scorecard.WEIGHT_DEPTH(),
            100
        );
    }

    function test_Constants_TierThresholdsOrdered() public view {
        assertLt(scorecard.BRONZE_MIN_CLAIMS(),   scorecard.SILVER_MIN_CLAIMS());
        assertLt(scorecard.SILVER_MIN_CLAIMS(),   scorecard.GOLD_MIN_CLAIMS());
        assertLt(scorecard.GOLD_MIN_CLAIMS(),     scorecard.PLATINUM_MIN_CLAIMS());

        assertLt(scorecard.BRONZE_MIN_ACCURACY(), scorecard.SILVER_MIN_ACCURACY());
        assertLt(scorecard.SILVER_MIN_ACCURACY(), scorecard.GOLD_MIN_ACCURACY());
        assertLt(scorecard.GOLD_MIN_ACCURACY(),   scorecard.PLATINUM_MIN_ACCURACY());
    }

    // ============ External builder integration pattern ============

    /// @dev Simulate an external contract calling scorecard.peek() as a pre-task check
    function test_BuilderPattern_GateOnTier() public view {
        // Builder: only assign task to GOLD or above
        EMETScorecard.Score memory s = scorecard.peek(agentGold);
        bool eligible = (s.tier == EMETScorecard.Tier.GOLD ||
                         s.tier == EMETScorecard.Tier.PLATINUM);
        assertTrue(eligible);

        EMETScorecard.Score memory s2 = scorecard.peek(agentBronze);
        bool eligible2 = (s2.tier == EMETScorecard.Tier.GOLD ||
                          s2.tier == EMETScorecard.Tier.PLATINUM);
        assertFalse(eligible2);
    }

    /// @dev Simulate selecting best agent from a list by trust score
    function test_BuilderPattern_SelectBestAgent() public view {
        address[3] memory candidates = [agentSilver, agentBronze, agentGold];
        uint256 bestScore;
        address bestAgent;

        for (uint256 i = 0; i < candidates.length; i++) {
            uint256 ts = scorecard.trustScoreOf(candidates[i]);
            if (ts > bestScore) {
                bestScore = ts;
                bestAgent = candidates[i];
            }
        }

        assertEq(bestAgent, agentGold);
    }

    /// @dev Combine scorecard trustScore with a custom stake requirement
    function test_BuilderPattern_CompositeDecision() public view {
        EMETScorecard.Score memory s = scorecard.peek(agentGold);
        bool approveHighValueTask = (
            s.trustScore >= 500 &&
            s.passesStandard &&
            s.avgStakeWei >= 0.005 ether
        );
        assertTrue(approveHighValueTask);
    }
}
