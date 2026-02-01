"""Tests for EMET data types."""

import pytest
from emet.types import Claim, ClaimStatus, StakeInfo, ReputationInfo


class TestClaimStatus:
    def test_enum_values(self):
        assert ClaimStatus.ACTIVE == 0
        assert ClaimStatus.CHALLENGED == 1
        assert ClaimStatus.VERIFIED == 2
        assert ClaimStatus.REJECTED == 3

    def test_labels(self):
        assert ClaimStatus.ACTIVE.label == "Active"
        assert ClaimStatus.CHALLENGED.label == "Challenged"
        assert ClaimStatus.VERIFIED.label == "Verified"
        assert ClaimStatus.REJECTED.label == "Rejected"


class TestClaim:
    @pytest.fixture
    def claim(self):
        return Claim(
            claim_id=0,
            claim_hash=b"\x00" * 32,
            evidence_uri="https://example.com/evidence",
            submitter="0x1234567890abcdef1234567890abcdef12345678",
            timestamp=1700000000,
            stake=1000 * 10**18,
            challenge_end=0,
            status=ClaimStatus.ACTIVE,
        )

    def test_is_active(self, claim):
        assert claim.is_active is True
        assert claim.is_challenged is False
        assert claim.is_resolved is False

    def test_is_challenged(self):
        c = Claim(
            claim_id=1,
            claim_hash=b"\x00" * 32,
            evidence_uri="",
            submitter="0x0000000000000000000000000000000000000000",
            timestamp=0,
            stake=0,
            challenge_end=1700100000,
            status=ClaimStatus.CHALLENGED,
        )
        assert c.is_active is False
        assert c.is_challenged is True
        assert c.is_resolved is False

    def test_is_resolved(self):
        verified = Claim(
            claim_id=2,
            claim_hash=b"\x00" * 32,
            evidence_uri="",
            submitter="0x0000000000000000000000000000000000000000",
            timestamp=0,
            stake=0,
            challenge_end=0,
            status=ClaimStatus.VERIFIED,
        )
        rejected = Claim(
            claim_id=3,
            claim_hash=b"\x00" * 32,
            evidence_uri="",
            submitter="0x0000000000000000000000000000000000000000",
            timestamp=0,
            stake=0,
            challenge_end=0,
            status=ClaimStatus.REJECTED,
        )
        assert verified.is_resolved is True
        assert rejected.is_resolved is True

    def test_stake_ether(self, claim):
        assert claim.stake_ether == 1000.0

    def test_frozen(self, claim):
        with pytest.raises(AttributeError):
            claim.claim_id = 99


class TestStakeInfo:
    def test_ratio_normal(self):
        info = StakeInfo(claim_id=0, total_for=3000, total_against=1000)
        assert info.ratio == 3.0

    def test_ratio_zero_against(self):
        info = StakeInfo(claim_id=0, total_for=1000, total_against=0)
        assert info.ratio == float("inf")

    def test_ratio_zero_both(self):
        info = StakeInfo(claim_id=0, total_for=0, total_against=0)
        assert info.ratio == 0.0

    def test_ether_conversion(self):
        info = StakeInfo(
            claim_id=0,
            total_for=500 * 10**18,
            total_against=250 * 10**18,
        )
        assert info.total_for_ether == 500.0
        assert info.total_against_ether == 250.0


class TestReputationInfo:
    def test_creation(self):
        rep = ReputationInfo(
            address="0x1234",
            score=50,
            multiplier=1.5,
            tier="Contributor",
            is_positive=True,
        )
        assert rep.score == 50
        assert rep.multiplier == 1.5
        assert rep.tier == "Contributor"
        assert rep.is_positive is True
