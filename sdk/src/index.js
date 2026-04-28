/**
 * EMET Protocol SDK
 * 
 * SDK for interacting with the EMET Protocol on Base mainnet.
 * 
 * @example
 * ```js
 * import { EMETClient } from '@emet/sdk'
 * 
 * // Read-only mode
 * const client = new EMETClient()
 * const claim = await client.getClaim(0)
 * 
 * // With signing capability
 * const client = new EMETClient({ 
 *   privateKey: process.env.EMET_PRIVATE_KEY 
 * })
 * await client.submitClaim("My claim", { stake: 100, evidence: "https://..." })
 * ```
 * 
 * @module @emet/sdk
 */

export { EMETClient } from './client.js';
export {
  EMETTrust,
  Policy,
  PolicyName,
  Tier,
  TierName,
  RiskAppetite,
  RiskAppetiteName,
  formatScore,
  normalizePolicy,
  normalizeScore,
  normalizeTrustResult
} from './trust.js';
export { 
  ADDRESSES, 
  ABIS, 
  CHAIN_ID, 
  DEFAULT_RPC,
  ClaimStatus,
  ClaimStatusName,
  ChallengeStatus,
  ChallengeStatusName
} from './contracts.js';

// Re-export ethers utilities for convenience
export { ethers } from 'ethers';
