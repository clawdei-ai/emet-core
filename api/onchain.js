/**
 * EMET Protocol — On-Chain Query Module
 *
 * Queries EMETReputation + EMETStake contracts on Base mainnet directly.
 * Used by the /trust-gate endpoint to resolve real Ethereum addresses.
 *
 * Falls back gracefully if RPC is unavailable or address has no history.
 */

'use strict';

const { ethers } = require('ethers');

const BASE_RPC = process.env.BASE_RPC_URL || 'https://mainnet.base.org';
const CHAIN_ID = 8453;

// Contract addresses (Base mainnet, Phase 2)
const ADDRESSES = {
  EMETReputation: '0x358a775b74f9369D23Ce95EDa57dcbA39A1F4d4e',
  EMETStake:      '0xb4A3Cf08194E445db65862Fb92bbC0cE587345bb',
  EMETRegistry:   '0x7a03057490e8541BF4A0F879659e58Fb13f03Ca9',
  EMETToken:      '0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C',
};

// Minimal ABIs — only what /trust-gate needs
const REPUTATION_ABI = [
  'function getReputation(address account) view returns (int256)',
  'function getReputationMultiplier(address account) view returns (uint256)',
  'function hasPositiveReputation(address account) view returns (bool)',
  'function getReputationTier(address account) view returns (string)',
  'function totalUpdates() view returns (uint256)',
];

const STAKE_ABI = [
  'function totalStakeFor(uint256 claimId) view returns (uint256)',
  'function stakes(uint256 claimId, address staker) view returns (uint256, uint256)',
];

const REGISTRY_ABI = [
  'function claimCount() view returns (uint256)',
  'function getClaimsBySubmitter(address submitter) view returns (uint256[])',
];

// Singleton provider (lazy init)
let _provider = null;
let _reputation = null;
let _registry = null;

function getProvider() {
  if (!_provider) {
    _provider = new ethers.JsonRpcProvider(BASE_RPC, CHAIN_ID);
  }
  return _provider;
}

function getReputationContract() {
  if (!_reputation) {
    _reputation = new ethers.Contract(
      ADDRESSES.EMETReputation,
      REPUTATION_ABI,
      getProvider()
    );
  }
  return _reputation;
}

function getRegistryContract() {
  if (!_registry) {
    _registry = new ethers.Contract(
      ADDRESSES.EMETRegistry,
      REGISTRY_ABI,
      getProvider()
    );
  }
  return _registry;
}

/**
 * Check if a string looks like an Ethereum address.
 * @param {string} id
 * @returns {boolean}
 */
function isEthAddress(id) {
  return /^0x[0-9a-fA-F]{40}$/.test(id);
}

/**
 * Query on-chain reputation for an Ethereum address.
 *
 * Returns null if the address has no on-chain history or if RPC fails.
 *
 * @param {string} address — 0x Ethereum address
 * @param {number} [timeoutMs=3000] — RPC timeout in milliseconds
 * @returns {Promise<OnChainRep|null>}
 *
 * @typedef {Object} OnChainRep
 * @property {number} score       — normalised 0-100 EMET reputation score
 * @property {number} rawScore    — raw int256 from contract
 * @property {number} multiplier  — reputation multiplier (x1.00 etc)
 * @property {boolean} positive   — hasPositiveReputation
 * @property {string}  tier       — e.g. "Bronze", "Silver", "Gold", "Platinum"
 * @property {number} claimCount  — number of claims submitted
 * @property {string} source      — "onchain"
 */
async function queryOnChain(address, timeoutMs = 4000) {
  if (!isEthAddress(address)) return null;

  const timeout = (ms) => new Promise((_, reject) =>
    setTimeout(() => reject(new Error('RPC timeout')), ms)
  );

  try {
    const rep = getReputationContract();
    const reg = getRegistryContract();

    // Race all queries against the timeout
    const [rawScore, multiplierRaw, positive, tier, claimIds] = await Promise.race([
      Promise.all([
        rep.getReputation(address).catch(() => 0n),
        rep.getReputationMultiplier(address).catch(() => 1000000000000000000n),
        rep.hasPositiveReputation(address).catch(() => false),
        rep.getReputationTier(address).catch(() => 'Unknown'),
        reg.getClaimsBySubmitter(address).catch(() => []),
      ]),
      timeout(timeoutMs),
    ]);

    const raw = Number(rawScore);
    const claimCount = Array.isArray(claimIds) ? claimIds.length : 0;
    const multiplier = Number(multiplierRaw) / 1e18;

    // Normalise raw reputation score to 0-100
    // Negative = below baseline, 0 = no history, positive = good standing
    // Contract stores raw delta sum; normalise against ±1000 range
    let score;
    if (raw === 0 && claimCount === 0) {
      // Truly fresh address
      score = 50; // baseline
    } else {
      // Map raw [-1000, 1000] → [0, 100], clamp
      score = Math.max(0, Math.min(100, Math.round(50 + (raw / 20))));
    }

    return {
      score,
      rawScore: raw,
      multiplier: parseFloat(multiplier.toFixed(2)),
      positive,
      tier,
      claimCount,
      source: 'onchain',
    };
  } catch (err) {
    // RPC unavailable or timeout — caller falls back to simulation
    return null;
  }
}

/**
 * Best-effort on-chain trust check.
 * Returns structured data for /trust-gate, or null if unavailable.
 *
 * @param {string} candidate — agent ID (eth address or emet:agent:... format)
 * @returns {Promise<OnChainRep|null>}
 */
async function resolveOnChain(candidate) {
  // Direct 0x address
  if (isEthAddress(candidate)) {
    return queryOnChain(candidate);
  }

  // emet:agent:address:suffix format
  const parts = candidate.split(':');
  for (const part of parts) {
    if (isEthAddress(part)) {
      return queryOnChain(part);
    }
  }

  return null;
}

module.exports = { resolveOnChain, isEthAddress, queryOnChain, ADDRESSES };
