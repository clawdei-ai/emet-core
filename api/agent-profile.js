/**
 * EMET Protocol — Agent Profile (v2)
 * 
 * Separates accuracy_score from risk_appetite as per EMET v2 design.
 * 
 * In v1, `emetScore` blended accuracy + risk into one number.
 * This caused two problems:
 *   1. Risk-seeking agents (large stakes, occasional slashes) appeared untrustworthy
 *   2. Risk-averse agents (tiny stakes, never slashed) appeared trustworthy
 * 
 * V2 separates them:
 *   accuracy_score (0–100): % of staked claims that resolved correct
 *   risk_appetite  (low/medium/high): avg stake size relative to median
 * 
 * Callers set their threshold on accuracy_score, not a blended number.
 * 
 * @version 2.0.0
 */

const { ethers } = require('ethers');

/**
 * Compute accuracy score from slash data.
 * 
 * @param {number} totalClaims
 * @param {number} slashCount
 * @returns {number} 0-100
 */
function computeAccuracyScore(totalClaims, slashCount) {
  if (totalClaims === 0) return 50; // bootstrap baseline
  const correctClaims = Math.max(0, totalClaims - slashCount);
  return Math.round((correctClaims / totalClaims) * 100);
}

/**
 * Classify risk appetite from average stake size in wei.
 * 
 * Thresholds:
 *   low:    avg stake < 0.001 ETH
 *   medium: 0.001–0.01 ETH
 *   high:   > 0.01 ETH
 * 
 * @param {string|bigint} avgStakeWei
 * @returns {'low'|'medium'|'high'|'unknown'}
 */
function classifyRiskAppetite(avgStakeWei) {
  if (!avgStakeWei || avgStakeWei === '0') return 'unknown';
  
  try {
    const wei = BigInt(avgStakeWei);
    const low    = BigInt(ethers.parseEther('0.001'));
    const medium = BigInt(ethers.parseEther('0.01'));
    
    if (wei < low)    return 'low';
    if (wei < medium) return 'medium';
    return 'high';
  } catch {
    return 'unknown';
  }
}

/**
 * Compute stake floor required based on requester tier.
 * 
 * From EMET v2 design:
 *   Gold queries Bronze  → Bronze must have staked ≥ 0.01 ETH recently
 *   Gold queries Silver  → Silver must have staked ≥ 0.001 ETH recently
 *   Bronze queries any   → no floor (bootstrap path)
 *   Silver queries any   → 0.0001 ETH floor
 * 
 * @param {'Bronze'|'Silver'|'Gold'|null} requesterTier
 * @returns {bigint} min stake in wei (0 = no floor)
 */
function stakeFloorForRequester(requesterTier) {
  const floors = {
    Gold:   BigInt(ethers.parseEther('0.01')),
    Silver: BigInt(ethers.parseEther('0.001')),
    Bronze: BigInt(0),
    null:   BigInt(0),
  };
  return floors[requesterTier] ?? BigInt(0);
}

/**
 * Build a full v2 agent profile from raw reputation data.
 * 
 * @param {object} raw
 * @param {number} raw.emetScore    — v1 blended score
 * @param {number} raw.slashCount
 * @param {number} raw.taskCount
 * @param {string} raw.stakeAmount  — total stake in wei (string)
 * @param {string} [raw.tier]       — Bronze/Silver/Gold
 * @returns {object} v2 profile
 */
function buildAgentProfile(raw) {
  const {
    emetScore = 50,
    slashCount = 0,
    taskCount = 0,
    stakeAmount = '0',
    tier = null,
  } = raw;

  const accuracyScore = computeAccuracyScore(taskCount, slashCount);
  
  // Average stake = total / task count
  let avgStake = '0';
  if (taskCount > 0 && stakeAmount && stakeAmount !== '0') {
    try {
      avgStake = (BigInt(stakeAmount) / BigInt(taskCount)).toString();
    } catch {
      avgStake = '0';
    }
  }
  
  const riskAppetite = classifyRiskAppetite(avgStake);

  return {
    // V1 compatibility
    legacyScore: emetScore,

    // V2 separated dimensions
    accuracyScore,
    riskAppetite,
    
    // Raw stats
    slashCount,
    taskCount,
    slashRate: taskCount > 0 ? parseFloat((slashCount / taskCount).toFixed(4)) : 0,
    totalStake: stakeAmount,
    avgStakeWei: avgStake,
    
    // Tier
    tier: tier || deriveTier(accuracyScore, taskCount),
  };
}

/**
 * Derive tier from accuracy + task history.
 * Used when on-chain tier data isn't available.
 */
function deriveTier(accuracyScore, taskCount) {
  if (taskCount === 0) return 'Bronze';
  if (accuracyScore >= 80 && taskCount >= 20) return 'Gold';
  if (accuracyScore >= 60 && taskCount >= 5)  return 'Silver';
  return 'Bronze';
}

/**
 * Check if a candidate meets the stake floor set by the requester's tier.
 * 
 * @param {object} candidateProfile — output of buildAgentProfile
 * @param {string} requesterTier    — "Bronze" | "Silver" | "Gold"
 * @returns {{ meetsFloor: boolean, requiredFloor: string, candidateAvg: string }}
 */
function checkStakeFloor(candidateProfile, requesterTier) {
  const floor = stakeFloorForRequester(requesterTier);
  if (floor === BigInt(0)) {
    return {
      meetsFloor: true,
      requiredFloor: '0',
      requiredFloorEth: '0',
      candidateAvg: candidateProfile.avgStakeWei,
    };
  }

  let candidateAvgWei;
  try {
    candidateAvgWei = BigInt(candidateProfile.avgStakeWei || '0');
  } catch {
    candidateAvgWei = BigInt(0);
  }

  return {
    meetsFloor: candidateAvgWei >= floor,
    requiredFloor: floor.toString(),
    requiredFloorEth: ethers.formatEther(floor),
    candidateAvg: candidateProfile.avgStakeWei,
    candidateAvgEth: ethers.formatEther(candidateAvgWei),
    requesterTier,
  };
}

module.exports = {
  buildAgentProfile,
  computeAccuracyScore,
  classifyRiskAppetite,
  stakeFloorForRequester,
  checkStakeFloor,
  deriveTier,
};
