"""Contract addresses and ABIs for the EMET Protocol on Base mainnet.

ABIs are derived from the Solidity sources in contracts/src/.
Only the functions used by the SDK are included.

Version: 2.2 (2026-02-12)
"""

# ============ Protocol Constants ============

DEFAULT_CLAIM_FEE = 10 * 10**18  # 10 EMET per claim submission
DEFAULT_RESOLUTION_FEE_BPS = 500  # 5% resolution fee

# ============ Addresses (Base mainnet v2.2) ============

# Core contracts
EMET_TOKEN_ADDRESS = "0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C"
EMET_REGISTRY_ADDRESS = "0x266D8343463deE2920CBE97EfB72B4540E491DeC"  # v2 - has claim fees
EMET_STAKE_ADDRESS = "0xb4A3Cf08194E445db65862Fb92bbC0cE587345bb"
EMET_SIGNATURE_ADDRESS = "0x6E5A8eF99D294a381bf4D0b0e27B95aFc293e074"

# Governance contracts
EMET_CHALLENGE_V3_ADDRESS = "0x697BAC4b1FCA88e12003C0ef3E03bdcbdE5d17D9"  # v2 - has resolution fees
EMET_JURY_POOL_ADDRESS = "0x018377D4e725703974A0087f8Ca8066c4aE8b045"  # v2
EMET_JUROR_STAKE_ADDRESS = "0x3f672390BeDac73eaCa3136552dB1197654DE20F"
EMET_HUMAN_ORACLE_ADDRESS = "0x017eEA4fad7dC4fb26E260B4e91354F722F6B61E"

# Trust contracts
EMET_REPUTATION_ADDRESS = "0x358a775b74f9369D23Ce95EDa57dcbA39A1F4d4e"
EMET_SYBIL_RESISTANCE_ADDRESS = "0xB195c1B3161b73B1dc2958793BBEB48D7995bEa5"
EMET_CONCENTRATION_ADDRESS = "0xbC13370559317f363d9665a49C59538484dF27fC"

# Verification contracts
EMET_CROSS_MODEL_ADDRESS = "0x7d19FcfFF4eD6093b9807edd7ae1b333f4b069aD"
EMET_DECAY_ADDRESS = "0xf75308E8093BC63cE6AcA0a01daDD918B249ab5a"

# Economic contracts
EMET_TREASURY_ADDRESS = "0xe1230E68818CCE66275Ad95E1bC79517Ac1ae502"
EMET_WHISTLEBLOWER_ADDRESS = "0xaa57c2cB96cceD9A56D238F2d1F9814a31CA8a26"

# Bootstrap
EMET_BOOTSTRAP_ADDRESS = "0xb2b908953f73006ad26a1ad212F740aB5Fe38BCa"

# Legacy (deprecated - do not use)
EMET_REGISTRY_V1_ADDRESS = "0x69FC0F525F15DFB57e762cD2c570114433AFc6e2"
EMET_CHALLENGE_V2_ADDRESS = "0x6F42c2F75aDB5e25018Ef7822E94DA3Df37E5B5A"
EMET_CHALLENGE_V3_V1_ADDRESS = "0xfFd54b3B1D72BE8205D961566e1AD4134FBd5332"
EMET_JURY_POOL_V1_ADDRESS = "0xDBa7434180e09c9b0857d5808a227E32E1c79bD8"


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

# EMETRegistry v2 - with claim fees
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
    {
        "inputs": [
            {"name": "claimId", "type": "uint256"},
            {"name": "newStatus", "type": "uint8"},
        ],
        "name": "updateClaimStatus",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function",
    },
    {
        "inputs": [{"name": "newFee", "type": "uint256"}],
        "name": "setClaimFee",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function",
    },
    {
        "inputs": [{"name": "newMinimum", "type": "uint256"}],
        "name": "setMinimumStake",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function",
    },
    {
        "inputs": [{"name": "challenge", "type": "address"}],
        "name": "setChallengeContract",
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
        "name": "verifiedClaimsCount",
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
        "name": "claimFee",
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
        "inputs": [],
        "name": "token",
        "outputs": [{"name": "", "type": "address"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "treasury",
        "outputs": [{"name": "", "type": "address"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "challengeContract",
        "outputs": [{"name": "", "type": "address"}],
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
    {
        "anonymous": False,
        "inputs": [
            {"indexed": False, "name": "oldFee", "type": "uint256"},
            {"indexed": False, "name": "newFee", "type": "uint256"},
        ],
        "name": "ClaimFeeUpdated",
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

# EMETChallengeV3 v2 - with resolution fees
EMET_CHALLENGE_V3_ABI = [
    # --- Write ---
    {
        "inputs": [
            {"name": "claimId", "type": "uint256"},
            {"name": "evidence", "type": "string"},
            {"name": "stake", "type": "uint256"},
        ],
        "name": "initiateChallenge",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function",
    },
    {
        "inputs": [
            {"name": "claimId", "type": "uint256"},
            {"name": "supportChallenge", "type": "bool"},
        ],
        "name": "castVote",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function",
    },
    {
        "inputs": [{"name": "claimId", "type": "uint256"}],
        "name": "resolve",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function",
    },
    {
        "inputs": [{"name": "newFeeBps", "type": "uint256"}],
        "name": "setResolutionFee",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function",
    },
    {
        "inputs": [{"name": "newMinimum", "type": "uint256"}],
        "name": "setMinimumChallengeStake",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function",
    },
    # --- Read ---
    {
        "inputs": [{"name": "claimId", "type": "uint256"}],
        "name": "challenges",
        "outputs": [
            {"name": "challenger", "type": "address"},
            {"name": "evidence", "type": "string"},
            {"name": "stake", "type": "uint256"},
            {"name": "voteStart", "type": "uint256"},
            {"name": "voteEnd", "type": "uint256"},
            {"name": "status", "type": "uint8"},
        ],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [{"name": "claimId", "type": "uint256"}],
        "name": "challengeExists",
        "outputs": [{"name": "", "type": "bool"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [{"name": "claimId", "type": "uint256"}],
        "name": "canResolve",
        "outputs": [{"name": "", "type": "bool"}],
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
        "inputs": [],
        "name": "votingPeriod",
        "outputs": [{"name": "", "type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "minimumChallengeStake",
        "outputs": [{"name": "", "type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "resolutionFeeBps",
        "outputs": [{"name": "", "type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "token",
        "outputs": [{"name": "", "type": "address"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "registry",
        "outputs": [{"name": "", "type": "address"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "treasury",
        "outputs": [{"name": "", "type": "address"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "reputation",
        "outputs": [{"name": "", "type": "address"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "juryPool",
        "outputs": [{"name": "", "type": "address"}],
        "stateMutability": "view",
        "type": "function",
    },
    # --- Events ---
    {
        "anonymous": False,
        "inputs": [
            {"indexed": True, "name": "claimId", "type": "uint256"},
            {"indexed": True, "name": "challenger", "type": "address"},
            {"indexed": False, "name": "stake", "type": "uint256"},
            {"indexed": False, "name": "evidence", "type": "string"},
        ],
        "name": "ChallengeInitiated",
        "type": "event",
    },
    {
        "anonymous": False,
        "inputs": [
            {"indexed": True, "name": "claimId", "type": "uint256"},
            {"indexed": True, "name": "voter", "type": "address"},
            {"indexed": False, "name": "supportChallenge", "type": "bool"},
            {"indexed": False, "name": "weight", "type": "uint256"},
        ],
        "name": "VoteCast",
        "type": "event",
    },
    {
        "anonymous": False,
        "inputs": [
            {"indexed": True, "name": "claimId", "type": "uint256"},
            {"indexed": False, "name": "challengeSucceeded", "type": "bool"},
            {"indexed": False, "name": "forVotes", "type": "uint256"},
            {"indexed": False, "name": "againstVotes", "type": "uint256"},
        ],
        "name": "ChallengeResolved",
        "type": "event",
    },
    {
        "anonymous": False,
        "inputs": [
            {"indexed": False, "name": "oldFeeBps", "type": "uint256"},
            {"indexed": False, "name": "newFeeBps", "type": "uint256"},
        ],
        "name": "ResolutionFeeUpdated",
        "type": "event",
    },
]

# EMETTreasury
EMET_TREASURY_ABI = [
    {
        "inputs": [],
        "name": "balance",
        "outputs": [{"name": "", "type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "token",
        "outputs": [{"name": "", "type": "address"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [
            {"name": "to", "type": "address"},
            {"name": "amount", "type": "uint256"},
        ],
        "name": "withdraw",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function",
    },
]

# EMETBootstrap
EMET_BOOTSTRAP_ABI = [
    {
        "inputs": [],
        "name": "claimBootstrapTokens",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function",
    },
    {
        "inputs": [{"name": "account", "type": "address"}],
        "name": "hasClaimed",
        "outputs": [{"name": "", "type": "bool"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "boostrapAmount",
        "outputs": [{"name": "", "type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "token",
        "outputs": [{"name": "", "type": "address"}],
        "stateMutability": "view",
        "type": "function",
    },
]
