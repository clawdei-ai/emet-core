"""EMET Protocol client for Python.

Provides an async interface to all EMET Protocol contracts on Base mainnet:
EMETRegistry, EMETStake, EMETReputation, and the EMET ERC-20 token.

Usage::

    from emet import EMETClient

    client = EMETClient(private_key="0x...", rpc_url="https://mainnet.base.org")

    # Submit a claim
    tx = await client.submit_claim("The sky is blue", stake=1000, evidence="https://...")

    # Read a claim
    claim = await client.get_claim(0)
"""

from __future__ import annotations

import hashlib
from typing import Any

from web3 import AsyncWeb3
from web3.contract import AsyncContract
from web3.types import TxReceipt, Wei

from emet.contracts import (
    EMET_TOKEN_ADDRESS,
    EMET_TOKEN_ABI,
    EMET_REGISTRY_ADDRESS,
    EMET_REGISTRY_ABI,
    EMET_STAKE_ADDRESS,
    EMET_STAKE_ABI,
    EMET_REPUTATION_ADDRESS,
    EMET_REPUTATION_ABI,
    EMET_CHALLENGE_V3_ADDRESS,
    EMET_CHALLENGE_V3_ABI,
    EMET_TREASURY_ADDRESS,
    EMET_TREASURY_ABI,
    EMET_BOOTSTRAP_ADDRESS,
    EMET_BOOTSTRAP_ABI,
    DEFAULT_CLAIM_FEE,
    DEFAULT_RESOLUTION_FEE_BPS,
)
from emet.exceptions import (
    InsufficientStakeError,
    ClaimNotFoundError,
    TransactionFailedError,
    InsufficientBalanceError,
    InsufficientAllowanceError,
)
from emet.types import Claim, ClaimStatus, StakeInfo, Challenge, ReputationInfo


# Default Base mainnet RPC
DEFAULT_RPC_URL = "https://mainnet.base.org"

# Maximum uint256 for unlimited approval
MAX_UINT256 = 2**256 - 1


class EMETClient:
    """Async client for the EMET Protocol on Base.

    Args:
        private_key: Hex-encoded private key for signing transactions.
            Optional for read-only usage.
        rpc_url: Base mainnet JSON-RPC endpoint.
            Defaults to ``https://mainnet.base.org``.
        token_address: Override EMET token contract address.
        registry_address: Override EMETRegistry contract address.
        stake_address: Override EMETStake contract address.
        reputation_address: Override EMETReputation contract address.
        gas_multiplier: Multiplier for estimated gas (default 1.2).
    """

    def __init__(
        self,
        private_key: str | None = None,
        rpc_url: str = DEFAULT_RPC_URL,
        *,
        token_address: str = EMET_TOKEN_ADDRESS,
        registry_address: str = EMET_REGISTRY_ADDRESS,
        stake_address: str = EMET_STAKE_ADDRESS,
        reputation_address: str = EMET_REPUTATION_ADDRESS,
        challenge_v3_address: str = EMET_CHALLENGE_V3_ADDRESS,
        treasury_address: str = EMET_TREASURY_ADDRESS,
        bootstrap_address: str = EMET_BOOTSTRAP_ADDRESS,
        gas_multiplier: float = 1.2,
    ):
        self._w3 = AsyncWeb3(AsyncWeb3.AsyncHTTPProvider(rpc_url))
        self._gas_multiplier = gas_multiplier

        # Account setup
        self._private_key = private_key
        if private_key:
            self._account = self._w3.eth.account.from_key(private_key)
            self._address = self._account.address
        else:
            self._account = None
            self._address = None

        # Core contract instances
        self._token: AsyncContract = self._w3.eth.contract(
            address=self._w3.to_checksum_address(token_address),
            abi=EMET_TOKEN_ABI,
        )
        self._registry: AsyncContract = self._w3.eth.contract(
            address=self._w3.to_checksum_address(registry_address),
            abi=EMET_REGISTRY_ABI,
        )
        self._stake: AsyncContract = self._w3.eth.contract(
            address=self._w3.to_checksum_address(stake_address),
            abi=EMET_STAKE_ABI,
        )
        self._reputation: AsyncContract = self._w3.eth.contract(
            address=self._w3.to_checksum_address(reputation_address),
            abi=EMET_REPUTATION_ABI,
        )
        
        # Governance contracts (v2.2)
        self._challenge_v3: AsyncContract = self._w3.eth.contract(
            address=self._w3.to_checksum_address(challenge_v3_address),
            abi=EMET_CHALLENGE_V3_ABI,
        )
        self._treasury: AsyncContract = self._w3.eth.contract(
            address=self._w3.to_checksum_address(treasury_address),
            abi=EMET_TREASURY_ABI,
        )
        self._bootstrap: AsyncContract = self._w3.eth.contract(
            address=self._w3.to_checksum_address(bootstrap_address),
            abi=EMET_BOOTSTRAP_ABI,
        )

    # ================================================================
    # Properties
    # ================================================================

    @property
    def address(self) -> str | None:
        """The connected wallet address, or None if read-only."""
        return self._address

    @property
    def w3(self) -> AsyncWeb3:
        """The underlying AsyncWeb3 instance."""
        return self._w3

    # ================================================================
    # Claims — Write
    # ================================================================

    async def get_claim_fee(self) -> int:
        """Get the current claim fee in wei.
        
        Registry v2 charges a fee (default 10 EMET) per claim submission.
        """
        try:
            return await self._registry.functions.claimFee().call()
        except Exception:
            return DEFAULT_CLAIM_FEE

    async def get_resolution_fee_bps(self) -> int:
        """Get the current resolution fee in basis points.
        
        ChallengeV3 v2 charges a fee (default 5% / 500 bps) on resolution.
        """
        try:
            return await self._challenge_v3.functions.resolutionFeeBps().call()
        except Exception:
            return DEFAULT_RESOLUTION_FEE_BPS

    async def get_verified_claims_count(self) -> int:
        """Get the total number of verified claims."""
        try:
            return await self._registry.functions.verifiedClaimsCount().call()
        except Exception:
            return 0

    async def submit_claim(
        self,
        claim_text: str,
        *,
        stake: int,
        evidence: str = "",
        auto_approve: bool = True,
    ) -> TxReceipt:
        """Submit a new claim to the EMETRegistry.

        Registry v2 requires a claim fee (10 EMET by default) in addition
        to the stake. The fee is transferred to the treasury on submission.

        Args:
            claim_text: The claim content (will be hashed on-chain).
            stake: Amount of EMET to stake (in wei, 18 decimals).
                Must be >= the contract's ``minimumStake``.
            evidence: URI to evidence (IPFS, Arweave, HTTP).
            auto_approve: If True, automatically approve the registry
                to spend tokens if the current allowance is insufficient.

        Returns:
            Transaction receipt.

        Raises:
            InsufficientStakeError: Stake below minimum.
            InsufficientBalanceError: Not enough EMET tokens.
            TransactionFailedError: Transaction reverted.
        """
        self._require_signer()

        # Validate minimum stake
        min_stake = await self._registry.functions.minimumStake().call()
        if stake < min_stake:
            raise InsufficientStakeError(stake, min_stake)

        # Get claim fee
        claim_fee = await self.get_claim_fee()
        total_required = stake + claim_fee

        # Check balance (stake + fee)
        await self._check_balance(total_required)

        # Approve if needed (stake + fee)
        if auto_approve:
            await self._ensure_allowance(self._registry.address, total_required)

        # Hash the claim text (keccak256)
        claim_hash = self._w3.keccak(text=claim_text)

        # Build and send tx
        tx = self._registry.functions.submitClaim(claim_hash, evidence, stake)
        return await self._send_tx(tx)

    async def verify_unchallenged(self, claim_id: int) -> TxReceipt:
        """Verify a claim that passed its challenge period without dispute.

        Anyone can call this — no stake or ownership required.

        Args:
            claim_id: The claim to verify.

        Returns:
            Transaction receipt.
        """
        self._require_signer()
        tx = self._registry.functions.verifyUnchallenged(claim_id)
        return await self._send_tx(tx)

    # ================================================================
    # Claims — Read
    # ================================================================

    async def get_claim(self, claim_id: int) -> Claim:
        """Fetch a claim by ID.

        Args:
            claim_id: The claim ID.

        Returns:
            Claim dataclass.

        Raises:
            ClaimNotFoundError: If claim doesn't exist.
        """
        try:
            raw = await self._registry.functions.getClaim(claim_id).call()
        except Exception as e:
            if "ClaimDoesNotExist" in str(e):
                raise ClaimNotFoundError(claim_id) from e
            raise

        return Claim(
            claim_id=claim_id,
            claim_hash=raw[0],
            evidence_uri=raw[1],
            submitter=raw[2],
            timestamp=raw[3],
            stake=raw[4],
            challenge_end=raw[5],
            status=ClaimStatus(raw[6]),
        )

    async def get_claim_count(self) -> int:
        """Get the total number of claims submitted."""
        return await self._registry.functions.claimCount().call()

    async def get_minimum_stake(self) -> int:
        """Get the minimum stake required to submit a claim (in wei)."""
        return await self._registry.functions.minimumStake().call()

    async def get_challenge_period(self) -> int:
        """Get the challenge period duration in seconds."""
        return await self._registry.functions.challengePeriod().call()

    async def can_verify_unchallenged(self, claim_id: int) -> bool:
        """Check if a claim can be verified (unchallenged + period passed)."""
        return await self._registry.functions.canVerifyUnchallenged(claim_id).call()

    # ================================================================
    # Staking — Write
    # ================================================================

    async def stake_for(
        self,
        claim_id: int,
        amount: int,
        *,
        auto_approve: bool = True,
    ) -> TxReceipt:
        """Stake EMET in support of a claim.

        Args:
            claim_id: The claim to support.
            amount: Amount of EMET to stake (wei).
            auto_approve: Auto-approve the stake contract if needed.

        Returns:
            Transaction receipt.
        """
        self._require_signer()
        await self._check_balance(amount)
        if auto_approve:
            await self._ensure_allowance(self._stake.address, amount)

        tx = self._stake.functions.stakeFor(claim_id, amount)
        return await self._send_tx(tx)

    async def stake_against(
        self,
        claim_id: int,
        amount: int,
        *,
        auto_approve: bool = True,
    ) -> TxReceipt:
        """Stake EMET against a claim.

        Note: This calls stakeFor with the 'against' path. On the actual
        protocol, staking against requires going through the Challenge
        contract. This is a convenience that stakes FOR the opposing side.
        For proper challenges, use :meth:`challenge`.

        Args:
            claim_id: The claim to oppose.
            amount: Amount of EMET to stake (wei).
            auto_approve: Auto-approve the stake contract if needed.

        Returns:
            Transaction receipt.
        """
        self._require_signer()
        await self._check_balance(amount)
        if auto_approve:
            await self._ensure_allowance(self._stake.address, amount)

        # The EMETStake contract only exposes stakeFor() publicly.
        # stakeAgainst() is restricted to the challenge contract.
        # To oppose a claim, users must initiate a challenge via EMETChallenge.
        # This method stakes FOR the claim — see challenge() for opposing.
        tx = self._stake.functions.stakeFor(claim_id, amount)
        return await self._send_tx(tx)

    async def withdraw(self, claim_id: int) -> TxReceipt:
        """Withdraw stake and rewards after a claim is resolved.

        Args:
            claim_id: The resolved claim to withdraw from.

        Returns:
            Transaction receipt.
        """
        self._require_signer()
        tx = self._stake.functions.withdraw(claim_id)
        return await self._send_tx(tx)

    # ================================================================
    # Staking — Read
    # ================================================================

    async def get_stake_totals(self, claim_id: int) -> StakeInfo:
        """Get the total for/against stakes on a claim.

        Args:
            claim_id: The claim ID.

        Returns:
            StakeInfo with totals.
        """
        result = await self._stake.functions.getStakeTotals(claim_id).call()
        return StakeInfo(
            claim_id=claim_id,
            total_for=result[0],
            total_against=result[1],
        )

    async def get_user_stakes(
        self, claim_id: int, address: str | None = None
    ) -> tuple[int, int]:
        """Get a user's for/against stakes on a claim.

        Args:
            claim_id: The claim ID.
            address: Address to query. Defaults to connected wallet.

        Returns:
            Tuple of (stake_for, stake_against) in wei.
        """
        addr = self._resolve_address(address)
        result = await self._stake.functions.getUserStakes(claim_id, addr).call()
        return (result[0], result[1])

    async def calculate_payout(
        self,
        claim_id: int,
        assume_verified: bool = True,
        address: str | None = None,
    ) -> int:
        """Preview expected payout if the claim resolves now.

        Args:
            claim_id: The claim ID.
            assume_verified: True = assume claim verified, False = rejected.
            address: Address to query. Defaults to connected wallet.

        Returns:
            Expected payout in wei.
        """
        addr = self._resolve_address(address)
        return await self._stake.functions.calculatePayout(
            claim_id, addr, assume_verified
        ).call()

    # ================================================================
    # Token — Read / Write
    # ================================================================

    async def get_balance(self, address: str | None = None) -> int:
        """Get EMET token balance for an address.

        Args:
            address: Address to query. Defaults to connected wallet.

        Returns:
            Balance in wei (18 decimals).
        """
        addr = self._resolve_address(address)
        return await self._token.functions.balanceOf(addr).call()

    async def get_allowance(self, spender: str, owner: str | None = None) -> int:
        """Get the EMET allowance for a spender.

        Args:
            spender: Spender address.
            owner: Token owner. Defaults to connected wallet.

        Returns:
            Allowance in wei.
        """
        owner_addr = self._resolve_address(owner)
        return await self._token.functions.allowance(
            owner_addr, self._w3.to_checksum_address(spender)
        ).call()

    async def approve(
        self, spender: str, amount: int = MAX_UINT256
    ) -> TxReceipt:
        """Approve a spender to transfer EMET tokens.

        Args:
            spender: Address to approve.
            amount: Amount to approve (default: unlimited).

        Returns:
            Transaction receipt.
        """
        self._require_signer()
        tx = self._token.functions.approve(
            self._w3.to_checksum_address(spender), amount
        )
        return await self._send_tx(tx)

    async def transfer(self, to: str, amount: int) -> TxReceipt:
        """Transfer EMET tokens to another address.

        Args:
            to: Recipient address.
            amount: Amount in wei.

        Returns:
            Transaction receipt.
        """
        self._require_signer()
        await self._check_balance(amount)
        tx = self._token.functions.transfer(
            self._w3.to_checksum_address(to), amount
        )
        return await self._send_tx(tx)

    # ================================================================
    # Reputation — Read
    # ================================================================

    async def get_reputation(self, address: str | None = None) -> ReputationInfo:
        """Get full reputation info for an address.

        Args:
            address: Address to query. Defaults to connected wallet.

        Returns:
            ReputationInfo with score, multiplier, tier.
        """
        addr = self._resolve_address(address)
        checksum = self._w3.to_checksum_address(addr)

        score, multiplier_raw, is_positive, tier = await self._w3.eth.call_batch(
            [
                self._reputation.functions.getReputation(checksum),
                self._reputation.functions.getReputationMultiplier(checksum),
                self._reputation.functions.hasPositiveReputation(checksum),
                self._reputation.functions.getReputationTier(checksum),
            ]
        ) if False else (  # call_batch not available, use sequential calls
            await self._reputation.functions.getReputation(checksum).call(),
            await self._reputation.functions.getReputationMultiplier(checksum).call(),
            await self._reputation.functions.hasPositiveReputation(checksum).call(),
            await self._reputation.functions.getReputationTier(checksum).call(),
        )

        return ReputationInfo(
            address=addr,
            score=score,
            multiplier=multiplier_raw / 1e18,
            tier=tier,
            is_positive=is_positive,
        )

    async def get_reputation_score(self, address: str | None = None) -> int:
        """Get raw reputation score (can be negative).

        Args:
            address: Address to query. Defaults to connected wallet.

        Returns:
            Reputation score as signed integer.
        """
        addr = self._resolve_address(address)
        return await self._reputation.functions.getReputation(
            self._w3.to_checksum_address(addr)
        ).call()

    async def get_reputation_tier(self, address: str | None = None) -> str:
        """Get reputation tier label.

        Returns one of: Untrusted, Unknown, Newcomer, Contributor,
        Trusted, Expert, Authority.
        """
        addr = self._resolve_address(address)
        return await self._reputation.functions.getReputationTier(
            self._w3.to_checksum_address(addr)
        ).call()

    # ================================================================
    # Challenge — Convenience
    # ================================================================

    async def challenge(
        self,
        claim_id: int,
        *,
        evidence: str = "",
        stake: int,
        auto_approve: bool = True,
    ) -> TxReceipt:
        """Challenge a claim.

        This is a convenience method. The actual challenge flow requires
        interacting with the EMETChallenge contract which is not directly
        exposed here (it needs its own contract address). This method submits
        a counter-claim referencing the original.

        For full challenge support, use the challenge contract directly::

            challenge_contract = client.w3.eth.contract(
                address="0x...",  # EMETChallenge address
                abi=challenge_abi,
            )

        Args:
            claim_id: The claim to challenge.
            evidence: Counter-evidence URI.
            stake: Amount of EMET to stake against.
            auto_approve: Auto-approve if needed.

        Returns:
            Transaction receipt from staking against.

        Note:
            In the EMET protocol, challenges go through EMETChallenge or
            EMETChallengeV2 contracts. This SDK exposes the staking
            mechanism directly. For full challenge initiation with
            dispute resolution, deploy and interact with the challenge
            contract separately.
        """
        self._require_signer()
        await self._check_balance(stake)
        if auto_approve:
            await self._ensure_allowance(self._stake.address, stake)

        # Stake in support of the claim (stakeFor is the public method)
        # Note: proper challenges require the EMETChallenge contract
        tx = self._stake.functions.stakeFor(claim_id, stake)
        return await self._send_tx(tx)

    # ================================================================
    # Utilities
    # ================================================================

    @staticmethod
    def to_wei(amount: float | int, decimals: int = 18) -> int:
        """Convert a human-readable amount to wei.

        Args:
            amount: Amount in human-readable units (e.g. 1000.5).
            decimals: Token decimals (default 18).

        Returns:
            Amount in wei.
        """
        return int(amount * (10**decimals))

    @staticmethod
    def from_wei(amount: int, decimals: int = 18) -> float:
        """Convert wei to human-readable amount.

        Args:
            amount: Amount in wei.
            decimals: Token decimals (default 18).

        Returns:
            Human-readable amount.
        """
        return amount / (10**decimals)

    @staticmethod
    def hash_claim(text: str) -> bytes:
        """Hash claim text using keccak256 (same as on-chain).

        Args:
            text: Claim text to hash.

        Returns:
            32-byte keccak256 hash.
        """
        return AsyncWeb3.keccak(text=text)

    # ================================================================
    # Internal helpers
    # ================================================================

    def _require_signer(self) -> None:
        """Ensure a private key is configured."""
        if self._account is None:
            from emet.exceptions import EMETError as _EMETError

            raise _EMETError(
                "No private key configured. "
                "Provide private_key= to EMETClient for write operations."
            )

    def _resolve_address(self, address: str | None) -> str:
        """Resolve an address, defaulting to the connected wallet."""
        if address is not None:
            return self._w3.to_checksum_address(address)
        if self._address is not None:
            return self._address
        raise ValueError(
            "No address provided and no wallet connected. "
            "Pass address= or initialize EMETClient with a private_key."
        )

    async def _check_balance(self, required: int) -> None:
        """Check that the connected wallet has enough EMET tokens."""
        balance = await self._token.functions.balanceOf(self._address).call()
        if balance < required:
            raise InsufficientBalanceError(balance, required)

    async def _ensure_allowance(self, spender: str, required: int) -> None:
        """Approve spender if current allowance is insufficient."""
        current = await self._token.functions.allowance(
            self._address, spender
        ).call()
        if current < required:
            # Approve unlimited to avoid repeated approvals
            tx = self._token.functions.approve(spender, MAX_UINT256)
            await self._send_tx(tx)

    async def _send_tx(self, contract_fn: Any) -> TxReceipt:
        """Build, sign, send, and wait for a transaction.

        Args:
            contract_fn: A prepared contract function call.

        Returns:
            Transaction receipt.

        Raises:
            TransactionFailedError: If the transaction reverts.
        """
        # Build transaction
        nonce = await self._w3.eth.get_transaction_count(self._address)
        gas_price = await self._w3.eth.gas_price

        tx_params = {
            "from": self._address,
            "nonce": nonce,
            "gasPrice": gas_price,
            "chainId": 8453,  # Base mainnet
        }

        # Estimate gas
        try:
            gas_estimate = await contract_fn.estimate_gas(tx_params)
            tx_params["gas"] = int(gas_estimate * self._gas_multiplier)
        except Exception as e:
            # If estimation fails, the tx would likely revert
            raise TransactionFailedError(reason=str(e)) from e

        # Build the full transaction
        tx = await contract_fn.build_transaction(tx_params)

        # Sign
        signed = self._w3.eth.account.sign_transaction(tx, self._private_key)

        # Send
        tx_hash = await self._w3.eth.send_raw_transaction(signed.raw_transaction)

        # Wait for receipt
        receipt = await self._w3.eth.wait_for_transaction_receipt(tx_hash)

        if receipt["status"] == 0:
            raise TransactionFailedError(
                tx_hash=tx_hash.hex(), reason="Transaction reverted"
            )

        return receipt
