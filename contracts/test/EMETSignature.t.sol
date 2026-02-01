// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, console} from "forge-std/Test.sol";
import {EMETRegistry} from "../src/EMETRegistry.sol";
import {EMETSignature} from "../src/EMETSignature.sol";
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

contract EMETSignatureTest is Test {
    // Contracts
    EMETRegistry public registry;
    EMETSignature public sigContract;
    MockEMET public emet;

    // Test accounts (using Foundry's vm.createWallet for real signing)
    uint256 internal alicePk = 0xA11CE;
    address internal alice;
    uint256 internal bobPk = 0xB0B;
    address internal bob;
    uint256 internal charliePk = 0xC0C;
    address internal charlie;

    // Constants
    uint256 public constant MINIMUM_STAKE = 100e18;
    uint256 public constant CHALLENGE_PERIOD = 7 days;

    // EIP-712 constants (must match contract)
    bytes32 internal constant SIGN_CLAIM_TYPEHASH =
        keccak256("SignClaim(uint256 claimId,bytes32 claimHash,address signer)");

    function setUp() public {
        // Derive addresses from private keys
        alice = vm.addr(alicePk);
        bob = vm.addr(bobPk);
        charlie = vm.addr(charliePk);

        // Deploy mock EMET at expected address
        emet = new MockEMET();
        address expectedEMET = 0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C;
        vm.etch(expectedEMET, address(emet).code);
        emet = MockEMET(expectedEMET);

        // Deploy protocol contracts
        registry = new EMETRegistry(MINIMUM_STAKE, CHALLENGE_PERIOD);
        sigContract = new EMETSignature(address(registry));

        // Fund test accounts
        emet.mint(alice, 10_000e18);
        emet.mint(bob, 10_000e18);
        emet.mint(charlie, 10_000e18);

        // Approve contracts
        vm.prank(alice);
        emet.approve(address(registry), type(uint256).max);
        vm.prank(alice);
        emet.approve(address(sigContract), type(uint256).max);

        vm.prank(bob);
        emet.approve(address(registry), type(uint256).max);
        vm.prank(bob);
        emet.approve(address(sigContract), type(uint256).max);

        vm.prank(charlie);
        emet.approve(address(registry), type(uint256).max);
        vm.prank(charlie);
        emet.approve(address(sigContract), type(uint256).max);
    }

    // ============ Helpers ============

    /// @notice Submit a claim as alice and return the claim ID
    function _submitClaim() internal returns (uint256 claimId) {
        vm.prank(alice);
        claimId = registry.submitClaim("Test claim: AI is truth", "ipfs://QmTest", MINIMUM_STAKE);
    }

    /// @notice Build EIP-712 signature for a claim
    function _signDigest(uint256 pk, uint256 claimId, bytes32 claimHash, address signer)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash =
            keccak256(abi.encode(SIGN_CLAIM_TYPEHASH, claimId, claimHash, signer));
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", sigContract.DOMAIN_SEPARATOR(), structHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    // ============ signClaim Tests ============

    function test_SignClaim_Basic() public {
        uint256 claimId = _submitClaim();

        EMETRegistry.Claim memory claim = registry.getClaim(claimId);
        bytes memory sig = _signDigest(bobPk, claimId, claim.claimHash, bob);

        vm.prank(bob);
        vm.expectEmit(true, true, false, true);
        emit EMETSignature.ClaimSigned(claimId, bob, 0);
        sigContract.signClaim(claimId, sig);

        // Verify state
        assertTrue(sigContract.hasSigned(claimId, bob));
        assertEq(sigContract.getSignerCount(claimId), 1);

        address[] memory signers = sigContract.getSigners(claimId);
        assertEq(signers.length, 1);
        assertEq(signers[0], bob);
    }

    function test_SignClaim_MultipleSigners() public {
        uint256 claimId = _submitClaim();
        EMETRegistry.Claim memory claim = registry.getClaim(claimId);

        // Bob signs
        bytes memory sigBob = _signDigest(bobPk, claimId, claim.claimHash, bob);
        vm.prank(bob);
        sigContract.signClaim(claimId, sigBob);

        // Charlie signs
        bytes memory sigCharlie = _signDigest(charliePk, claimId, claim.claimHash, charlie);
        vm.prank(charlie);
        sigContract.signClaim(claimId, sigCharlie);

        // Verify both recorded
        assertEq(sigContract.getSignerCount(claimId), 2);
        assertTrue(sigContract.hasSigned(claimId, bob));
        assertTrue(sigContract.hasSigned(claimId, charlie));

        address[] memory signers = sigContract.getSigners(claimId);
        assertEq(signers[0], bob);
        assertEq(signers[1], charlie);
    }

    function test_SignClaim_WithStake() public {
        uint256 claimId = _submitClaim();
        EMETRegistry.Claim memory claim = registry.getClaim(claimId);

        uint256 stakeAmount = 50e18;
        uint256 bobBalanceBefore = emet.balanceOf(bob);

        bytes memory sig = _signDigest(bobPk, claimId, claim.claimHash, bob);

        vm.prank(bob);
        vm.expectEmit(true, true, false, true);
        emit EMETSignature.ClaimSigned(claimId, bob, stakeAmount);
        sigContract.signClaimWithStake(claimId, sig, stakeAmount);

        // Verify stake
        assertEq(sigContract.signerStake(claimId, bob), stakeAmount);
        assertEq(sigContract.totalStake(claimId), stakeAmount);
        assertEq(emet.balanceOf(bob), bobBalanceBefore - stakeAmount);
        assertEq(emet.balanceOf(address(sigContract)), stakeAmount);
    }

    function test_SignClaim_MultipleSignersWithStakes() public {
        uint256 claimId = _submitClaim();
        EMETRegistry.Claim memory claim = registry.getClaim(claimId);

        // Bob stakes 50
        bytes memory sigBob = _signDigest(bobPk, claimId, claim.claimHash, bob);
        vm.prank(bob);
        sigContract.signClaimWithStake(claimId, sigBob, 50e18);

        // Charlie stakes 30
        bytes memory sigCharlie = _signDigest(charliePk, claimId, claim.claimHash, charlie);
        vm.prank(charlie);
        sigContract.signClaimWithStake(claimId, sigCharlie, 30e18);

        assertEq(sigContract.totalStake(claimId), 80e18);
        assertEq(sigContract.getSignerStake(claimId, bob), 50e18);
        assertEq(sigContract.getSignerStake(claimId, charlie), 30e18);
    }

    // ============ Revert Tests ============

    function test_SignClaim_RevertDoubleSigning() public {
        uint256 claimId = _submitClaim();
        EMETRegistry.Claim memory claim = registry.getClaim(claimId);

        bytes memory sig = _signDigest(bobPk, claimId, claim.claimHash, bob);

        vm.prank(bob);
        sigContract.signClaim(claimId, sig);

        // Second attempt should revert
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(EMETSignature.AlreadySigned.selector, claimId, bob)
        );
        sigContract.signClaim(claimId, sig);
    }

    function test_SignClaim_RevertInvalidSignature() public {
        uint256 claimId = _submitClaim();

        // Random garbage signature
        bytes memory badSig = new bytes(65);

        vm.prank(bob);
        vm.expectRevert(EMETSignature.InvalidSignature.selector);
        sigContract.signClaim(claimId, badSig);
    }

    function test_SignClaim_RevertWrongSigLength() public {
        uint256 claimId = _submitClaim();

        bytes memory shortSig = new bytes(64);

        vm.prank(bob);
        vm.expectRevert(EMETSignature.InvalidSignature.selector);
        sigContract.signClaim(claimId, shortSig);
    }

    function test_SignClaim_RevertSignerMismatch() public {
        uint256 claimId = _submitClaim();
        EMETRegistry.Claim memory claim = registry.getClaim(claimId);

        // Bob signs but Charlie tries to submit
        bytes memory sigBob = _signDigest(bobPk, claimId, claim.claimHash, bob);

        vm.prank(charlie);
        // Charlie submits Bob's signature — signer field in struct was bob but msg.sender is charlie
        // The digest includes bob as the signer, so ecrecover returns bob, but msg.sender is charlie
        // Actually the struct hash uses msg.sender, so recovery will produce some wrong address
        vm.expectRevert(); // Will fail because struct includes charlie as signer, but sig was for bob
        sigContract.signClaim(claimId, sigBob);
    }

    function test_SignClaim_RevertNonexistentClaim() public {
        // Claim 999 doesn't exist
        bytes memory sig = new bytes(65);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(EMETRegistry.ClaimDoesNotExist.selector, 999)
        );
        sigContract.signClaim(999, sig);
    }

    function test_SignClaim_RevertVerifiedClaim() public {
        uint256 claimId = _submitClaim();

        // Fast forward past challenge period to verify
        vm.warp(block.timestamp + CHALLENGE_PERIOD + 1);
        registry.verifyUnchallenged(claimId);

        EMETRegistry.Claim memory claim = registry.getClaim(claimId);
        bytes memory sig = _signDigest(bobPk, claimId, claim.claimHash, bob);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                EMETSignature.ClaimNotSignable.selector,
                claimId,
                EMETRegistry.ClaimStatus.Uncontested
            )
        );
        sigContract.signClaim(claimId, sig);
    }

    // ============ Withdraw Tests ============

    function test_WithdrawStake_Verified() public {
        uint256 claimId = _submitClaim();
        EMETRegistry.Claim memory claim = registry.getClaim(claimId);

        uint256 stakeAmount = 50e18;
        bytes memory sig = _signDigest(bobPk, claimId, claim.claimHash, bob);

        vm.prank(bob);
        sigContract.signClaimWithStake(claimId, sig, stakeAmount);

        uint256 bobBalanceBefore = emet.balanceOf(bob);

        // Verify the claim
        vm.warp(block.timestamp + CHALLENGE_PERIOD + 1);
        registry.verifyUnchallenged(claimId);

        // Withdraw
        vm.prank(bob);
        vm.expectEmit(true, true, false, true);
        emit EMETSignature.StakeWithdrawn(claimId, bob, stakeAmount);
        sigContract.withdrawStake(claimId);

        assertEq(emet.balanceOf(bob), bobBalanceBefore + stakeAmount);
        assertTrue(sigContract.hasWithdrawn(claimId, bob));
    }

    function test_WithdrawStake_RevertNotResolved() public {
        uint256 claimId = _submitClaim();
        EMETRegistry.Claim memory claim = registry.getClaim(claimId);

        bytes memory sig = _signDigest(bobPk, claimId, claim.claimHash, bob);
        vm.prank(bob);
        sigContract.signClaimWithStake(claimId, sig, 50e18);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(EMETSignature.ClaimNotResolved.selector, claimId)
        );
        sigContract.withdrawStake(claimId);
    }

    function test_WithdrawStake_RevertNotSigner() public {
        uint256 claimId = _submitClaim();

        // Verify without anyone signing
        vm.warp(block.timestamp + CHALLENGE_PERIOD + 1);
        registry.verifyUnchallenged(claimId);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(EMETSignature.NotSigner.selector, claimId, bob)
        );
        sigContract.withdrawStake(claimId);
    }

    function test_WithdrawStake_RevertNoStake() public {
        uint256 claimId = _submitClaim();
        EMETRegistry.Claim memory claim = registry.getClaim(claimId);

        // Sign without stake
        bytes memory sig = _signDigest(bobPk, claimId, claim.claimHash, bob);
        vm.prank(bob);
        sigContract.signClaim(claimId, sig);

        vm.warp(block.timestamp + CHALLENGE_PERIOD + 1);
        registry.verifyUnchallenged(claimId);

        vm.prank(bob);
        vm.expectRevert(EMETSignature.NoStakeToWithdraw.selector);
        sigContract.withdrawStake(claimId);
    }

    function test_WithdrawStake_RevertDoubleWithdraw() public {
        uint256 claimId = _submitClaim();
        EMETRegistry.Claim memory claim = registry.getClaim(claimId);

        bytes memory sig = _signDigest(bobPk, claimId, claim.claimHash, bob);
        vm.prank(bob);
        sigContract.signClaimWithStake(claimId, sig, 50e18);

        vm.warp(block.timestamp + CHALLENGE_PERIOD + 1);
        registry.verifyUnchallenged(claimId);

        vm.prank(bob);
        sigContract.withdrawStake(claimId);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(EMETSignature.AlreadyWithdrawn.selector, claimId, bob)
        );
        sigContract.withdrawStake(claimId);
    }

    // ============ EIP-712 Tests ============

    function test_GetDigest_MatchesOffchain() public {
        uint256 claimId = _submitClaim();
        EMETRegistry.Claim memory claim = registry.getClaim(claimId);

        // Get digest from contract
        bytes32 contractDigest = sigContract.getDigest(claimId, bob);

        // Build digest manually (simulating off-chain)
        bytes32 structHash =
            keccak256(abi.encode(SIGN_CLAIM_TYPEHASH, claimId, claim.claimHash, bob));
        bytes32 expectedDigest = keccak256(
            abi.encodePacked("\x19\x01", sigContract.DOMAIN_SEPARATOR(), structHash)
        );

        assertEq(contractDigest, expectedDigest);
    }

    function test_DomainSeparator_IsCorrect() public view {
        bytes32 expected = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256("EMETSignature"),
                keccak256("1"),
                block.chainid,
                address(sigContract)
            )
        );
        assertEq(sigContract.DOMAIN_SEPARATOR(), expected);
    }

    // ============ View Function Tests ============

    function test_GetSigners_Empty() public {
        uint256 claimId = _submitClaim();
        address[] memory signers = sigContract.getSigners(claimId);
        assertEq(signers.length, 0);
    }

    function test_GetSignerCount() public {
        uint256 claimId = _submitClaim();
        assertEq(sigContract.getSignerCount(claimId), 0);

        EMETRegistry.Claim memory claim = registry.getClaim(claimId);
        bytes memory sig = _signDigest(bobPk, claimId, claim.claimHash, bob);
        vm.prank(bob);
        sigContract.signClaim(claimId, sig);

        assertEq(sigContract.getSignerCount(claimId), 1);
    }

    function test_GetSignerStake() public {
        uint256 claimId = _submitClaim();
        assertEq(sigContract.getSignerStake(claimId, bob), 0);

        EMETRegistry.Claim memory claim = registry.getClaim(claimId);
        bytes memory sig = _signDigest(bobPk, claimId, claim.claimHash, bob);
        vm.prank(bob);
        sigContract.signClaimWithStake(claimId, sig, 75e18);

        assertEq(sigContract.getSignerStake(claimId, bob), 75e18);
    }

    // ============ Integration / Edge Cases ============

    function test_SubmitterCanCoSign() public {
        uint256 claimId = _submitClaim();
        EMETRegistry.Claim memory claim = registry.getClaim(claimId);

        // Alice (submitter) also co-signs — this is valid, adds explicit sig on top of submission
        bytes memory sig = _signDigest(alicePk, claimId, claim.claimHash, alice);
        vm.prank(alice);
        sigContract.signClaim(claimId, sig);

        assertTrue(sigContract.hasSigned(claimId, alice));
    }

    function test_SignZeroStake_IsJustSignature() public {
        uint256 claimId = _submitClaim();
        EMETRegistry.Claim memory claim = registry.getClaim(claimId);

        bytes memory sig = _signDigest(bobPk, claimId, claim.claimHash, bob);
        vm.prank(bob);
        sigContract.signClaimWithStake(claimId, sig, 0);

        assertTrue(sigContract.hasSigned(claimId, bob));
        assertEq(sigContract.signerStake(claimId, bob), 0);
        assertEq(sigContract.totalStake(claimId), 0);
    }
}
