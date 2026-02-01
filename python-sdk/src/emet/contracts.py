"""Contract addresses and ABIs for the EMET Protocol on Base mainnet.

ABIs are derived from the Solidity sources in contracts/src/.
Only the functions used by the SDK are included.
"""

# ============ Addresses (Base mainnet) ============

EMET_TOKEN_ADDRESS = "0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C"
EMET_REGISTRY_ADDRESS = "0x9D2550eB1Ee613E0f35c70524e1304B26392b0aC"
EMET_STAKE_ADDRESS = "0x63901ED9Fbd8262B4505819E2F39a6145f28Fbf0"
EMET_REPUTATION_ADDRESS = "0xAb6Aa88faaC77c1d941eE25A81e397a7A6fa3a85"


# ============ ABIs ============

# IEMET (ERC-20 token interface)
EMET_TOKEN_ABI = [
    {
        "inputs": [{"name": "account", "type": "address"}],
        "name": "balanceOf",
        "outputs": [{"name": "", "type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [
            {"name": "to", "type": "address"},
            {"name": "amount", "type": "uint256"},
        ],
        "name": "transfer",
        "outputs": [{"name": "", "type": "bool"}],
        "stateMutability": "nonpayable",
        "type": "function",
    },
    {
        "inputs": [
            {"name": "from", "type": "address"},
            {"name": "to", "type": "address"},
            {"name": "amount", "type": "uint256"},
        ],
        "name": "transferFrom",
        "outputs": [{"name": "", "type": "bool"}],
        "stateMutability": "nonpayable",
        "type": "function",
    },
    {
        "inputs": [
            {"name": "spender", "type": "address"},
            {"name": "amount", "type": "uint256"},
        ],
        "name": "approve",
        "outputs": [{"name": "", "type": "bool"}],
        "stateMutability": "nonpayable",
        "type": "function",
    },
    {
        "inputs": [
            {"name": "owner", "type": "address"},
            {"name": "spender", "type": "address"},
        ],
        "name": "allowance",
        "outputs": [{"name": "", "type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "decimals",
        "outputs": [{"name": "", "type": "uint8"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "totalSupply",
        "outputs": [{"name": "", "type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
]

# EMETRegistry
EMET_REGISTRY_ABI = [
    # --- Write ---
    {
        "inputs": [
            {"name": "claimHash", "type": "bytes32"},
            {"name": "evidenceURI", "type": "string"},
            {"name": "stake", "type": "uint256"},
        ],
        "name": "submitClaim",
        "outputs": [{"name": "claimId", "type": "uint256"}],
        "stateMutability": "nonpayable",
        "type": "function",
    },
    {
        "inputs": [{"name": "claimId", "type": "uint256"}],
        "name": "verifyUnchallenged",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function",
    },
    # --- Read ---
    {
        "inputs": [{"name": "claimId", "type": "uint256"}],
        "name": "getClaim",
        "outputs": [
            {
                "components": [
                    {"name": "claimHash", "type": "bytes32"},
                    {"name": "evidenceURI", "type": "string"},
                    {"name": "submitter", "type": "address"},
                    {"name": "timestamp", "type": "uint256"},
                    {"name": "stake", "type": "uint256"},
                    {"name": "challengeEnd", "type": "uint256"},
                    {"name": "status", "type": "uint8"},
                ],
                "name": "claim",
                "type": "tuple",
            }
        ],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "claimCount",
        "outputs": [{"name": "", "type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "minimumStake",
        "outputs": [{"name": "", "type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "challengePeriod",
        "outputs": [{"name": "", "type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [{"name": "claimId", "type": "uint256"}],
        "name": "canVerifyUnchallenged",
        "outputs": [{"name": "canVerify", "type": "bool"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [{"name": "claimId", "type": "uint256"}],
        "name": "getClaimStake",
        "outputs": [{"name": "stake", "type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [{"name": "claimId", "type": "uint256"}],
        "name": "getClaimSubmitter",
        "outputs": [{"name": "submitter", "type": "address"}],
        "stateMutability": "view",
        "type": "function",
    },
    # --- Events ---
    {
        "anonymous": False,
        "inputs": [
            {"indexed": True, "name": "claimId", "type": "uint256"},
            {"indexed": True, "name": "claimHash", "type": "bytes32"},
            {"indexed": True, "name": "submitter", "type": "address"},
            {"indexed": False, "name": "evidenceURI", "type": "string"},
            {"indexed": False, "name": "stake", "type": "uint256"},
            {"indexed": False, "name": "timestamp", "type": "uint256"},
        ],
        "name": "ClaimSubmitted",
        "type": "event",
    },
    {
        "anonymous": False,
        "inputs": [
            {"indexed": True, "name": "claimId", "type": "uint256"},
            {"indexed": True, "name": "oldStatus", "type": "uint8"},
            {"indexed": True, "name": "newStatus", "type": "uint8"},
        ],
        "name": "ClaimStatusChanged",
        "type": "event",
    },
]

# EMETStake
EMET_STAKE_ABI = [
    # --- Write ---
    {
        "inputs": [
            {"name": "claimId", "type": "uint256"},
            {"name": "amount", "type": "uint256"},
        ],
        "name": "stakeFor",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function",
    },
    {
        "inputs": [{"name": "claimId", "type": "uint256"}],
        "name": "withdraw",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function",
    },
    # --- Read ---
    {
        "inputs": [{"name": "claimId", "type": "uint256"}],
        "name": "getStakeTotals",
        "outputs": [
            {"name": "totalFor", "type": "uint256"},
            {"name": "totalAgainst", "type": "uint256"},
        ],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [
            {"name": "claimId", "type": "uint256"},
            {"name": "staker", "type": "address"},
        ],
        "name": "getUserStakes",
        "outputs": [
            {"name": "userStakeFor", "type": "uint256"},
            {"name": "userStakeAgainst", "type": "uint256"},
        ],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [
            {"name": "claimId", "type": "uint256"},
            {"name": "staker", "type": "address"},
            {"name": "assumeVerified", "type": "bool"},
        ],
        "name": "calculatePayout",
        "outputs": [{"name": "payout", "type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [
            {"name": "", "type": "uint256"},
            {"name": "", "type": "address"},
        ],
        "name": "hasWithdrawn",
        "outputs": [{"name": "", "type": "bool"}],
        "stateMutability": "view",
        "type": "function",
    },
    # --- Events ---
    {
        "anonymous": False,
        "inputs": [
            {"indexed": True, "name": "claimId", "type": "uint256"},
            {"indexed": True, "name": "staker", "type": "address"},
            {"indexed": False, "name": "amount", "type": "uint256"},
            {"indexed": True, "name": "isFor", "type": "bool"},
        ],
        "name": "Staked",
        "type": "event",
    },
    {
        "anonymous": False,
        "inputs": [
            {"indexed": True, "name": "claimId", "type": "uint256"},
            {"indexed": True, "name": "staker", "type": "address"},
            {"indexed": False, "name": "amount", "type": "uint256"},
            {"indexed": False, "name": "reward", "type": "uint256"},
        ],
        "name": "Withdrawn",
        "type": "event",
    },
]

# EMETReputation
EMET_REPUTATION_ABI = [
    {
        "inputs": [{"name": "account", "type": "address"}],
        "name": "getReputation",
        "outputs": [{"name": "score", "type": "int256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [{"name": "account", "type": "address"}],
        "name": "getReputationMultiplier",
        "outputs": [{"name": "multiplier", "type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [{"name": "account", "type": "address"}],
        "name": "hasPositiveReputation",
        "outputs": [{"name": "positive", "type": "bool"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [{"name": "account", "type": "address"}],
        "name": "getReputationTier",
        "outputs": [{"name": "tier", "type": "string"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "totalUpdates",
        "outputs": [{"name": "", "type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
    # --- Constants ---
    {
        "inputs": [],
        "name": "CLAIM_VERIFIED_POINTS",
        "outputs": [{"name": "", "type": "int256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "CLAIM_REJECTED_POINTS",
        "outputs": [{"name": "", "type": "int256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "CHALLENGE_SUCCESS_POINTS",
        "outputs": [{"name": "", "type": "int256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "CHALLENGE_FAILED_POINTS",
        "outputs": [{"name": "", "type": "int256"}],
        "stateMutability": "view",
        "type": "function",
    },
    # --- Events ---
    {
        "anonymous": False,
        "inputs": [
            {"indexed": True, "name": "account", "type": "address"},
            {"indexed": False, "name": "oldScore", "type": "int256"},
            {"indexed": False, "name": "newScore", "type": "int256"},
            {"indexed": False, "name": "delta", "type": "int256"},
            {"indexed": False, "name": "reason", "type": "string"},
        ],
        "name": "ReputationUpdated",
        "type": "event",
    },
]
