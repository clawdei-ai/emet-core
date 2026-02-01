// ABIs extracted from Solidity contracts

export const EMETTokenABI = [
  { type: 'function', name: 'balanceOf', inputs: [{ name: 'account', type: 'address' }], outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view' },
  { type: 'function', name: 'allowance', inputs: [{ name: 'owner', type: 'address' }, { name: 'spender', type: 'address' }], outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view' },
  { type: 'function', name: 'approve', inputs: [{ name: 'spender', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [{ name: '', type: 'bool' }], stateMutability: 'nonpayable' },
  { type: 'function', name: 'transfer', inputs: [{ name: 'to', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [{ name: '', type: 'bool' }], stateMutability: 'nonpayable' },
  { type: 'function', name: 'transferFrom', inputs: [{ name: 'from', type: 'address' }, { name: 'to', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [{ name: '', type: 'bool' }], stateMutability: 'nonpayable' },
  { type: 'function', name: 'totalSupply', inputs: [], outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view' },
  { type: 'function', name: 'decimals', inputs: [], outputs: [{ name: '', type: 'uint8' }], stateMutability: 'view' },
  { type: 'function', name: 'symbol', inputs: [], outputs: [{ name: '', type: 'string' }], stateMutability: 'view' },
  { type: 'function', name: 'name', inputs: [], outputs: [{ name: '', type: 'string' }], stateMutability: 'view' },
] as const;

export const EMETRegistryABI = [
  // View functions
  { type: 'function', name: 'claimCount', inputs: [], outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view' },
  { type: 'function', name: 'minimumStake', inputs: [], outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view' },
  { type: 'function', name: 'challengePeriod', inputs: [], outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view' },
  {
    type: 'function', name: 'getClaim', inputs: [{ name: 'claimId', type: 'uint256' }],
    outputs: [{
      name: 'claim', type: 'tuple',
      components: [
        { name: 'claimHash', type: 'bytes32' },
        { name: 'claimText', type: 'string' },
        { name: 'evidenceURI', type: 'string' },
        { name: 'submitter', type: 'address' },
        { name: 'timestamp', type: 'uint256' },
        { name: 'stake', type: 'uint256' },
        { name: 'challengeEnd', type: 'uint256' },
        { name: 'status', type: 'uint8' },
      ],
    }],
    stateMutability: 'view',
  },
  { type: 'function', name: 'canVerifyUnchallenged', inputs: [{ name: 'claimId', type: 'uint256' }], outputs: [{ name: 'canVerify', type: 'bool' }], stateMutability: 'view' },
  { type: 'function', name: 'getClaimStake', inputs: [{ name: 'claimId', type: 'uint256' }], outputs: [{ name: 'stake', type: 'uint256' }], stateMutability: 'view' },
  { type: 'function', name: 'getClaimSubmitter', inputs: [{ name: 'claimId', type: 'uint256' }], outputs: [{ name: 'submitter', type: 'address' }], stateMutability: 'view' },
  // Write functions
  {
    type: 'function', name: 'submitClaim',
    inputs: [
      { name: 'claimText', type: 'string' },
      { name: 'evidenceURI', type: 'string' },
      { name: 'stake', type: 'uint256' },
    ],
    outputs: [{ name: 'claimId', type: 'uint256' }],
    stateMutability: 'nonpayable',
  },
  { type: 'function', name: 'verifyUnchallenged', inputs: [{ name: 'claimId', type: 'uint256' }], outputs: [], stateMutability: 'nonpayable' },
  // Events
  {
    type: 'event', name: 'ClaimSubmitted',
    inputs: [
      { name: 'claimId', type: 'uint256', indexed: true },
      { name: 'claimHash', type: 'bytes32', indexed: true },
      { name: 'submitter', type: 'address', indexed: true },
      { name: 'claimText', type: 'string', indexed: false },
      { name: 'evidenceURI', type: 'string', indexed: false },
      { name: 'stake', type: 'uint256', indexed: false },
      { name: 'timestamp', type: 'uint256', indexed: false },
    ],
  },
  {
    type: 'event', name: 'ClaimStatusChanged',
    inputs: [
      { name: 'claimId', type: 'uint256', indexed: true },
      { name: 'oldStatus', type: 'uint8', indexed: true },
      { name: 'newStatus', type: 'uint8', indexed: true },
    ],
  },
] as const;

export const EMETStakeABI = [
  // View functions
  {
    type: 'function', name: 'getStakeTotals',
    inputs: [{ name: 'claimId', type: 'uint256' }],
    outputs: [{ name: 'totalFor', type: 'uint256' }, { name: 'totalAgainst', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function', name: 'getUserStakes',
    inputs: [{ name: 'claimId', type: 'uint256' }, { name: 'staker', type: 'address' }],
    outputs: [{ name: 'userStakeFor', type: 'uint256' }, { name: 'userStakeAgainst', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function', name: 'calculatePayout',
    inputs: [{ name: 'claimId', type: 'uint256' }, { name: 'staker', type: 'address' }, { name: 'assumeVerified', type: 'bool' }],
    outputs: [{ name: 'payout', type: 'uint256' }],
    stateMutability: 'view',
  },
  // Write functions
  { type: 'function', name: 'stakeFor', inputs: [{ name: 'claimId', type: 'uint256' }, { name: 'amount', type: 'uint256' }], outputs: [], stateMutability: 'nonpayable' },
  { type: 'function', name: 'withdraw', inputs: [{ name: 'claimId', type: 'uint256' }], outputs: [], stateMutability: 'nonpayable' },
  // Events
  {
    type: 'event', name: 'Staked',
    inputs: [
      { name: 'claimId', type: 'uint256', indexed: true },
      { name: 'staker', type: 'address', indexed: true },
      { name: 'amount', type: 'uint256', indexed: false },
      { name: 'isFor', type: 'bool', indexed: true },
    ],
  },
] as const;

export const EMETChallengeABI = [
  // View functions
  {
    type: 'function', name: 'getChallenge',
    inputs: [{ name: 'claimId', type: 'uint256' }],
    outputs: [
      { name: 'challenger', type: 'address' },
      { name: 'stake', type: 'uint256' },
      { name: 'startTime', type: 'uint256' },
      { name: 'resolved', type: 'bool' },
    ],
    stateMutability: 'view',
  },
  { type: 'function', name: 'canResolve', inputs: [{ name: 'claimId', type: 'uint256' }], outputs: [{ name: 'resolvable', type: 'bool' }], stateMutability: 'view' },
  {
    type: 'function', name: 'getCurrentStanding',
    inputs: [{ name: 'claimId', type: 'uint256' }],
    outputs: [
      { name: 'effectiveFor', type: 'uint256' },
      { name: 'totalAgainst', type: 'uint256' },
      { name: 'currentWinner', type: 'string' },
    ],
    stateMutability: 'view',
  },
  { type: 'function', name: 'minimumChallengeStake', inputs: [], outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view' },
  // Write functions (V2 legacy)
  { type: 'function', name: 'initiateChallenge', inputs: [{ name: 'claimId', type: 'uint256' }, { name: 'stake', type: 'uint256' }], outputs: [], stateMutability: 'nonpayable' },
  { type: 'function', name: 'stakeForClaim', inputs: [{ name: 'claimId', type: 'uint256' }, { name: 'amount', type: 'uint256' }], outputs: [], stateMutability: 'nonpayable' },
  { type: 'function', name: 'stakeAgainstClaim', inputs: [{ name: 'claimId', type: 'uint256' }, { name: 'amount', type: 'uint256' }], outputs: [], stateMutability: 'nonpayable' },
  { type: 'function', name: 'resolveChallenge', inputs: [{ name: 'claimId', type: 'uint256' }], outputs: [], stateMutability: 'nonpayable' },
] as const;

export const EMETChallengeV3ABI = [
  // View
  {
    type: 'function', name: 'getChallenge',
    inputs: [{ name: 'challengeId', type: 'uint256' }],
    outputs: [
      { name: 'claimId', type: 'uint256' },
      { name: 'challenger', type: 'address' },
      { name: 'evidence', type: 'string' },
      { name: 'stake', type: 'uint256' },
      { name: 'tier', type: 'uint8' },
      { name: 'resolved', type: 'bool' },
    ],
    stateMutability: 'view',
  },
  { type: 'function', name: 'challengeCount', inputs: [], outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view' },
  // Write
  {
    type: 'function', name: 'initiateChallenge',
    inputs: [
      { name: 'claimId', type: 'uint256' },
      { name: 'evidence', type: 'string' },
      { name: 'stake', type: 'uint256' },
      { name: 'tier', type: 'uint8' },
    ],
    outputs: [{ name: 'challengeId', type: 'uint256' }],
    stateMutability: 'nonpayable',
  },
] as const;

export const EMETReputationABI = [
  { type: 'function', name: 'getReputation', inputs: [{ name: 'account', type: 'address' }], outputs: [{ name: 'score', type: 'int256' }], stateMutability: 'view' },
  { type: 'function', name: 'getReputationMultiplier', inputs: [{ name: 'account', type: 'address' }], outputs: [{ name: 'multiplier', type: 'uint256' }], stateMutability: 'view' },
  { type: 'function', name: 'getReputationTier', inputs: [{ name: 'account', type: 'address' }], outputs: [{ name: 'tier', type: 'string' }], stateMutability: 'view' },
  { type: 'function', name: 'hasPositiveReputation', inputs: [{ name: 'account', type: 'address' }], outputs: [{ name: 'positive', type: 'bool' }], stateMutability: 'view' },
  { type: 'function', name: 'totalUpdates', inputs: [], outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view' },
] as const;
