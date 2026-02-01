/**
 * EMET Protocol Contract Definitions
 * 
 * Deployed on Base mainnet (chainId: 8453)
 * 
 * Version: 2.2 (2026-02-12)
 */

export const CHAIN_ID = 8453;
export const DEFAULT_RPC = 'https://mainnet.base.org';

// Protocol fee constants
export const DEFAULT_CLAIM_FEE = '10'; // 10 EMET per claim submission
export const DEFAULT_RESOLUTION_FEE_BPS = 500; // 5% resolution fee

// Deployed contract addresses (v2.2)
export const ADDRESSES = {
  // Core contracts
  EMETToken: '0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C',
  EMETRegistry: '0x266D8343463deE2920CBE97EfB72B4540E491DeC',  // v2 - has claim fees
  EMETStake: '0xb4A3Cf08194E445db65862Fb92bbC0cE587345bb',
  EMETSignature: '0x6E5A8eF99D294a381bf4D0b0e27B95aFc293e074',
  
  // Governance contracts
  EMETChallengeV3: '0x697BAC4b1FCA88e12003C0ef3E03bdcbdE5d17D9',  // v2 - has resolution fees
  EMETJuryPool: '0x018377D4e725703974A0087f8Ca8066c4aE8b045',     // v2
  EMETJurorStake: '0x3f672390BeDac73eaCa3136552dB1197654DE20F',
  EMETHumanOracle: '0x017eEA4fad7dC4fb26E260B4e91354F722F6B61E',
  
  // Trust contracts
  EMETReputation: '0x358a775b74f9369D23Ce95EDa57dcbA39A1F4d4e',
  EMETSybilResistance: '0xB195c1B3161b73B1dc2958793BBEB48D7995bEa5',
  EMETConcentration: '0xbC13370559317f363d9665a49C59538484dF27fC',
  
  // Verification contracts
  EMETCrossModel: '0x7d19FcfFF4eD6093b9807edd7ae1b333f4b069aD',
  EMETDecay: '0xf75308E8093BC63cE6AcA0a01daDD918B249ab5a',
  
  // Economic contracts
  EMETTreasury: '0xe1230E68818CCE66275Ad95E1bC79517Ac1ae502',
  EMETWhistleblower: '0xaa57c2cB96cceD9A56D238F2d1F9814a31CA8a26',
  
  // Bootstrap
  EMETBootstrap: '0xb2b908953f73006ad26a1ad212F740aB5Fe38BCa',
  
  // Legacy (deprecated - do not use)
  EMETRegistry_v1: '0x69FC0F525F15DFB57e762cD2c570114433AFc6e2',
  EMETChallenge: '0x6F42c2F75aDB5e25018Ef7822E94DA3Df37E5B5A',  // ChallengeV2
  EMETChallengeV3_v1: '0xfFd54b3B1D72BE8205D961566e1AD4134FBd5332',
  EMETJuryPool_v1: '0xDBa7434180e09c9b0857d5808a227E32E1c79bD8'
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

  // Registry v2 ABI - manages claims with fees
  // Claim fee: 10 EMET per submission (transferred to treasury)
  EMETRegistry: [
    // Read functions
    'function claimCount() view returns (uint256)',
    'function verifiedClaimsCount() view returns (uint256)',
    'function nextClaimId() view returns (uint256)',
    'function claims(uint256 claimId) view returns (bytes32 id, string evidence, address submitter, uint256 timestamp, uint256 stake, uint8 status, bool exists)',
    'function getClaim(uint256 claimId) view returns (bytes32 id, string evidence, address submitter, uint256 timestamp, uint256 stake, uint8 status, bool exists)',
    'function getClaimsBySubmitter(address submitter) view returns (uint256[])',
    'function getClaimStatus(uint256 claimId) view returns (uint8)',
    'function minimumStake() view returns (uint256)',
    'function claimFee() view returns (uint256)',
    'function token() view returns (address)',
    'function treasury() view returns (address)',
    'function challengeContract() view returns (address)',
    'function owner() view returns (address)',
    // Write functions
    'function submitClaim(bytes32 claimHash, string evidenceURI, uint256 stake) returns (uint256)',
    'function updateClaimStatus(uint256 claimId, uint8 newStatus)',
    'function setClaimFee(uint256 newFee)',
    'function setMinimumStake(uint256 newMinimum)',
    'function setChallengeContract(address challenge)',
    // Events
    'event ClaimSubmitted(uint256 indexed claimId, bytes32 indexed claimHash, address indexed submitter, string evidenceURI, uint256 stake, uint256 timestamp)',
    'event ClaimStatusChanged(uint256 indexed claimId, uint8 indexed oldStatus, uint8 indexed newStatus)',
    'event ClaimFeeUpdated(uint256 oldFee, uint256 newFee)'
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
    'function getStakeTotals(uint256 claimId) view returns (uint256 totalFor, uint256 totalAgainst)',
    'function getUserStakes(uint256 claimId, address staker) view returns (uint256 userStakeFor, uint256 userStakeAgainst)',
    'function token() view returns (address)',
    'function registry() view returns (address)',
    'event Staked(uint256 indexed claimId, address indexed staker, uint256 amount, bool indexed isFor)',
    'event StakeWithdrawn(uint256 indexed claimId, address indexed staker, uint256 amount)'
  ],

  // ChallengeV3 v2 ABI - dispute resolution with resolution fees
  // Resolution fee: 5% (500 bps) on challenge resolution
  EMETChallengeV3: [
    // Read functions
    'function challenges(uint256 claimId) view returns (address challenger, string evidence, uint256 stake, uint256 voteStart, uint256 voteEnd, uint8 status)',
    'function getChallenge(uint256 claimId) view returns (tuple(address challenger, string evidence, uint256 stake, uint256 voteStart, uint256 voteEnd, uint8 status))',
    'function challengeExists(uint256 claimId) view returns (bool)',
    'function canResolve(uint256 claimId) view returns (bool)',
    'function challengePeriod() view returns (uint256)',
    'function votingPeriod() view returns (uint256)',
    'function minimumChallengeStake() view returns (uint256)',
    'function resolutionFeeBps() view returns (uint256)',
    'function token() view returns (address)',
    'function registry() view returns (address)',
    'function treasury() view returns (address)',
    'function reputation() view returns (address)',
    'function juryPool() view returns (address)',
    'function owner() view returns (address)',
    // Write functions
    'function initiateChallenge(uint256 claimId, string evidence, uint256 stake)',
    'function castVote(uint256 claimId, bool supportChallenge)',
    'function resolve(uint256 claimId)',
    'function setResolutionFee(uint256 newFeeBps)',
    'function setMinimumChallengeStake(uint256 newMinimum)',
    // Events
    'event ChallengeInitiated(uint256 indexed claimId, address indexed challenger, uint256 stake, string evidence)',
    'event VoteCast(uint256 indexed claimId, address indexed voter, bool supportChallenge, uint256 weight)',
    'event ChallengeResolved(uint256 indexed claimId, bool challengeSucceeded, uint256 forVotes, uint256 againstVotes)',
    'event ResolutionFeeUpdated(uint256 oldFeeBps, uint256 newFeeBps)'
  ],

  // Legacy Challenge ABI (ChallengeV2 - deprecated)
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

  // Reputation ABI
  EMETReputation: [
    'function reputation(address account) view returns (int256)',
    'function getReputation(address account) view returns (int256)',
    'function getReputationMultiplier(address account) view returns (uint256)',
    'function hasPositiveReputation(address account) view returns (bool)',
    'function getReputationTier(address account) view returns (string)',
    'function totalUpdates() view returns (uint256)',
    'event ReputationUpdated(address indexed account, int256 oldScore, int256 newScore, int256 delta, string reason)'
  ],

  // Treasury ABI
  EMETTreasury: [
    'function balance() view returns (uint256)',
    'function token() view returns (address)',
    'function owner() view returns (address)',
    'function withdraw(address to, uint256 amount)',
    'event FundsReceived(address indexed from, uint256 amount)',
    'event FundsWithdrawn(address indexed to, uint256 amount)'
  ],

  // JuryPool v2 ABI
  EMETJuryPool: [
    'function isJuror(address account) view returns (bool)',
    'function getJurorCount() view returns (uint256)',
    'function selectJury(uint256 claimId, uint256 size) view returns (address[])',
    'function minimumStakeToBeJuror() view returns (uint256)',
    'function reputation() view returns (address)',
    'function challengeContract() view returns (address)'
  ],

  // Bootstrap ABI
  EMETBootstrap: [
    'function claimBootstrapTokens()',
    'function hasClaimed(address account) view returns (bool)',
    'function boostrapAmount() view returns (uint256)',
    'function token() view returns (address)'
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
