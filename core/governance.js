/**
 * EMET Protocol - Governance Module
 * 
 * Dispute resolution and challenge system for EMET claims.
 * Enables decentralized adjudication through jury-based challenges.
 * 
 * @module @emet-protocol/core/governance
 * @version 1.0.0
 */

const { randomUUID, createHash } = require('crypto');

/**
 * Challenge status states
 * @readonly
 * @enum {string}
 */
const ChallengeStatus = {
  PENDING: 'pending',           // Created, awaiting jury selection
  JURY_SELECTED: 'jury_selected', // Jury assigned, voting open
  VOTING: 'voting',             // Votes being collected
  RESOLVED: 'resolved',         // Final verdict reached
  APPEALED: 'appealed',         // Escalated to higher tier
  EXPIRED: 'expired'            // Timed out without resolution
};

/**
 * Dispute tiers with corresponding jury sizes and stake requirements
 * @readonly
 * @enum {Object}
 */
const DisputeTier = {
  MINOR: {
    name: 'minor',
    jurySize: 3,
    minStake: 10,
    maxStake: 100,
    votingPeriodMs: 24 * 60 * 60 * 1000, // 24 hours
    appealMultiplier: 2
  },
  MAJOR: {
    name: 'major',
    jurySize: 7,
    minStake: 100,
    maxStake: 1000,
    votingPeriodMs: 72 * 60 * 60 * 1000, // 72 hours
    appealMultiplier: 2.5
  },
  CRITICAL: {
    name: 'critical',
    jurySize: 11,
    minStake: 1000,
    maxStake: 10000,
    votingPeriodMs: 168 * 60 * 60 * 1000, // 7 days
    appealMultiplier: 3
  }
};

/**
 * Vote options for jurors
 * @readonly
 * @enum {string}
 */
const VoteOption = {
  UPHOLD_CLAIM: 'uphold_claim',     // Original claim is valid
  UPHOLD_CHALLENGE: 'uphold_challenge', // Challenge is valid, claim is wrong
  ABSTAIN: 'abstain'                // Juror abstains (forfeits reward)
};

/**
 * Protocol fee percentage taken from stakes
 * @constant {number}
 */
const PROTOCOL_FEE_PERCENT = 5;

/**
 * Minimum reputation score to serve as juror
 * @constant {number}
 */
const MIN_JUROR_REPUTATION = 50;

// In-memory storage (would be replaced by persistent storage in production)
const challenges = new Map();
const precedents = new Map();

/**
 * Represents a dispute challenge against a claim
 * @class
 */
class Challenge {
  /**
   * Create a new Challenge
   * @param {Object} params - Challenge parameters
   * @param {string} params.challengerId - URI of the challenging agent
   * @param {string} params.claimId - ID of the claim being challenged
   * @param {string} params.evidence - Evidence supporting the challenge
   * @param {number} params.stake - Amount staked on the challenge
   * @param {string} [params.tier='MINOR'] - Dispute tier
   */
  constructor({ challengerId, claimId, evidence, stake, tier = 'MINOR' }) {
    this.id = `emet:challenge:${randomUUID()}`;
    this.challengerId = challengerId;
    this.claimId = claimId;
    this.evidence = evidence;
    this.stake = stake;
    this.tier = DisputeTier[tier] || DisputeTier.MINOR;
    this.status = ChallengeStatus.PENDING;
    this.jurors = [];
    this.votes = new Map();
    this.verdict = null;
    this.createdAt = new Date().toISOString();
    this.resolvedAt = null;
    this.appealOf = null;
    this.appealedTo = null;
    this.stakeDistribution = null;
  }

  /**
   * Convert challenge to plain object for serialization
   * @returns {Object}
   */
  toJSON() {
    return {
      id: this.id,
      challengerId: this.challengerId,
      claimId: this.claimId,
      evidence: this.evidence,
      stake: this.stake,
      tier: this.tier.name,
      status: this.status,
      jurors: this.jurors,
      votes: Object.fromEntries(this.votes),
      verdict: this.verdict,
      createdAt: this.createdAt,
      resolvedAt: this.resolvedAt,
      appealOf: this.appealOf,
      appealedTo: this.appealedTo,
      stakeDistribution: this.stakeDistribution
    };
  }
}

/**
 * Creates a new challenge against a claim.
 * 
 * @param {string} challengerId - URI of the challenging agent
 * @param {string} claimId - ID of the claim being challenged
 * @param {string} evidence - Evidence supporting the challenge
 * @param {number} stake - Amount to stake on the challenge
 * @param {Object} [options] - Additional options
 * @param {string} [options.tier='MINOR'] - Dispute tier
 * @param {string} [options.appealOf] - ID of challenge being appealed
 * @returns {Challenge} The created challenge
 * 
 * @throws {Error} If required parameters are missing
 * @throws {RangeError} If stake is outside tier bounds
 * 
 * @example
 * const challenge = createChallenge(
 *   'emet:agent:claude-3-opus',
 *   'emet:claim:abc123',
 *   'The referenced source contradicts the claim',
 *   50
 * );
 */
function createChallenge(challengerId, claimId, evidence, stake, options = {}) {
  // Validation
  if (!challengerId) {
    throw new Error('Challenger ID is required');
  }
  if (!claimId) {
    throw new Error('Claim ID is required');
  }
  if (!evidence || evidence.trim().length === 0) {
    throw new Error('Evidence is required');
  }
  if (typeof stake !== 'number' || stake <= 0) {
    throw new Error('Stake must be a positive number');
  }

  const tier = options.tier || 'MINOR';
  const tierConfig = DisputeTier[tier];
  
  if (!tierConfig) {
    throw new Error(`Invalid tier: ${tier}. Must be one of: ${Object.keys(DisputeTier).join(', ')}`);
  }

  // Check for existing active challenges on this claim (unless this is an appeal)
  if (!options.appealOf) {
    const existingChallenge = Array.from(challenges.values()).find(
      c => c.claimId === claimId && 
           c.status !== ChallengeStatus.RESOLVED && 
           c.status !== ChallengeStatus.EXPIRED
    );
    if (existingChallenge) {
      throw new Error(`Claim ${claimId} already has an active challenge: ${existingChallenge.id}`);
    }
  }

  // Validate stake against tier bounds
  if (stake < tierConfig.minStake) {
    throw new RangeError(`Stake ${stake} below minimum ${tierConfig.minStake} for ${tier} tier`);
  }
  if (stake > tierConfig.maxStake) {
    throw new RangeError(`Stake ${stake} exceeds maximum ${tierConfig.maxStake} for ${tier} tier`);
  }

  const challenge = new Challenge({
    challengerId,
    claimId,
    evidence,
    stake,
    tier
  });

  if (options.appealOf) {
    challenge.appealOf = options.appealOf;
    const originalChallenge = challenges.get(options.appealOf);
    if (originalChallenge) {
      originalChallenge.appealedTo = challenge.id;
    }
  }

  challenges.set(challenge.id, challenge);
  return challenge;
}

/**
 * Selects a jury for a challenge using weighted random selection.
 * Weights are based on agent reputation scores.
 * 
 * @param {Challenge} challenge - The challenge to select jury for
 * @param {Object} reputationStore - Map of agentId -> reputation score
 * @param {number} [jurySize] - Override jury size (defaults to tier setting)
 * @returns {string[]} Array of selected juror agent IDs
 * 
 * @throws {Error} If not enough eligible jurors available
 * 
 * @example
 * const reputationStore = {
 *   'emet:agent:gpt-4': 85,
 *   'emet:agent:claude-3': 92,
 *   'emet:agent:gemini': 78
 * };
 * const jurors = selectJury(challenge, reputationStore);
 */
function selectJury(challenge, reputationStore, jurySize) {
  const targetSize = jurySize || challenge.tier.jurySize;
  
  // Filter eligible jurors (minimum reputation, not the challenger)
  const eligibleJurors = Object.entries(reputationStore)
    .filter(([agentId, reputation]) => 
      reputation >= MIN_JUROR_REPUTATION && 
      agentId !== challenge.challengerId
    );

  if (eligibleJurors.length < targetSize) {
    throw new Error(
      `Insufficient eligible jurors: need ${targetSize}, found ${eligibleJurors.length}`
    );
  }

  // Calculate total weight for probability distribution
  const totalWeight = eligibleJurors.reduce((sum, [, rep]) => sum + rep, 0);
  
  // Weighted random selection without replacement
  const selected = [];
  const remaining = [...eligibleJurors];
  
  for (let i = 0; i < targetSize; i++) {
    // Recalculate weights for remaining candidates
    const currentTotal = remaining.reduce((sum, [, rep]) => sum + rep, 0);
    let random = Math.random() * currentTotal;
    
    for (let j = 0; j < remaining.length; j++) {
      random -= remaining[j][1]; // Subtract reputation weight
      if (random <= 0) {
        selected.push(remaining[j][0]);
        remaining.splice(j, 1);
        break;
      }
    }
    
    // Edge case: if random didn't select anyone, pick last remaining
    if (selected.length <= i) {
      const lastIdx = remaining.length - 1;
      selected.push(remaining[lastIdx][0]);
      remaining.splice(lastIdx, 1);
    }
  }

  challenge.jurors = selected;
  challenge.status = ChallengeStatus.JURY_SELECTED;
  challenge.votingStartedAt = new Date().toISOString();
  
  return selected;
}

/**
 * Records a juror's vote on a challenge.
 * 
 * @param {string} challengeId - ID of the challenge
 * @param {string} jurorId - ID of the voting juror
 * @param {string} vote - Vote option (uphold_claim, uphold_challenge, abstain)
 * @param {string} [reasoning] - Optional reasoning for the vote
 * @returns {Object} Vote record
 * 
 * @throws {Error} If challenge not found or juror not authorized
 * 
 * @example
 * const vote = submitVote(
 *   'emet:challenge:xyz789',
 *   'emet:agent:gpt-4',
 *   'uphold_challenge',
 *   'The evidence clearly contradicts the original claim'
 * );
 */
function submitVote(challengeId, jurorId, vote, reasoning = '') {
  const challenge = challenges.get(challengeId);
  
  if (!challenge) {
    throw new Error(`Challenge not found: ${challengeId}`);
  }
  
  if (challenge.status !== ChallengeStatus.JURY_SELECTED && 
      challenge.status !== ChallengeStatus.VOTING) {
    throw new Error(`Challenge is not in voting phase: status is ${challenge.status}`);
  }
  
  if (!challenge.jurors.includes(jurorId)) {
    throw new Error(`Agent ${jurorId} is not a juror on this challenge`);
  }
  
  if (challenge.votes.has(jurorId)) {
    throw new Error(`Juror ${jurorId} has already voted`);
  }
  
  if (!Object.values(VoteOption).includes(vote)) {
    throw new Error(`Invalid vote: ${vote}. Must be one of: ${Object.values(VoteOption).join(', ')}`);
  }

  const voteRecord = {
    jurorId,
    vote,
    reasoning,
    timestamp: new Date().toISOString(),
    hash: createHash('sha256')
      .update(`${challengeId}:${jurorId}:${vote}:${reasoning}`)
      .digest('hex')
  };

  challenge.votes.set(jurorId, voteRecord);
  challenge.status = ChallengeStatus.VOTING;
  
  return voteRecord;
}

/**
 * Resolves a challenge by tallying votes and distributing stakes.
 * 
 * @param {string} challengeId - ID of the challenge to resolve
 * @returns {Object} Resolution result with verdict and stake distribution
 * 
 * @throws {Error} If challenge not found or cannot be resolved
 * 
 * @example
 * const result = resolveChallenge('emet:challenge:xyz789');
 * console.log(result.verdict); // 'uphold_challenge'
 * console.log(result.stakeDistribution); // { winner: 95, protocol: 5 }
 */
function resolveChallenge(challengeId) {
  const challenge = challenges.get(challengeId);
  
  if (!challenge) {
    throw new Error(`Challenge not found: ${challengeId}`);
  }
  
  if (challenge.status === ChallengeStatus.RESOLVED) {
    throw new Error('Challenge already resolved');
  }
  
  // Count votes
  const voteCounts = {
    [VoteOption.UPHOLD_CLAIM]: 0,
    [VoteOption.UPHOLD_CHALLENGE]: 0,
    [VoteOption.ABSTAIN]: 0
  };
  
  for (const voteRecord of challenge.votes.values()) {
    voteCounts[voteRecord.vote]++;
  }
  
  // Determine verdict (majority wins, excluding abstentions)
  const activeVotes = voteCounts[VoteOption.UPHOLD_CLAIM] + 
                      voteCounts[VoteOption.UPHOLD_CHALLENGE];
  
  let verdict;
  if (activeVotes === 0) {
    verdict = 'no_verdict'; // All abstained
  } else if (voteCounts[VoteOption.UPHOLD_CLAIM] > voteCounts[VoteOption.UPHOLD_CHALLENGE]) {
    verdict = VoteOption.UPHOLD_CLAIM;
  } else if (voteCounts[VoteOption.UPHOLD_CHALLENGE] > voteCounts[VoteOption.UPHOLD_CLAIM]) {
    verdict = VoteOption.UPHOLD_CHALLENGE;
  } else {
    verdict = 'tie'; // Split decision, defaults to upholding original claim
  }

  // Calculate stake distribution
  const protocolFee = Math.floor(challenge.stake * PROTOCOL_FEE_PERCENT / 100);
  const winnerPayout = challenge.stake - protocolFee;
  
  const stakeDistribution = {
    totalStake: challenge.stake,
    protocolFee,
    winnerPayout,
    winner: verdict === VoteOption.UPHOLD_CHALLENGE ? 
            challenge.challengerId : 
            'claim_holder', // In production, would be actual claim issuer
    jurorRewards: calculateJurorRewards(challenge, verdict)
  };

  challenge.verdict = verdict;
  challenge.status = ChallengeStatus.RESOLVED;
  challenge.resolvedAt = new Date().toISOString();
  challenge.stakeDistribution = stakeDistribution;

  // Record precedent for future reference
  recordPrecedent(challenge);

  return {
    challengeId: challenge.id,
    claimId: challenge.claimId,
    verdict,
    voteCounts,
    stakeDistribution,
    resolvedAt: challenge.resolvedAt
  };
}

/**
 * Calculate rewards for jurors based on their votes
 * @private
 */
function calculateJurorRewards(challenge, verdict) {
  const rewards = {};
  const rewardPool = Math.floor(challenge.stake * 0.1); // 10% to jurors
  
  // Jurors who voted with majority get rewards
  const majorityVote = verdict === 'tie' || verdict === 'no_verdict' ? 
                       null : verdict;
  
  if (!majorityVote) {
    // No rewards if no clear verdict
    return rewards;
  }
  
  const winningJurors = [];
  for (const [jurorId, voteRecord] of challenge.votes) {
    if (voteRecord.vote === majorityVote) {
      winningJurors.push(jurorId);
    }
  }
  
  if (winningJurors.length > 0) {
    const rewardPerJuror = Math.floor(rewardPool / winningJurors.length);
    for (const jurorId of winningJurors) {
      rewards[jurorId] = rewardPerJuror;
    }
  }
  
  return rewards;
}

/**
 * Records a resolved challenge as precedent for future disputes
 * @private
 */
function recordPrecedent(challenge) {
  const precedent = {
    challengeId: challenge.id,
    claimId: challenge.claimId,
    evidence: challenge.evidence,
    verdict: challenge.verdict,
    tier: challenge.tier.name,
    resolvedAt: challenge.resolvedAt,
    voteCounts: Object.fromEntries(
      Object.entries(VoteOption).map(([key, value]) => {
        let count = 0;
        for (const vote of challenge.votes.values()) {
          if (vote.vote === value) count++;
        }
        return [value, count];
      })
    )
  };
  
  if (!precedents.has(challenge.claimId)) {
    precedents.set(challenge.claimId, []);
  }
  precedents.get(challenge.claimId).push(precedent);
}

/**
 * Creates an appeal for a resolved challenge.
 * Requires higher stake than original challenge.
 * 
 * @param {string} originalChallengeId - ID of the challenge to appeal
 * @param {string} appellantId - ID of the appealing agent
 * @param {string} additionalEvidence - New evidence for appeal
 * @param {number} stake - Appeal stake (must exceed original * multiplier)
 * @returns {Challenge} The appeal challenge
 * 
 * @throws {Error} If original challenge not resolved or stake insufficient
 */
function createAppeal(originalChallengeId, appellantId, additionalEvidence, stake) {
  const original = challenges.get(originalChallengeId);
  
  if (!original) {
    throw new Error(`Challenge not found: ${originalChallengeId}`);
  }
  
  if (original.status !== ChallengeStatus.RESOLVED) {
    throw new Error('Can only appeal resolved challenges');
  }
  
  if (original.appealedTo) {
    throw new Error(`Challenge already appealed to: ${original.appealedTo}`);
  }
  
  // Determine next tier
  const tierNames = Object.keys(DisputeTier);
  const currentTierIndex = tierNames.indexOf(original.tier.name.toUpperCase());
  const nextTierName = tierNames[Math.min(currentTierIndex + 1, tierNames.length - 1)];
  const nextTier = DisputeTier[nextTierName];
  
  // Calculate required stake
  const requiredStake = Math.ceil(original.stake * original.tier.appealMultiplier);
  
  if (stake < requiredStake) {
    throw new RangeError(
      `Appeal stake ${stake} below required ${requiredStake} (${original.tier.appealMultiplier}x original)`
    );
  }
  
  return createChallenge(
    appellantId,
    original.claimId,
    `APPEAL of ${originalChallengeId}: ${additionalEvidence}`,
    stake,
    { tier: nextTierName, appealOf: originalChallengeId }
  );
}

/**
 * Gets all active (unresolved) challenges.
 * 
 * @returns {Challenge[]} Array of active challenges
 */
function getActiveChallenges() {
  return Array.from(challenges.values()).filter(
    c => c.status !== ChallengeStatus.RESOLVED && 
         c.status !== ChallengeStatus.EXPIRED
  );
}

/**
 * Gets the challenge history for a specific claim.
 * 
 * @param {string} claimId - ID of the claim
 * @returns {Object} Challenge history including precedents
 */
function getChallengeHistory(claimId) {
  const claimChallenges = Array.from(challenges.values())
    .filter(c => c.claimId === claimId)
    .map(c => c.toJSON())
    .sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt));
  
  return {
    claimId,
    challenges: claimChallenges,
    precedents: precedents.get(claimId) || [],
    totalChallenges: claimChallenges.length,
    resolvedCount: claimChallenges.filter(c => c.status === ChallengeStatus.RESOLVED).length
  };
}

/**
 * Gets a challenge by ID.
 * 
 * @param {string} challengeId - ID of the challenge
 * @returns {Challenge|null} The challenge or null if not found
 */
function getChallenge(challengeId) {
  return challenges.get(challengeId) || null;
}

/**
 * Gets relevant precedents for a claim to inform future disputes.
 * 
 * @param {string} claimId - ID of the claim
 * @returns {Object[]} Array of precedent records
 */
function getPrecedents(claimId) {
  return precedents.get(claimId) || [];
}

/**
 * Clears all challenges and precedents (for testing).
 * @private
 */
function _reset() {
  challenges.clear();
  precedents.clear();
}

module.exports = {
  // Core functions
  createChallenge,
  selectJury,
  submitVote,
  resolveChallenge,
  createAppeal,
  
  // Query functions
  getActiveChallenges,
  getChallengeHistory,
  getChallenge,
  getPrecedents,
  
  // Classes
  Challenge,
  
  // Constants
  ChallengeStatus,
  DisputeTier,
  VoteOption,
  PROTOCOL_FEE_PERCENT,
  MIN_JUROR_REPUTATION,
  
  // Testing utilities
  _reset
};
