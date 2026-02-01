// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {IEMET} from "./interfaces/IEMET.sol";
import {EMETRegistry} from "./EMETRegistry.sol";

/// @title EMETSignature - Cross-model consensus through co-signing claims
/// @notice Allows multiple agents/addresses to co-sign existing claims using EIP-712 signatures
/// @dev When Clawdei AND Grok both sign a claim, it carries more weight than either alone.
///      Signers can optionally stake EMET as skin-in-the-game. Fully trustless, no admin.
contract EMETSignature {
    // ============ Constants ============

    /// @notice EMET token on Base mainnet
    IEMET public constant EMET = IEMET(0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C);

    /// @notice The claim registry
    EMETRegistry public immutable registry;

    /// @notice EIP-712 domain separator (cached at deploy)
    bytes32 public immutable DOMAIN_SEPARATOR;

    /// @notice EIP-712 typehash for claim signing
    /// @dev SignClaim(uint256 claimId,bytes32 claimHash,address signer)
    bytes32 public constant SIGN_CLAIM_TYPEHASH =
        keccak256("SignClaim(uint256 claimId,bytes32 claimHash,address signer)");

    // ============ State ============

    /// @notice Ordered list of signers per claim
    mapping(uint256 => address[]) internal _claimSigners;

    /// @notice Whether an address has signed a specific claim
    mapping(uint256 => mapping(address => bool)) public hasSigned;

    /// @notice Stake deposited by each signer per claim
    mapping(uint256 => mapping(address => uint256)) public signerStake;

    /// @notice Total stake across all signers for a claim
    mapping(uint256 => uint256) public totalStake;

    /// @notice Whether a signer has withdrawn their stake from a resolved claim
    mapping(uint256 => mapping(address => bool)) public hasWithdrawn;

    // ============ Events ============

    /// @notice Emitted when someone co-signs a claim
    event ClaimSigned(uint256 indexed claimId, address indexed signer, uint256 stake);

    /// @notice Emitted when a signer withdraws their stake from a verified claim
    event StakeWithdrawn(uint256 indexed claimId, address indexed signer, uint256 amount);

    // ============ Errors ============

    error ClaimDoesNotExist(uint256 claimId);
    error ClaimNotSignable(uint256 claimId, EMETRegistry.ClaimStatus status);
    error AlreadySigned(uint256 claimId, address signer);
    error InvalidSignature();
    error SignerMismatch(address recovered, address expected);
    error TransferFailed();
    error ClaimNotResolved(uint256 claimId);
    error NotSigner(uint256 claimId, address account);
    error AlreadyWithdrawn(uint256 claimId, address account);
    error NoStakeToWithdraw();
    error ClaimRejected(uint256 claimId);

    // ============ Constructor ============

    /// @notice Deploy signature contract linked to registry
    /// @param _registry Address of the EMETRegistry contract
    constructor(address _registry) {
        registry = EMETRegistry(_registry);

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256("EMETSignature"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    // ============ External Functions ============

    /// @notice Co-sign an existing claim with an EIP-712 signature
    /// @dev Caller provides an ECDSA signature over the EIP-712 typed data.
    ///      The recovered signer is recorded (allows relayed/meta-tx signing).
    ///      Optionally stake EMET by approving this contract before calling.
    /// @param claimId The claim to co-sign
    /// @param signature 65-byte ECDSA signature (r, s, v) over the claim digest
    function signClaim(uint256 claimId, bytes calldata signature) external {
        _signClaim(claimId, signature, 0);
    }

    /// @notice Co-sign an existing claim with an EIP-712 signature and optional EMET stake
    /// @dev Same as signClaim but with an optional stake amount for skin-in-the-game.
    ///      If claim is rejected, co-signers lose their stake.
    /// @param claimId The claim to co-sign
    /// @param signature 65-byte ECDSA signature (r, s, v) over the claim digest
    /// @param stake Amount of EMET to stake alongside the signature (0 for no stake)
    function signClaimWithStake(uint256 claimId, bytes calldata signature, uint256 stake) external {
        _signClaim(claimId, signature, stake);
    }

    /// @notice Withdraw stake from a verified claim
    /// @dev Only callable after claim is verified. Rejected claims forfeit stakes.
    /// @param claimId The resolved claim
    function withdrawStake(uint256 claimId) external {
        EMETRegistry.Claim memory claim = registry.getClaim(claimId);

        // Must be resolved
        if (
            claim.status != EMETRegistry.ClaimStatus.Verified
                && claim.status != EMETRegistry.ClaimStatus.Rejected
        ) {
            revert ClaimNotResolved(claimId);
        }

        if (!hasSigned[claimId][msg.sender]) {
            revert NotSigner(claimId, msg.sender);
        }
        if (hasWithdrawn[claimId][msg.sender]) {
            revert AlreadyWithdrawn(claimId, msg.sender);
        }

        uint256 staked = signerStake[claimId][msg.sender];
        if (staked == 0) revert NoStakeToWithdraw();

        hasWithdrawn[claimId][msg.sender] = true;

        // Rejected = stake lost (stays in contract as protocol revenue)
        if (claim.status == EMETRegistry.ClaimStatus.Rejected) {
            revert ClaimRejected(claimId);
        }

        // Verified = return stake
        bool success = EMET.transfer(msg.sender, staked);
        if (!success) revert TransferFailed();

        emit StakeWithdrawn(claimId, msg.sender, staked);
    }

    // ============ Internal Functions ============

    /// @notice Core signing logic with optional stake
    function _signClaim(uint256 claimId, bytes calldata signature, uint256 stake) internal {
        // Fetch claim — reverts if nonexistent
        EMETRegistry.Claim memory claim = registry.getClaim(claimId);

        // Only sign active or challenged claims (not resolved ones)
        if (
            claim.status != EMETRegistry.ClaimStatus.Active
                && claim.status != EMETRegistry.ClaimStatus.Challenged
        ) {
            revert ClaimNotSignable(claimId, claim.status);
        }

        // Recover signer from EIP-712 signature
        address signer = _recoverSigner(claimId, claim.claimHash, signature);

        // Prevent double-signing
        if (hasSigned[claimId][signer]) {
            revert AlreadySigned(claimId, signer);
        }

        // Record signature
        hasSigned[claimId][signer] = true;
        _claimSigners[claimId].push(signer);

        // Handle optional stake
        if (stake > 0) {
            bool success = EMET.transferFrom(msg.sender, address(this), stake);
            if (!success) revert TransferFailed();

            signerStake[claimId][signer] = stake;
            totalStake[claimId] += stake;
        }

        emit ClaimSigned(claimId, signer, stake);
    }

    /// @notice Recover the EIP-712 signer from a signature
    /// @param claimId The claim ID being signed
    /// @param claimHash The claim hash from the registry
    /// @param signature 65-byte ECDSA signature
    /// @return signer The recovered address
    function _recoverSigner(uint256 claimId, bytes32 claimHash, bytes calldata signature)
        internal
        view
        returns (address signer)
    {
        if (signature.length != 65) revert InvalidSignature();

        // Build EIP-712 struct hash
        bytes32 structHash =
            keccak256(abi.encode(SIGN_CLAIM_TYPEHASH, claimId, claimHash, msg.sender));

        // Build final digest
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        // Split signature
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 0x20))
            v := byte(0, calldataload(add(signature.offset, 0x40)))
        }

        // Normalize v
        if (v < 27) v += 27;
        if (v != 27 && v != 28) revert InvalidSignature();

        // Prevent signature malleability (EIP-2)
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            revert InvalidSignature();
        }

        signer = ecrecover(digest, v, r, s);
        if (signer == address(0)) revert InvalidSignature();

        // The signer must match the caller (prevents frontrunning with someone else's sig)
        if (signer != msg.sender) {
            revert SignerMismatch(signer, msg.sender);
        }
    }

    // ============ View Functions ============

    /// @notice Get all co-signers for a claim
    /// @param claimId The claim ID
    /// @return signers Array of addresses who have signed
    function getSigners(uint256 claimId) external view returns (address[] memory signers) {
        return _claimSigners[claimId];
    }

    /// @notice Get the number of co-signers for a claim
    /// @param claimId The claim ID
    /// @return count Number of signers
    function getSignerCount(uint256 claimId) external view returns (uint256 count) {
        return _claimSigners[claimId].length;
    }

    /// @notice Get the stake a signer has on a claim
    /// @param claimId The claim ID
    /// @param signer The signer address
    /// @return stake Amount staked
    function getSignerStake(uint256 claimId, address signer)
        external
        view
        returns (uint256 stake)
    {
        return signerStake[claimId][signer];
    }

    /// @notice Build the EIP-712 digest for a claim (for off-chain signing)
    /// @dev Call this to get the exact hash that must be signed
    /// @param claimId The claim ID to sign
    /// @param signer The address that will sign
    /// @return digest The EIP-712 digest to sign
    function getDigest(uint256 claimId, address signer) external view returns (bytes32 digest) {
        EMETRegistry.Claim memory claim = registry.getClaim(claimId);

        bytes32 structHash =
            keccak256(abi.encode(SIGN_CLAIM_TYPEHASH, claimId, claim.claimHash, signer));

        digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
    }
}
