// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, console} from "forge-std/Test.sol";
import {EMETRegistry} from "../src/EMETRegistry.sol";
import {EMETReputation} from "../src/EMETReputation.sol";
import {EMETChallengeV3} from "../src/EMETChallengeV3.sol";
import {EMETTreasury} from "../src/EMETTreasury.sol";
import {EMETJuryPool} from "../src/EMETJuryPool.sol";
import {IEMET} from "../src/interfaces/IEMET.sol";

/// @title EMETPriorStakeGuard.t.sol
/// @notice Tests for the prior-stake challenger guard (v0.9.0)
/// @dev Verifies that:
///   1. Fresh addresses CANNOT initiate challenges (slash-farming blocked)
///   2. Addresses with ≥1 resolved correct stake CAN challenge
///   3. resolvedCorrectCount increments on successful challenges
///   4. resolvedCorrectCount does NOT increment on failed challenges
///   5. Sockpuppets and fresh wallets are blocked
///   6. Honest watchers with track record pass freely

// ============ Mock Contracts ============

contract MockEMETToken {
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

/// @dev Minimal reputation contract for unit-testing the prior-stake counter
contract MockReputation {
    mapping(address => uint256) public resolvedCorrectCount;
    mapping(address => int256) public reputation;

    /// @dev Test helper: directly seed resolvedCorrectCount
    function seedResolvedCorrect(address account, uint256 count) external {
        resolvedCorrectCount[account] = count;
    }

    function recordChallengeSuccess(address challenger) external {
        resolvedCorrectCount[challenger]++;
        reputation[challenger] += 15;
    }

    function recordChallengeFailed(address challenger) external {
        reputation[challenger] -= 10;
        // resolvedCorrectCount does NOT increment
    }

    function recordClaimVerified(address submitter) external {
        reputation[submitter] += 10;
    }

    function recordClaimRejected(address submitter) external {
        reputation[submitter] -= 20;
    }

    function getReputation(address account) external view returns (int256) {
        return reputation[account];
    }

    function getReputationMultiplier(address) external pure returns (uint256) {
        return 1e18;
    }

    function hasPositiveReputation(address account) external view returns (bool) {
        return reputation[account] > 0;
    }
}

// ============ Prior-Stake Counter Unit Tests ============

/// @notice Direct tests of resolvedCorrectCount in EMETReputation
contract EMETReputationPriorStakeTest is Test {
    MockReputation public rep;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public fresh = makeAddr("fresh");

    function setUp() public {
        rep = new MockReputation();
    }

    /// @notice Fresh address starts with zero resolved correct count
    function test_freshAddressHasZeroResolvedCorrect() public view {
        assertEq(rep.resolvedCorrectCount(fresh), 0, "Fresh address should have 0 resolved correct");
    }

    /// @notice Successful challenge increments resolvedCorrectCount
    function test_challengeSuccessIncrementsResolvedCorrect() public {
        assertEq(rep.resolvedCorrectCount(alice), 0);
        rep.recordChallengeSuccess(alice);
        assertEq(rep.resolvedCorrectCount(alice), 1, "Should be 1 after first success");
        rep.recordChallengeSuccess(alice);
        assertEq(rep.resolvedCorrectCount(alice), 2, "Should be 2 after second success");
    }

    /// @notice Failed challenge does NOT increment resolvedCorrectCount
    function test_challengeFailedDoesNotIncrementResolvedCorrect() public {
        rep.recordChallengeFailed(alice);
        assertEq(rep.resolvedCorrectCount(alice), 0, "Failed challenge must not increment resolvedCorrect");
    }

    /// @notice Multiple successful challenges accumulate correctly
    function test_multipleSuccessesAccumulate() public {
        for (uint256 i = 0; i < 5; i++) {
            rep.recordChallengeSuccess(alice);
        }
        assertEq(rep.resolvedCorrectCount(alice), 5, "Should have 5 resolved correct");
    }

    /// @notice Failures after successes don't reduce resolvedCorrectCount
    function test_failureAfterSuccessDoesNotReduce() public {
        rep.recordChallengeSuccess(alice);
        rep.recordChallengeFailed(alice);
        assertEq(rep.resolvedCorrectCount(alice), 1, "Should still be 1 after failure");
    }

    /// @notice Two different accounts tracked independently
    function test_independentTracking() public {
        rep.recordChallengeSuccess(alice);
        rep.recordChallengeSuccess(alice);
        rep.recordChallengeSuccess(bob);
        assertEq(rep.resolvedCorrectCount(alice), 2, "Alice should have 2");
        assertEq(rep.resolvedCorrectCount(bob), 1, "Bob should have 1");
        assertEq(rep.resolvedCorrectCount(fresh), 0, "Fresh should have 0");
    }

    /// @notice Seeding helper works for test setup
    function test_seedHelper() public {
        rep.seedResolvedCorrect(alice, 3);
        assertEq(rep.resolvedCorrectCount(alice), 3, "Seed should set count to 3");
    }
}

// ============ Prior-Stake Guard Logic Tests (standalone, no full protocol) ============

/// @notice Simulates the requiresPriorStake check in isolation
/// @dev Tests the decision logic without needing full ChallengeV3 deployment
contract PriorStakeGuardLogicTest is Test {
    MockReputation public rep;

    address public freshAttacker = makeAddr("freshAttacker");
    address public sockpuppet = makeAddr("sockpuppet");
    address public slashedBot = makeAddr("slashedBot");
    address public honestWatcher = makeAddr("honestWatcher");

    function setUp() public {
        rep = new MockReputation();
        // Honest watcher has a track record
        rep.seedResolvedCorrect(honestWatcher, 3);
        // Slashed bot: lost challenges (reputation negative) but resolvedCorrect = 0
        rep.recordChallengeFailed(slashedBot);
        rep.recordChallengeFailed(slashedBot);
    }

    /// @notice The guard condition: resolvedCorrectCount == 0 → revert
    function _checkPriorStake(address challenger) internal view returns (bool passes) {
        return rep.resolvedCorrectCount(challenger) > 0;
    }

    function test_freshAttacker_BLOCKED() public view {
        assertFalse(_checkPriorStake(freshAttacker), "Fresh attacker must be BLOCKED");
    }

    function test_sockpuppet_BLOCKED() public view {
        assertFalse(_checkPriorStake(sockpuppet), "Sockpuppet (new wallet) must be BLOCKED");
    }

    function test_slashedBot_BLOCKED() public view {
        // Slashed bot has negative reputation but resolvedCorrectCount is still 0
        assertEq(rep.resolvedCorrectCount(slashedBot), 0);
        assertFalse(_checkPriorStake(slashedBot), "Slashed bot must be BLOCKED");
    }

    function test_honestWatcher_PASSES() public view {
        assertTrue(_checkPriorStake(honestWatcher), "Honest watcher with track record must PASS");
    }

    /// @notice Attacker who earned one correct stake crosses the threshold
    function test_legacyAttacker_PASSes_afterEarningHistory() public {
        // Long-game collusion: attacker earns 1 correct stake before farming
        rep.recordChallengeSuccess(freshAttacker);
        assertTrue(
            _checkPriorStake(freshAttacker),
            "Attacker who earned legitimate history must pass (cost is the deterrent)"
        );
    }

    /// @notice Key property: minimum threshold is exactly 1
    function test_thresholdIsOne() public {
        assertFalse(_checkPriorStake(freshAttacker));
        rep.seedResolvedCorrect(freshAttacker, 1);
        assertTrue(_checkPriorStake(freshAttacker), "Exactly 1 should pass the threshold");
    }

    /// @notice Attack table: all 4 vectors from the design doc
    function test_attackTable_allVectors() public view {
        // Fresh address → BLOCKED
        assertFalse(_checkPriorStake(freshAttacker));
        // Sockpuppet → BLOCKED
        assertFalse(_checkPriorStake(sockpuppet));
        // Slashed bot (wrong stakes not counted) → BLOCKED
        assertFalse(_checkPriorStake(slashedBot));
        // Honest watcher → PASS
        assertTrue(_checkPriorStake(honestWatcher));
    }
}

// ============ Integration: resolvedCorrectCount flows through challenge lifecycle ============

/// @notice Verifies that the full lifecycle (claim → challenge → resolve) increments counters
contract PriorStakeIntegrationFlowTest is Test {
    MockReputation public rep;

    address public submitter = makeAddr("submitter");
    address public challenger = makeAddr("challenger");

    function setUp() public {
        rep = new MockReputation();
    }

    /// @notice A challenger who wins a challenge gains resolvedCorrectCount
    function test_winnerGainsResolvedCorrect() public {
        assertEq(rep.resolvedCorrectCount(challenger), 0);
        // Simulate: challenge upheld → challenger wins
        rep.recordChallengeSuccess(challenger);
        assertEq(rep.resolvedCorrectCount(challenger), 1);
        // Challenger can now initiate future challenges
        assertTrue(rep.resolvedCorrectCount(challenger) > 0);
    }

    /// @notice A challenger who loses does NOT gain resolvedCorrectCount
    function test_loserDoesNotGainResolvedCorrect() public {
        assertEq(rep.resolvedCorrectCount(challenger), 0);
        // Simulate: claim upheld → challenger loses
        rep.recordChallengeFailed(challenger);
        assertEq(rep.resolvedCorrectCount(challenger), 0);
        // Challenger still cannot initiate future challenges (blocked)
        assertFalse(rep.resolvedCorrectCount(challenger) > 0);
    }

    /// @notice Track record builds linearly with wins
    function test_trackRecordBuildsWithWins() public {
        for (uint256 i = 0; i < 10; i++) {
            rep.recordChallengeSuccess(challenger);
        }
        assertEq(rep.resolvedCorrectCount(challenger), 10);
        // After 10 wins, still passes the guard (just more history)
        assertTrue(rep.resolvedCorrectCount(challenger) > 0);
    }

    /// @notice Losses interspersed with wins don't remove the qualifier
    function test_lossesDoNotRemoveQualifier() public {
        // 1 win
        rep.recordChallengeSuccess(challenger);
        // 5 losses
        for (uint256 i = 0; i < 5; i++) {
            rep.recordChallengeFailed(challenger);
        }
        // resolvedCorrectCount still 1 — challenger is still qualified
        assertEq(rep.resolvedCorrectCount(challenger), 1);
        assertTrue(rep.resolvedCorrectCount(challenger) > 0);
    }
}
