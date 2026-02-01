"""Custom exceptions for the EMET SDK."""


class EMETError(Exception):
    """Base exception for all EMET SDK errors."""


class InsufficientStakeError(EMETError):
    """Stake amount is below the contract minimum."""

    def __init__(self, provided: int, required: int):
        self.provided = provided
        self.required = required
        super().__init__(
            f"Insufficient stake: provided {provided}, minimum required {required}"
        )


class ClaimNotFoundError(EMETError):
    """Claim ID does not exist in the registry."""

    def __init__(self, claim_id: int):
        self.claim_id = claim_id
        super().__init__(f"Claim {claim_id} does not exist")


class TransactionFailedError(EMETError):
    """On-chain transaction failed."""

    def __init__(self, tx_hash: str | None = None, reason: str = ""):
        self.tx_hash = tx_hash
        msg = f"Transaction failed"
        if tx_hash:
            msg += f" (tx: {tx_hash})"
        if reason:
            msg += f": {reason}"
        super().__init__(msg)


class InsufficientBalanceError(EMETError):
    """Account does not have enough EMET tokens."""

    def __init__(self, balance: int, required: int):
        self.balance = balance
        self.required = required
        super().__init__(
            f"Insufficient EMET balance: have {balance}, need {required}"
        )


class InsufficientAllowanceError(EMETError):
    """Spender allowance is too low — need to approve first."""

    def __init__(self, allowance: int, required: int, spender: str):
        self.allowance = allowance
        self.required = required
        self.spender = spender
        super().__init__(
            f"Insufficient allowance for {spender}: "
            f"approved {allowance}, need {required}. Call approve() first."
        )
