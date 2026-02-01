/**
 * EMET Protocol Contract Definitions
 * 
 * Deployed on Base mainnet (chainId: 8453)
 */

export const CHAIN_ID = 8453;
export const DEFAULT_RPC = 'https://mainnet.base.org';

// Deployed contract addresses
export const ADDRESSES = {
  EMETToken: '0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C',
  EMETRegistry: '0x9D2550eB1Ee613E0f35c70524e1304B26392b0aC',
  EMETStake: '0x63901ED9Fbd8262B4505819E2F39a6145f28Fbf0',
  EMETChallenge: '0x5D47f36b0C768395CE49F2D7249DDe44086Fe37b',
  // Future contracts (hooks)
  EMETTreasury: null,
  EMETReputation: null,
  EMETLPRewards: null,
  EMETChallengeV2: null,
  EMETSignature: null
};

// Minimal ABIs for contract interaction
export const ABIS = {
  // ERC20 Token ABI
  EMETToken: [
    'function name() view returns (string)',
    'function symbol() view returns (string)',
    'function decimals() view returns (uint8)',
    'function totalSupply() view returns (uint256)',
    'function balanceOf(address account) view returns (uint256)',
    'function transfer(address to, uint256 amount) returns (bool)',
    'function allowance(address owner, address spender) view returns (uint256)',
    'function approve(address spender, uint256 amount) returns (bool)',
    'function transferFrom(address from, address to, uint256 amount) returns (bool)',
    'event Transfer(address indexed from, address indexed to, uint256 value)',
    'event Approval(address indexed owner, address indexed spender, uint256 value)'
  ],

  // Registry ABI - manages claims
  // Struct: { bytes32 id, string evidence, address submitter, uint256 timestamp, uint256 stake, uint8 status, bool exists }
  EMETRegistry: [
    'function claimCount() view returns (uint256)',
    'function nextClaimId() view returns (uint256)',
    'function claims(uint256 claimId) view returns (bytes32 id, string evidence, address submitter, uint256 timestamp, uint256 stake, uint8 status, bool exists)',
    'function submitClaim(string content, uint256 stake) returns (uint256)',
    'function submitClaimWithStake(string content, string evidence, uint256 stake) returns (uint256)',
    'function getClaim(uint256 claimId) view returns (bytes32 id, string evidence, address submitter, uint256 timestamp, uint256 stake, uint8 status, bool exists)',
    'function getClaimsBySubmitter(address submitter) view returns (uint256[])',
    'function getClaimStatus(uint256 claimId) view returns (uint8)',
    'function updateClaimStatus(uint256 claimId, uint8 newStatus)',
    'function minimumStake() view returns (uint256)',
    'function token() view returns (address)',
    'function owner() view returns (address)',
    'event ClaimSubmitted(uint256 indexed claimId, address indexed submitter, bytes32 claimHash, uint256 stake)',
    'event ClaimStatusUpdated(uint256 indexed claimId, uint8 oldStatus, uint8 newStatus)'
  ],

  // Stake ABI - manages staking for/against claims
  EMETStake: [
    'function stakes(uint256 claimId, address staker) view returns (uint256 forAmount, uint256 againstAmount)',
    'function totalStakeFor(uint256 claimId) view returns (uint256)',
    'function totalStakeAgainst(uint256 claimId) view returns (uint256)',
    'function stakeFor(uint256 claimId, uint256 amount)',
    'function stakeAgainst(uint256 claimId, uint256 amount)',
    'function withdrawStake(uint256 claimId)',
    'function getStakeInfo(uint256 claimId) view returns (uint256 totalFor, uint256 totalAgainst)',
    'function getUserStake(uint256 claimId, address user) view returns (uint256 forAmount, uint256 againstAmount)',
    'function token() view returns (address)',
    'function registry() view returns (address)',
    'event StakeAdded(uint256 indexed claimId, address indexed staker, uint256 amount, bool isFor)',
    'event StakeWithdrawn(uint256 indexed claimId, address indexed staker, uint256 amount)'
  ],

  // Challenge ABI - dispute resolution
  EMETChallenge: [
    'function challenges(uint256 claimId) view returns (address challenger, string evidence, uint256 stake, uint256 timestamp, uint8 status)',
    'function challenge(uint256 claimId, string evidence, uint256 stake)',
    'function resolveChallenge(uint256 claimId, bool challengeSucceeded)',
    'function getChallenge(uint256 claimId) view returns (tuple(address challenger, string evidence, uint256 stake, uint256 timestamp, uint8 status))',
    'function challengePeriod() view returns (uint256)',
    'function minimumChallengeStake() view returns (uint256)',
    'function canResolve(uint256 claimId) view returns (bool)',
    'function token() view returns (address)',
    'function registry() view returns (address)',
    'event ChallengeCreated(uint256 indexed claimId, address indexed challenger, uint256 stake)',
    'event ChallengeResolved(uint256 indexed claimId, bool succeeded, address winner)'
  ],

  // Reputation ABI (stub for future)
  EMETReputation: [
    'function reputation(address account) view returns (uint256)',
    'function getReputation(address account) view returns (uint256)',
    'function updateReputation(address account, int256 delta)'
  ]
};

// Claim status enum
export const ClaimStatus = {
  PENDING: 0,
  ACTIVE: 1,
  VERIFIED: 2,
  REJECTED: 3,
  DISPUTED: 4,
  RESOLVED: 5
};

// Reverse mapping for display
export const ClaimStatusName = {
  0: 'Pending',
  1: 'Active',
  2: 'Verified',
  3: 'Rejected',
  4: 'Disputed',
  5: 'Resolved'
};

// Challenge status enum
export const ChallengeStatus = {
  NONE: 0,
  PENDING: 1,
  RESOLVED_SUCCESS: 2,
  RESOLVED_FAILED: 3
};

export const ChallengeStatusName = {
  0: 'None',
  1: 'Pending',
  2: 'Challenge Succeeded',
  3: 'Challenge Failed'
};
