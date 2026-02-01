"""Tests for EMETClient.

These tests verify the client's initialization, address resolution,
utility methods, and error handling — without hitting any RPC.
"""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch

from emet.client import EMETClient, MAX_UINT256
from emet.contracts import (
    EMET_TOKEN_ADDRESS,
    EMET_REGISTRY_ADDRESS,
    EMET_STAKE_ADDRESS,
    EMET_REPUTATION_ADDRESS,
)
from emet.exceptions import (
    InsufficientStakeError,
    ClaimNotFoundError,
    InsufficientBalanceError,
    InsufficientAllowanceError,
)


# A valid private key for testing (DO NOT use with real funds)
TEST_PRIVATE_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
TEST_ADDRESS = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"


class TestClientInit:
    def test_read_only_client(self):
        client = EMETClient(rpc_url="https://mainnet.base.org")
        assert client.address is None

    def test_client_with_key(self):
        client = EMETClient(
            private_key=TEST_PRIVATE_KEY,
            rpc_url="https://mainnet.base.org",
        )
        assert client.address is not None
        assert client.address.startswith("0x")
        # Hardhat account #0
        assert client.address.lower() == TEST_ADDRESS.lower()

    def test_custom_addresses(self):
        custom_token = "0x0000000000000000000000000000000000000001"
        client = EMETClient(
            rpc_url="https://mainnet.base.org",
            token_address=custom_token,
        )
        assert client._token.address.lower() == custom_token.lower()

    def test_w3_property(self):
        client = EMETClient(rpc_url="https://mainnet.base.org")
        assert client.w3 is not None


class TestUtilities:
    def test_to_wei(self):
        assert EMETClient.to_wei(1) == 10**18
        assert EMETClient.to_wei(1000) == 1000 * 10**18
        assert EMETClient.to_wei(0.5) == 5 * 10**17

    def test_from_wei(self):
        assert EMETClient.from_wei(10**18) == 1.0
        assert EMETClient.from_wei(1000 * 10**18) == 1000.0
        assert EMETClient.from_wei(5 * 10**17) == 0.5

    def test_to_from_roundtrip(self):
        for amount in [1, 100, 1000, 0.001, 999.999]:
            wei_amount = EMETClient.to_wei(amount)
            back = EMETClient.from_wei(wei_amount)
            assert abs(back - amount) < 1e-10

    def test_hash_claim(self):
        h1 = EMETClient.hash_claim("The sky is blue")
        h2 = EMETClient.hash_claim("The sky is blue")
        h3 = EMETClient.hash_claim("The sky is red")
        assert h1 == h2  # Deterministic
        assert h1 != h3  # Different text = different hash
        assert len(h1) == 32  # 32 bytes


class TestAddressResolution:
    def test_resolve_with_explicit_address(self):
        client = EMETClient(rpc_url="https://mainnet.base.org")
        addr = "0xdead000000000000000000000000000000000000"
        resolved = client._resolve_address(addr)
        assert resolved.lower() == addr.lower()

    def test_resolve_with_wallet(self):
        client = EMETClient(
            private_key=TEST_PRIVATE_KEY,
            rpc_url="https://mainnet.base.org",
        )
        resolved = client._resolve_address(None)
        assert resolved.lower() == TEST_ADDRESS.lower()

    def test_resolve_no_address_no_wallet(self):
        client = EMETClient(rpc_url="https://mainnet.base.org")
        with pytest.raises(ValueError, match="No address provided"):
            client._resolve_address(None)


class TestSignerRequired:
    def test_require_signer_without_key(self):
        client = EMETClient(rpc_url="https://mainnet.base.org")
        with pytest.raises(Exception, match="No private key"):
            client._require_signer()

    def test_require_signer_with_key(self):
        client = EMETClient(
            private_key=TEST_PRIVATE_KEY,
            rpc_url="https://mainnet.base.org",
        )
        # Should not raise
        client._require_signer()


class TestExceptions:
    def test_insufficient_stake(self):
        err = InsufficientStakeError(100, 1000)
        assert err.provided == 100
        assert err.required == 1000
        assert "100" in str(err)
        assert "1000" in str(err)

    def test_claim_not_found(self):
        err = ClaimNotFoundError(42)
        assert err.claim_id == 42
        assert "42" in str(err)

    def test_insufficient_balance(self):
        err = InsufficientBalanceError(50, 100)
        assert err.balance == 50
        assert err.required == 100

    def test_insufficient_allowance(self):
        err = InsufficientAllowanceError(0, 1000, "0xSpender")
        assert err.spender == "0xSpender"
        assert "approve" in str(err).lower()


class TestContractAddresses:
    """Verify the default contract addresses match the deployed protocol."""

    def test_token_address(self):
        assert EMET_TOKEN_ADDRESS == "0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C"

    def test_registry_address(self):
        assert EMET_REGISTRY_ADDRESS == "0x9D2550eB1Ee613E0f35c70524e1304B26392b0aC"

    def test_stake_address(self):
        assert EMET_STAKE_ADDRESS == "0x63901ED9Fbd8262B4505819E2F39a6145f28Fbf0"

    def test_reputation_address(self):
        assert EMET_REPUTATION_ADDRESS == "0xAb6Aa88faaC77c1d941eE25A81e397a7A6fa3a85"
