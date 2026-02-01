"""Data types for the EMET SDK."""

from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum


class ClaimStatus(IntEnum):
    """Claim lifecycle status, mirrors the on-chain enum."""

    ACTIVE = 0  # Open for challenges
    CHALLENGED = 1  # Currently disputed
    VERIFIED = 2  # Resolved in favor of claim
    REJECTED = 3  # Resolved against claim

    @property
    def label(self) -> str:
        return self.name.capitalize()


@dataclass(frozen=True, slots=True)
class Claim:
    """A claim from the EMETRegistry."""

    claim_id: int
    claim_hash: bytes
    evidence_uri: str
    submitter: str
    timestamp: int
    stake: int
    challenge_end: int
    status: ClaimStatus

    @property
    def is_active(self) -> bool:
        return self.status == ClaimStatus.ACTIVE

    @property
    def is_challenged(self) -> bool:
        return self.status == ClaimStatus.CHALLENGED

    @property
    def is_resolved(self) -> bool:
        return self.status in (ClaimStatus.VERIFIED, ClaimStatus.REJECTED)

    @property
    def stake_ether(self) -> float:
        """Stake in human-readable EMET (18 decimals)."""
        return self.stake / 1e18


@dataclass(frozen=True, slots=True)
class StakeInfo:
    """Stake totals for a claim."""

    claim_id: int
    total_for: int
    total_against: int

    @property
    def total_for_ether(self) -> float:
        return self.total_for / 1e18

    @property
    def total_against_ether(self) -> float:
        return self.total_against / 1e18

    @property
    def ratio(self) -> float:
        """Ratio of for:against. >1 means claim is winning."""
        if self.total_against == 0:
            return float("inf") if self.total_for > 0 else 0.0
        return self.total_for / self.total_against


@dataclass(frozen=True, slots=True)
class Challenge:
    """A challenge against a claim."""

    claim_id: int
    challenger: str
    stake: int
    start_time: int
    resolved: bool

    @property
    def stake_ether(self) -> float:
        return self.stake / 1e18


@dataclass(frozen=True, slots=True)
class ReputationInfo:
    """Reputation data for an address."""

    address: str
    score: int
    multiplier: float  # 1.0x – 2.0x
    tier: str
    is_positive: bool
