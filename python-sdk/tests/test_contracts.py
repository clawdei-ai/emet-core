"""Tests for contract ABI definitions.

Verify that the ABIs have the expected function signatures.
"""

import pytest

from emet.contracts import (
    EMET_TOKEN_ABI,
    EMET_REGISTRY_ABI,
    EMET_STAKE_ABI,
    EMET_REPUTATION_ABI,
)


def _get_function_names(abi: list[dict]) -> set[str]:
    """Extract function names from an ABI."""
    return {
        item["name"]
        for item in abi
        if item.get("type") == "function"
    }


def _get_event_names(abi: list[dict]) -> set[str]:
    """Extract event names from an ABI."""
    return {
        item["name"]
        for item in abi
        if item.get("type") == "event"
    }


class TestTokenABI:
    def test_has_erc20_functions(self):
        fns = _get_function_names(EMET_TOKEN_ABI)
        assert "balanceOf" in fns
        assert "transfer" in fns
        assert "transferFrom" in fns
        assert "approve" in fns
        assert "allowance" in fns

    def test_balance_of_signature(self):
        fn = next(f for f in EMET_TOKEN_ABI if f.get("name") == "balanceOf")
        assert len(fn["inputs"]) == 1
        assert fn["inputs"][0]["type"] == "address"
        assert fn["outputs"][0]["type"] == "uint256"
        assert fn["stateMutability"] == "view"


class TestRegistryABI:
    def test_has_core_functions(self):
        fns = _get_function_names(EMET_REGISTRY_ABI)
        assert "submitClaim" in fns
        assert "getClaim" in fns
        assert "claimCount" in fns
        assert "minimumStake" in fns
        assert "challengePeriod" in fns
        assert "canVerifyUnchallenged" in fns
        assert "verifyUnchallenged" in fns

    def test_submit_claim_signature(self):
        fn = next(f for f in EMET_REGISTRY_ABI if f.get("name") == "submitClaim")
        input_types = [i["type"] for i in fn["inputs"]]
        assert input_types == ["bytes32", "string", "uint256"]
        assert fn["outputs"][0]["type"] == "uint256"

    def test_get_claim_returns_struct(self):
        fn = next(f for f in EMET_REGISTRY_ABI if f.get("name") == "getClaim")
        assert fn["outputs"][0]["type"] == "tuple"
        component_names = [c["name"] for c in fn["outputs"][0]["components"]]
        assert "claimHash" in component_names
        assert "submitter" in component_names
        assert "stake" in component_names
        assert "status" in component_names

    def test_has_events(self):
        events = _get_event_names(EMET_REGISTRY_ABI)
        assert "ClaimSubmitted" in events
        assert "ClaimStatusChanged" in events


class TestStakeABI:
    def test_has_core_functions(self):
        fns = _get_function_names(EMET_STAKE_ABI)
        assert "stakeFor" in fns
        assert "withdraw" in fns
        assert "getStakeTotals" in fns
        assert "getUserStakes" in fns
        assert "calculatePayout" in fns

    def test_stake_for_signature(self):
        fn = next(f for f in EMET_STAKE_ABI if f.get("name") == "stakeFor")
        input_types = [i["type"] for i in fn["inputs"]]
        assert input_types == ["uint256", "uint256"]

    def test_has_events(self):
        events = _get_event_names(EMET_STAKE_ABI)
        assert "Staked" in events
        assert "Withdrawn" in events


class TestReputationABI:
    def test_has_core_functions(self):
        fns = _get_function_names(EMET_REPUTATION_ABI)
        assert "getReputation" in fns
        assert "getReputationMultiplier" in fns
        assert "hasPositiveReputation" in fns
        assert "getReputationTier" in fns

    def test_get_reputation_returns_int256(self):
        fn = next(f for f in EMET_REPUTATION_ABI if f.get("name") == "getReputation")
        assert fn["outputs"][0]["type"] == "int256"

    def test_has_events(self):
        events = _get_event_names(EMET_REPUTATION_ABI)
        assert "ReputationUpdated" in events
