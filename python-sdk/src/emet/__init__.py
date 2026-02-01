"""EMET Protocol Python SDK — trustless claim verification on Base."""

from emet.client import EMETClient
from emet.types import Claim, ClaimStatus, StakeInfo, Challenge, ReputationInfo
from emet.exceptions import (
    EMETError,
    InsufficientStakeError,
    ClaimNotFoundError,
    TransactionFailedError,
    InsufficientBalanceError,
    InsufficientAllowanceError,
)

__version__ = "0.1.0"

__all__ = [
    "EMETClient",
    "Claim",
    "ClaimStatus",
    "StakeInfo",
    "Challenge",
    "ReputationInfo",
    "EMETError",
    "InsufficientStakeError",
    "ClaimNotFoundError",
    "TransactionFailedError",
    "InsufficientBalanceError",
    "InsufficientAllowanceError",
]
