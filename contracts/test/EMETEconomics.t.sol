// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, console} from "forge-std/Test.sol";
import {EMETRegistry} from "../src/EMETRegistry.sol";
import {EMETStake} from "../src/EMETStake.sol";
import {EMETChallenge} from "../src/EMETChallenge.sol";
import {EMETSignature} from "../src/EMETSignature.sol";
import {EMETTreasury} from "../src/EMETTreasury.sol";
import {EMETReputation} from "../src/EMETReputation.sol";
import {EMETLPRewards} from "../src/EMETLPRewards.sol";
import {EMETChallengeV2} from "../src/EMETChallengeV2.sol";
import {IEMET} from "../src/interfaces/IEMET.sol";
import {INonfungiblePositionManager, IERC721Receiver} from "../src/interfaces/IUniswapV3.sol";

// ============ Mocks ============

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

/// @notice Mock Uniswap V3 NonfungiblePositionManager for LP rewards tests
contract MockPositionManager {
    struct MockPosition {
        address owner;
        address token0;
        address token1;
        uint24 fee;
        uint128 liquidity;
    }

    mapping(uint256 => MockPosition) public mockPositions;
    uint256 public nextTokenId = 1;

    function createPosition(
        address owner,
        address token0,
        address token1,
        uint24 fee,
        uint128 liquidity
    ) external returns (uint256 tokenId) {
        tokenId = nextTokenId++;
        mockPositions[tokenId] = MockPosition({
            owner: owner,
            token0: token0,
            token1: token1,
            fee: fee,
            liquidity: liquidity
        });
    }

    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        MockPosition memory p = mockPositions[tokenId];
        return (
            0, address(0), p.token0, p.token1, p.fee,
            -887_272, 887_272, p.liquidity,
            0, 0, 0, 0
        );
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        return mockPositions[tokenId].owner;
    }

    function transferFrom(address from, address to, uint256 tokenId) external {
        require(mockPositions[tokenId].owner == from, "Not owner");
        mockPositions[tokenId].owner = to;
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        require(mockPositions[tokenId].owner == from, "Not owner");
        mockPositions[tokenId].owner = to;
    }
}

// ============ Treasury Tests ============

contract EMETTreasuryTest is Test {
    MockEMET public emet;
    EMETTreasury public treasury;

    address public admin = makeAddr("admin");
    address public distributor = makeAddr("distributor");
    address public lpRewards = makeAddr("lpRewards");
    address public alice = makeAddr("alice");

    function setUp() public {
        // Deploy mock at expected address
        MockEMET mockEmet = new MockEMET();
        address expectedEMET = 0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C;
        vm.etch(expectedEMET, address(mockEmet).code);
        emet = MockEMET(expectedEMET);

        treasury = new EMETTreasury(admin);
    }

    function test_Constructor() public view {
        assertEq(treasury.admin(), admin);
        assertEq(treasury.PROTOCOL_FEE_BPS(), 100);
        assertEq(treasury.BPS_DENOMINATOR(), 10_000);
    }

    function test_SetFeeDistributor() public {
        vm.prank(admin);
        treasury.setFeeDistributor(distributor);
        assertEq(treasury.feeDistributor(), distributor);
    }

    function test_SetFeeDistributor_OnlyAdmin() public {
        vm.prank(alice);
        vm.expectRevert(EMETTreasury.OnlyAdmin.selector);
        treasury.setFeeDistributor(distributor);
    }

    function test_SetFeeDistributor_OnlyOnce() public {
        vm.prank(admin);
        treasury.setFeeDistributor(distributor);

        vm.prank(admin);
        vm.expectRevert(EMETTreasury.FeeDistributorAlreadySet.selector);
        treasury.setFeeDistributor(alice);
    }

    function test_SetLPRewardsContract() public {
        vm.prank(admin);
        treasury.setLPRewardsContract(lpRewards);
        assertEq(treasury.lpRewardsContract(), lpRewards);
    }

    function test_SetLPRewardsContract_OnlyOnce() public {
        vm.prank(admin);
        treasury.setLPRewardsContract(lpRewards);

        vm.prank(admin);
        vm.expectRevert(EMETTreasury.LPRewardsAlreadySet.selector);
        treasury.setLPRewardsContract(alice);
    }

    function test_ReceiveFee() public {
        vm.prank(admin);
        treasury.setFeeDistributor(distributor);

        // Send EMET to treasury first
        emet.mint(address(treasury), 100e18);

        vm.prank(distributor);
        treasury.receiveFee(0, 10e18, 1000e18);

        assertEq(treasury.totalFeesReceived(), 10e18);
    }

    function test_ReceiveFee_OnlyDistributor() public {
        vm.prank(admin);
        treasury.setFeeDistributor(distributor);

        vm.prank(alice);
        vm.expectRevert(EMETTreasury.OnlyFeeDistributor.selector);
        treasury.receiveFee(0, 10e18, 1000e18);
    }

    function test_Withdraw() public {
        emet.mint(address(treasury), 500e18);

        vm.prank(admin);
        treasury.withdraw(alice, 200e18);

        assertEq(emet.balanceOf(alice), 200e18);
        assertEq(emet.balanceOf(address(treasury)), 300e18);
    }

    function test_Withdraw_OnlyAdmin() public {
        emet.mint(address(treasury), 500e18);

        vm.prank(alice);
        vm.expectRevert(EMETTreasury.OnlyAdmin.selector);
        treasury.withdraw(alice, 200e18);
    }

    function test_Withdraw_InsufficientBalance() public {
        emet.mint(address(treasury), 100e18);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(EMETTreasury.InsufficientBalance.selector, 200e18, 100e18)
        );
        treasury.withdraw(alice, 200e18);
    }

    function test_DistributeLPRewards() public {
        vm.prank(admin);
        treasury.setLPRewardsContract(lpRewards);

        emet.mint(address(treasury), 500e18);

        vm.prank(admin);
        treasury.distributeLPRewards(100e18);

        assertEq(emet.balanceOf(lpRewards), 100e18);
        assertEq(treasury.totalLPRewardsDistributed(), 100e18);
    }

    function test_CalculateFee() public view {
        // 1% of 1000 = 10
        assertEq(treasury.calculateFee(1000e18), 10e18);
        // 1% of 100 = 1
        assertEq(treasury.calculateFee(100e18), 1e18);
        // Edge: 0
        assertEq(treasury.calculateFee(0), 0);
    }

    function test_Balance() public {
        emet.mint(address(treasury), 1234e18);
        assertEq(treasury.balance(), 1234e18);
    }
}

// ============ Reputation Tests ============

contract EMETReputationTest is Test {
    EMETReputation public reputation;

    address public deployer;
    address public updater = makeAddr("updater");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        deployer = address(this);
        reputation = new EMETReputation();
        reputation.setUpdater(updater);
    }

    function test_Constructor() public view {
        assertEq(reputation.deployer(), deployer);
        assertEq(reputation.updater(), updater);
    }

    function test_SetUpdater_OnlyDeployer() public {
        EMETReputation rep2 = new EMETReputation();

        vm.prank(alice);
        vm.expectRevert(EMETReputation.OnlyDeployer.selector);
        rep2.setUpdater(updater);
    }

    function test_SetUpdater_OnlyOnce() public {
        vm.expectRevert(EMETReputation.UpdaterAlreadySet.selector);
        reputation.setUpdater(alice);
    }

    function test_ClaimVerified() public {
        vm.prank(updater);
        reputation.recordClaimVerified(alice);

        assertEq(reputation.getReputation(alice), 10);
        assertEq(reputation.totalUpdates(), 1);
    }

    function test_ClaimRejected() public {
        vm.prank(updater);
        reputation.recordClaimRejected(alice);

        assertEq(reputation.getReputation(alice), -20);
    }

    function test_ChallengeSuccess() public {
        vm.prank(updater);
        reputation.recordChallengeSuccess(alice);

        assertEq(reputation.getReputation(alice), 15);
    }

    function test_ChallengeFailed() public {
        vm.prank(updater);
        reputation.recordChallengeFailed(alice);

        assertEq(reputation.getReputation(alice), -10);
    }

    function test_CosignVerified() public {
        vm.prank(updater);
        reputation.recordCosignVerified(alice);

        assertEq(reputation.getReputation(alice), 5);
    }

    function test_CosignVerifiedBatch() public {
        address[] memory cosigners = new address[](3);
        cosigners[0] = alice;
        cosigners[1] = bob;
        cosigners[2] = makeAddr("charlie");

        vm.prank(updater);
        reputation.recordCosignVerifiedBatch(cosigners);

        assertEq(reputation.getReputation(alice), 5);
        assertEq(reputation.getReputation(bob), 5);
        assertEq(reputation.getReputation(cosigners[2]), 5);
        assertEq(reputation.totalUpdates(), 3);
    }

    function test_ReputationAccumulates() public {
        // Alice verifies 5 claims: 5 * 10 = 50
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(updater);
            reputation.recordClaimVerified(alice);
        }
        assertEq(reputation.getReputation(alice), 50);

        // Then gets one rejected: 50 - 20 = 30
        vm.prank(updater);
        reputation.recordClaimRejected(alice);
        assertEq(reputation.getReputation(alice), 30);
    }

    function test_ReputationGoesNegative() public {
        // Three rejections: 3 * -20 = -60
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(updater);
            reputation.recordClaimRejected(alice);
        }
        assertEq(reputation.getReputation(alice), -60);
    }

    function test_OnlyUpdater() public {
        vm.prank(alice);
        vm.expectRevert(EMETReputation.OnlyUpdater.selector);
        reputation.recordClaimVerified(alice);
    }

    // ============ Multiplier Tests ============

    function test_Multiplier_Zero() public view {
        // Default: 0 reputation → 1.0x
        uint256 mult = reputation.getReputationMultiplier(alice);
        assertEq(mult, 1e18);
    }

    function test_Multiplier_Negative() public {
        vm.prank(updater);
        reputation.recordClaimRejected(alice); // -20

        uint256 mult = reputation.getReputationMultiplier(alice);
        assertEq(mult, 1e18); // Floor at 1.0x
    }

    function test_Multiplier_Halfway() public {
        // 50 rep → 1.5x
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(updater);
            reputation.recordClaimVerified(alice);
        }
        assertEq(reputation.getReputation(alice), 50);

        uint256 mult = reputation.getReputationMultiplier(alice);
        assertEq(mult, 1.5e18);
    }

    function test_Multiplier_Max() public {
        // 100+ rep → 2.0x
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(updater);
            reputation.recordClaimVerified(alice);
        }
        assertEq(reputation.getReputation(alice), 100);

        uint256 mult = reputation.getReputationMultiplier(alice);
        assertEq(mult, 2e18);
    }

    function test_Multiplier_BeyondMax() public {
        // 200 rep → still 2.0x (capped)
        for (uint256 i = 0; i < 20; i++) {
            vm.prank(updater);
            reputation.recordClaimVerified(alice);
        }
        assertEq(reputation.getReputation(alice), 200);

        uint256 mult = reputation.getReputationMultiplier(alice);
        assertEq(mult, 2e18);
    }

    // ============ Tier Tests ============

    function test_Tiers() public {
        assertEq(reputation.getReputationTier(alice), "Unknown"); // 0

        vm.prank(updater);
        reputation.recordClaimVerified(alice); // +10
        assertEq(reputation.getReputationTier(alice), "Newcomer");

        // Get to 25
        vm.prank(updater);
        reputation.recordChallengeSuccess(alice); // +15 → 25
        assertEq(reputation.getReputationTier(alice), "Contributor");

        // Get to 50
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(updater);
            reputation.recordCosignVerified(alice); // +5 each → 50
        }
        assertEq(reputation.getReputationTier(alice), "Trusted");

        // Get to 75
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(updater);
            reputation.recordCosignVerified(alice); // +5 each → 75
        }
        assertEq(reputation.getReputationTier(alice), "Expert");

        // Get to 100+
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(updater);
            reputation.recordCosignVerified(alice); // +5 each → 100
        }
        assertEq(reputation.getReputationTier(alice), "Authority");

        // Negative
        vm.prank(updater);
        reputation.recordClaimRejected(bob); // -20
        assertEq(reputation.getReputationTier(bob), "Untrusted");
    }

    function test_HasPositiveReputation() public {
        assertFalse(reputation.hasPositiveReputation(alice));

        vm.prank(updater);
        reputation.recordClaimVerified(alice);
        assertTrue(reputation.hasPositiveReputation(alice));

        vm.prank(updater);
        reputation.recordClaimRejected(alice); // 10 - 20 = -10
        assertFalse(reputation.hasPositiveReputation(alice));
    }
}

// ============ LP Rewards Tests ============

contract EMETLPRewardsTest is Test {
    MockEMET public emet;
    MockPositionManager public positionManager;
    EMETLPRewards public lpRewards;

    address public treasuryAddr = makeAddr("treasury");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    address public constant EMET_ADDR = 0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C;
    address public constant WETH_ADDR = 0x4200000000000000000000000000000000000006;
    uint24 public constant FEE_TIER = 3000;

    function setUp() public {
        // Deploy mock EMET at expected address
        MockEMET mockEmet = new MockEMET();
        vm.etch(EMET_ADDR, address(mockEmet).code);
        emet = MockEMET(EMET_ADDR);

        positionManager = new MockPositionManager();

        lpRewards = new EMETLPRewards(
            address(positionManager),
            EMET_ADDR,
            WETH_ADDR,
            FEE_TIER,
            treasuryAddr
        );
    }

    function _createAndStakePosition(address user, uint128 liquidity)
        internal
        returns (uint256 tokenId)
    {
        tokenId = positionManager.createPosition(user, EMET_ADDR, WETH_ADDR, FEE_TIER, liquidity);
        vm.prank(user);
        lpRewards.stake(tokenId);
    }

    function test_StakePosition() public {
        uint256 tokenId = _createAndStakePosition(alice, 1000e18);

        assertEq(lpRewards.totalLiquidity(), 1000e18);
        assertEq(lpRewards.stakedPositionCount(alice), 1);

        uint256[] memory tokens = lpRewards.getUserStakedTokens(alice);
        assertEq(tokens.length, 1);
        assertEq(tokens[0], tokenId);

        // NFT should be owned by lpRewards now
        assertEq(positionManager.ownerOf(tokenId), address(lpRewards));
    }

    function test_StakePosition_WrongPool() public {
        address wrongToken = makeAddr("wrongToken");
        uint256 tokenId =
            positionManager.createPosition(alice, wrongToken, WETH_ADDR, FEE_TIER, 1000e18);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                EMETLPRewards.InvalidPool.selector, wrongToken, WETH_ADDR, FEE_TIER
            )
        );
        lpRewards.stake(tokenId);
    }

    function test_StakePosition_WrongFee() public {
        uint256 tokenId =
            positionManager.createPosition(alice, EMET_ADDR, WETH_ADDR, 10_000, 1000e18);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(EMETLPRewards.InvalidPool.selector, EMET_ADDR, WETH_ADDR, 10_000)
        );
        lpRewards.stake(tokenId);
    }

    function test_StakePosition_ZeroLiquidity() public {
        uint256 tokenId =
            positionManager.createPosition(alice, EMET_ADDR, WETH_ADDR, FEE_TIER, 0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(EMETLPRewards.ZeroLiquidity.selector, tokenId));
        lpRewards.stake(tokenId);
    }

    function test_UnstakePosition() public {
        uint256 tokenId = _createAndStakePosition(alice, 1000e18);

        vm.prank(alice);
        lpRewards.unstake(tokenId);

        assertEq(lpRewards.totalLiquidity(), 0);
        assertEq(lpRewards.stakedPositionCount(alice), 0);
        assertEq(positionManager.ownerOf(tokenId), alice);
    }

    function test_UnstakePosition_NotOwner() public {
        uint256 tokenId = _createAndStakePosition(alice, 1000e18);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(EMETLPRewards.NotPositionOwner.selector, tokenId, bob)
        );
        lpRewards.unstake(tokenId);
    }

    function test_DistributeRewards() public {
        _createAndStakePosition(alice, 1000e18);

        emet.mint(address(lpRewards), 100e18);

        vm.prank(treasuryAddr);
        lpRewards.distributeRewards(100e18);

        assertEq(lpRewards.totalRewardsDistributed(), 100e18);
    }

    function test_DistributeRewards_OnlyTreasury() public {
        vm.prank(alice);
        vm.expectRevert(EMETLPRewards.OnlyTreasury.selector);
        lpRewards.distributeRewards(100e18);
    }

    function test_ClaimRewards_SingleStaker() public {
        _createAndStakePosition(alice, 1000e18);

        // Distribute 100 EMET rewards
        emet.mint(address(lpRewards), 100e18);
        vm.prank(treasuryAddr);
        lpRewards.distributeRewards(100e18);

        // Alice should get all 100
        uint256 claimable = lpRewards.claimableRewards(alice);
        assertEq(claimable, 100e18);

        vm.prank(alice);
        lpRewards.claim();

        assertEq(emet.balanceOf(alice), 100e18);
        assertEq(lpRewards.claimableRewards(alice), 0);
    }

    function test_ClaimRewards_ProportionalDistribution() public {
        // Alice stakes 3000 liquidity, Bob stakes 1000
        _createAndStakePosition(alice, 3000e18);
        _createAndStakePosition(bob, 1000e18);

        // Distribute 100 EMET
        emet.mint(address(lpRewards), 100e18);
        vm.prank(treasuryAddr);
        lpRewards.distributeRewards(100e18);

        // Alice: 75%, Bob: 25%
        uint256 aliceClaimable = lpRewards.claimableRewards(alice);
        uint256 bobClaimable = lpRewards.claimableRewards(bob);

        assertEq(aliceClaimable, 75e18);
        assertEq(bobClaimable, 25e18);
    }

    function test_ClaimRewards_MultipleDistributions() public {
        _createAndStakePosition(alice, 1000e18);

        // First distribution: 50
        emet.mint(address(lpRewards), 50e18);
        vm.prank(treasuryAddr);
        lpRewards.distributeRewards(50e18);

        // Second distribution: 50
        emet.mint(address(lpRewards), 50e18);
        vm.prank(treasuryAddr);
        lpRewards.distributeRewards(50e18);

        // Alice should have accumulated 100
        assertEq(lpRewards.claimableRewards(alice), 100e18);
    }

    function test_ClaimRewards_NoRewards() public {
        _createAndStakePosition(alice, 1000e18);

        vm.prank(alice);
        vm.expectRevert(EMETLPRewards.NoRewardsToClaim.selector);
        lpRewards.claim();
    }

    function test_StakeAfterDistribution() public {
        // Alice stakes first
        _createAndStakePosition(alice, 1000e18);

        // Rewards distributed
        emet.mint(address(lpRewards), 100e18);
        vm.prank(treasuryAddr);
        lpRewards.distributeRewards(100e18);

        // Bob stakes after distribution — should NOT get retroactive rewards
        _createAndStakePosition(bob, 1000e18);

        uint256 bobClaimable = lpRewards.claimableRewards(bob);
        assertEq(bobClaimable, 0);

        // Alice should still get full 100
        uint256 aliceClaimable = lpRewards.claimableRewards(alice);
        assertEq(aliceClaimable, 100e18);
    }

    function test_MultiplePositions() public {
        _createAndStakePosition(alice, 1000e18);
        _createAndStakePosition(alice, 2000e18);

        assertEq(lpRewards.totalLiquidity(), 3000e18);
        assertEq(lpRewards.getUserLiquidity(alice), 3000e18);
        assertEq(lpRewards.stakedPositionCount(alice), 2);

        emet.mint(address(lpRewards), 300e18);
        vm.prank(treasuryAddr);
        lpRewards.distributeRewards(300e18);

        assertEq(lpRewards.claimableRewards(alice), 300e18);
    }

    function test_TokenOrderReversed() public {
        // WETH as token0, EMET as token1 (reversed order)
        uint256 tokenId =
            positionManager.createPosition(alice, WETH_ADDR, EMET_ADDR, FEE_TIER, 500e18);

        vm.prank(alice);
        lpRewards.stake(tokenId);

        assertEq(lpRewards.totalLiquidity(), 500e18);
    }
}

// ============ ChallengeV2 Integration Tests ============

contract EMETChallengeV2Test is Test {
    MockEMET public emet;
    EMETRegistry public registry;
    EMETStake public stakeContract;
    EMETSignature public signatureContract;
    EMETTreasury public treasury;
    EMETReputation public reputation;
    EMETChallengeV2 public challengeV2;

    address public admin = makeAddr("admin");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    uint256 public constant MINIMUM_STAKE = 100e18;
    uint256 public constant CHALLENGE_PERIOD = 7 days;
    uint256 public constant MINIMUM_CHALLENGE_STAKE = 50e18;

    function setUp() public {
        // Deploy mock EMET at expected address
        MockEMET mockEmet = new MockEMET();
        address expectedEMET = 0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C;
        vm.etch(expectedEMET, address(mockEmet).code);
        emet = MockEMET(expectedEMET);

        // Deploy core protocol
        registry = new EMETRegistry(MINIMUM_STAKE, CHALLENGE_PERIOD);
        stakeContract = new EMETStake(address(registry));
        signatureContract = new EMETSignature(address(registry));

        // Deploy economics layer
        treasury = new EMETTreasury(admin);
        reputation = new EMETReputation();

        // Deploy ChallengeV2
        challengeV2 = new EMETChallengeV2(
            address(registry),
            address(stakeContract),
            address(treasury),
            address(reputation),
            address(signatureContract),
            MINIMUM_CHALLENGE_STAKE
        );

        // Wire up contracts
        registry.setChallengeContract(address(challengeV2));
        stakeContract.setChallengeContract(address(challengeV2));
        reputation.setUpdater(address(challengeV2));

        vm.prank(admin);
        treasury.setFeeDistributor(address(challengeV2));

        // Fund accounts
        emet.mint(alice, 10_000e18);
        emet.mint(bob, 10_000e18);
        emet.mint(charlie, 10_000e18);

        // Approve all contracts
        address[3] memory users = [alice, bob, charlie];
        address[3] memory contracts =
            [address(registry), address(stakeContract), address(challengeV2)];

        for (uint256 i = 0; i < users.length; i++) {
            for (uint256 j = 0; j < contracts.length; j++) {
                vm.prank(users[i]);
                emet.approve(contracts[j], type(uint256).max);
            }
        }
    }

    // ============ Basic Challenge Flow ============

    function test_InitiateChallenge() public {
        vm.prank(alice);
        uint256 claimId = registry.submitClaim("Autonomous AI agents can collaborate across model boundaries", "ipfs://test", MINIMUM_STAKE);

        vm.prank(bob);
        challengeV2.initiateChallenge(claimId, MINIMUM_CHALLENGE_STAKE);

        EMETRegistry.Claim memory claim = registry.getClaim(claimId);
        assertEq(uint256(claim.status), uint256(EMETRegistry.ClaimStatus.Challenged));

        (address challenger, uint256 stake,,) = challengeV2.getChallenge(claimId);
        assertEq(challenger, bob);
        assertEq(stake, MINIMUM_CHALLENGE_STAKE);
    }

    function test_CannotChallengeSelf() public {
        vm.prank(alice);
        uint256 claimId = registry.submitClaim("Autonomous AI agents can collaborate across model boundaries", "ipfs://test", MINIMUM_STAKE);

        vm.prank(alice);
        vm.expectRevert(EMETChallengeV2.CannotChallengeOwnClaim.selector);
        challengeV2.initiateChallenge(claimId, MINIMUM_CHALLENGE_STAKE);
    }

    function test_InsufficientChallengeStake() public {
        vm.prank(alice);
        uint256 claimId = registry.submitClaim("Autonomous AI agents can collaborate across model boundaries", "ipfs://test", MINIMUM_STAKE);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(EMETChallengeV2.InsufficientStake.selector, 10e18, 50e18)
        );
        challengeV2.initiateChallenge(claimId, 10e18);
    }

    // ============ Resolution with Reputation ============

    function test_ResolveChallenge_Verified_UpdatesReputation() public {
        // Alice submits, Bob challenges, Charlie supports → Claim verified
        vm.prank(alice);
        uint256 claimId = registry.submitClaim("Autonomous AI agents can collaborate across model boundaries", "ipfs://test", MINIMUM_STAKE);

        vm.prank(bob);
        challengeV2.initiateChallenge(claimId, MINIMUM_CHALLENGE_STAKE);

        vm.prank(charlie);
        stakeContract.stakeFor(claimId, 100e18);

        vm.warp(block.timestamp + CHALLENGE_PERIOD + 1);
        challengeV2.resolveChallenge(claimId);

        // Verify reputation updates
        assertEq(reputation.getReputation(alice), 10); // claim_verified: +10
        assertEq(reputation.getReputation(bob), -10); // challenge_failed: -10
    }

    function test_ResolveChallenge_Rejected_UpdatesReputation() public {
        // Alice submits, Bob challenges with overwhelming stake → Claim rejected
        vm.prank(alice);
        uint256 claimId = registry.submitClaim("Autonomous AI agents can collaborate across model boundaries", "ipfs://test", MINIMUM_STAKE);

        vm.prank(bob);
        challengeV2.initiateChallenge(claimId, 200e18);

        vm.warp(block.timestamp + CHALLENGE_PERIOD + 1);
        challengeV2.resolveChallenge(claimId);

        // Verify reputation updates
        assertEq(reputation.getReputation(alice), -20); // claim_rejected: -20
        assertEq(reputation.getReputation(bob), 15); // challenge_success: +15
    }

    function test_ReputationAccumulatesAcrossClaims() public {
        // Alice submits and gets verified twice
        for (uint256 i = 0; i < 2; i++) {
            vm.prank(alice);
            uint256 claimId = registry.submitClaim(
                string.concat("Reputation claim ", vm.toString(i)), "ipfs://test", MINIMUM_STAKE
            );

            vm.prank(bob);
            challengeV2.initiateChallenge(claimId, MINIMUM_CHALLENGE_STAKE);

            vm.prank(charlie);
            stakeContract.stakeFor(claimId, 100e18);

            vm.warp(block.timestamp + CHALLENGE_PERIOD + 1);
            challengeV2.resolveChallenge(claimId);
        }

        assertEq(reputation.getReputation(alice), 20); // 2 * +10
        assertEq(reputation.getReputation(bob), -20); // 2 * -10
    }

    // ============ Fee Calculation ============

    function test_GetCurrentStanding_WithFee() public {
        vm.prank(alice);
        uint256 claimId = registry.submitClaim("Autonomous AI agents can collaborate across model boundaries", "ipfs://test", 100e18);

        vm.prank(bob);
        challengeV2.initiateChallenge(claimId, 100e18);

        (uint256 effectiveFor, uint256 against, string memory winner, uint256 fee) =
            challengeV2.getCurrentStanding(claimId);

        assertEq(effectiveFor, 100e18); // claim stake
        assertEq(against, 100e18); // challenge stake
        assertEq(keccak256(bytes(winner)), keccak256(bytes("for"))); // tie goes to submitter
        assertEq(fee, 2e18); // 1% of 200
    }

    // ============ Reward Multiplier Preview ============

    function test_PreviewRewardWithMultiplier_NoReputation() public view {
        uint256 adjusted = challengeV2.previewRewardWithMultiplier(alice, 100e18);
        assertEq(adjusted, 100e18); // 1.0x multiplier
    }

    function test_PreviewRewardWithMultiplier_HighReputation() public {
        // Give Alice 100 reputation (Authority)
        for (uint256 i = 0; i < 10; i++) {
            // Simulate 10 verified claims
            vm.prank(alice);
            uint256 claimId = registry.submitClaim(
                string.concat("High rep claim ", vm.toString(i)), "ipfs://test", MINIMUM_STAKE
            );

            vm.prank(bob);
            challengeV2.initiateChallenge(claimId, MINIMUM_CHALLENGE_STAKE);

            vm.prank(charlie);
            stakeContract.stakeFor(claimId, 100e18);

            vm.warp(block.timestamp + CHALLENGE_PERIOD + 1);
            challengeV2.resolveChallenge(claimId);
        }

        assertEq(reputation.getReputation(alice), 100);

        uint256 adjusted = challengeV2.previewRewardWithMultiplier(alice, 100e18);
        assertEq(adjusted, 200e18); // 2.0x multiplier
    }

    // ============ Stake Operations ============

    function test_StakeForClaim_DirectOnStakeContract() public {
        // Users stake FOR claims directly on the stake contract (not through ChallengeV2)
        vm.prank(alice);
        uint256 claimId = registry.submitClaim("Autonomous AI agents can collaborate across model boundaries", "ipfs://test", MINIMUM_STAKE);

        vm.prank(bob);
        challengeV2.initiateChallenge(claimId, MINIMUM_CHALLENGE_STAKE);

        vm.prank(charlie);
        stakeContract.stakeFor(claimId, 50e18);

        (uint256 totalFor,) = stakeContract.getStakeTotals(claimId);
        assertEq(totalFor, 50e18);
    }

    function test_StakeAgainstClaim() public {
        vm.prank(alice);
        uint256 claimId = registry.submitClaim("Autonomous AI agents can collaborate across model boundaries", "ipfs://test", MINIMUM_STAKE);

        vm.prank(bob);
        challengeV2.initiateChallenge(claimId, MINIMUM_CHALLENGE_STAKE);

        vm.prank(charlie);
        challengeV2.stakeAgainstClaim(claimId, 50e18);

        (, uint256 totalAgainst) = stakeContract.getStakeTotals(claimId);
        assertEq(totalAgainst, MINIMUM_CHALLENGE_STAKE + 50e18);
    }

    function test_CannotStakeAfterPeriod() public {
        vm.prank(alice);
        uint256 claimId = registry.submitClaim("Autonomous AI agents can collaborate across model boundaries", "ipfs://test", MINIMUM_STAKE);

        vm.prank(bob);
        challengeV2.initiateChallenge(claimId, MINIMUM_CHALLENGE_STAKE);

        vm.warp(block.timestamp + CHALLENGE_PERIOD + 1);

        // Staking via stakeContract after period should revert
        vm.prank(charlie);
        vm.expectRevert();
        stakeContract.stakeFor(claimId, 50e18);
    }

    // ============ Can Resolve ============

    function test_CanResolve() public {
        vm.prank(alice);
        uint256 claimId = registry.submitClaim("Autonomous AI agents can collaborate across model boundaries", "ipfs://test", MINIMUM_STAKE);

        assertFalse(challengeV2.canResolve(claimId));

        vm.prank(bob);
        challengeV2.initiateChallenge(claimId, MINIMUM_CHALLENGE_STAKE);

        assertFalse(challengeV2.canResolve(claimId)); // period not ended

        vm.warp(block.timestamp + CHALLENGE_PERIOD + 1);
        assertTrue(challengeV2.canResolve(claimId));
    }

    function test_CannotResolveBeforePeriod() public {
        vm.prank(alice);
        uint256 claimId = registry.submitClaim("Autonomous AI agents can collaborate across model boundaries", "ipfs://test", MINIMUM_STAKE);

        vm.prank(bob);
        challengeV2.initiateChallenge(claimId, MINIMUM_CHALLENGE_STAKE);

        vm.expectRevert();
        challengeV2.resolveChallenge(claimId);
    }

    function test_CannotResolveWithoutChallenge() public {
        vm.expectRevert();
        challengeV2.resolveChallenge(999);
    }

    function test_CannotDoubleResolve() public {
        vm.prank(alice);
        uint256 claimId = registry.submitClaim("Autonomous AI agents can collaborate across model boundaries", "ipfs://test", MINIMUM_STAKE);

        vm.prank(bob);
        challengeV2.initiateChallenge(claimId, MINIMUM_CHALLENGE_STAKE);

        vm.warp(block.timestamp + CHALLENGE_PERIOD + 1);
        challengeV2.resolveChallenge(claimId);

        vm.expectRevert(
            abi.encodeWithSelector(EMETChallengeV2.ChallengeAlreadyResolved.selector, claimId)
        );
        challengeV2.resolveChallenge(claimId);
    }
}
