/**
 * EMET Protocol SDK Client
 * 
 * JavaScript/TypeScript SDK for interacting with EMET Protocol contracts on Base.
 */

import { ethers } from 'ethers';
import {
  ADDRESSES,
  ABIS,
  DEFAULT_RPC,
  CHAIN_ID,
  ClaimStatus,
  ClaimStatusName,
  ChallengeStatus,
  ChallengeStatusName
} from './contracts.js';

/**
 * EMET Protocol Client
 * 
 * @example
 * ```js
 * import { EMETClient } from '@emet/sdk'
 * 
 * const client = new EMETClient({ privateKey, rpcUrl })
 * await client.submitClaim("Earth is round", { stake: 1000, evidence: "https://..." })
 * ```
 */
export class EMETClient {
  /**
   * Create a new EMET client
   * @param {Object} options
   * @param {string} [options.privateKey] - Private key for signing transactions
   * @param {string} [options.rpcUrl] - RPC URL (default: Base mainnet)
   * @param {ethers.Provider} [options.provider] - Custom provider instance
   * @param {ethers.Signer} [options.signer] - Custom signer instance
   */
  constructor(options = {}) {
    const rpcUrl = options.rpcUrl || DEFAULT_RPC;
    
    // Set up provider
    if (options.provider) {
      this.provider = options.provider;
    } else {
      this.provider = new ethers.JsonRpcProvider(rpcUrl);
    }
    
    // Set up signer
    if (options.signer) {
      this.signer = options.signer;
    } else if (options.privateKey) {
      this.signer = new ethers.Wallet(options.privateKey, this.provider);
    } else {
      this.signer = null;
    }
    
    // Initialize contract instances
    this._initContracts();
  }

  /**
   * Initialize contract instances
   */
  _initContracts() {
    const signerOrProvider = this.signer || this.provider;
    
    this.token = new ethers.Contract(
      ADDRESSES.EMETToken,
      ABIS.EMETToken,
      signerOrProvider
    );
    
    this.registry = new ethers.Contract(
      ADDRESSES.EMETRegistry,
      ABIS.EMETRegistry,
      signerOrProvider
    );
    
    this.stake = new ethers.Contract(
      ADDRESSES.EMETStake,
      ABIS.EMETStake,
      signerOrProvider
    );
    
    this.challenge = new ethers.Contract(
      ADDRESSES.EMETChallenge,
      ABIS.EMETChallenge,
      signerOrProvider
    );
    
    // Future contracts (will be null until deployed)
    this.reputation = ADDRESSES.EMETReputation 
      ? new ethers.Contract(ADDRESSES.EMETReputation, ABIS.EMETReputation, signerOrProvider)
      : null;
  }

  /**
   * Ensure signer is available for write operations
   */
  _requireSigner() {
    if (!this.signer) {
      throw new Error('Signer required for this operation. Provide privateKey in constructor.');
    }
  }

  /**
   * Get the connected wallet address
   * @returns {Promise<string>}
   */
  async getAddress() {
    this._requireSigner();
    return this.signer.getAddress();
  }

  // =========================================================================
  // Token Operations
  // =========================================================================

  /**
   * Get EMET token balance
   * @param {string} [address] - Address to check (default: connected wallet)
   * @returns {Promise<{raw: bigint, formatted: string}>}
   */
  async getBalance(address) {
    const targetAddress = address || (this.signer ? await this.signer.getAddress() : null);
    if (!targetAddress) {
      throw new Error('Address required');
    }
    
    const balance = await this.token.balanceOf(targetAddress);
    const decimals = await this.token.decimals();
    
    return {
      raw: balance,
      formatted: ethers.formatUnits(balance, decimals),
      decimals
    };
  }

  /**
   * Get token info
   * @returns {Promise<{name: string, symbol: string, decimals: number, totalSupply: string}>}
   */
  async getTokenInfo() {
    const [name, symbol, decimals, totalSupply] = await Promise.all([
      this.token.name(),
      this.token.symbol(),
      this.token.decimals(),
      this.token.totalSupply()
    ]);
    
    return {
      name,
      symbol,
      decimals,
      totalSupply: ethers.formatUnits(totalSupply, decimals)
    };
  }

  /**
   * Approve tokens for a spender
   * @param {string} spender - Spender address
   * @param {string|number|bigint} amount - Amount to approve
   * @returns {Promise<ethers.TransactionReceipt>}
   */
  async approve(spender, amount) {
    this._requireSigner();
    const decimals = await this.token.decimals();
    const amountWei = ethers.parseUnits(amount.toString(), decimals);
    
    const tx = await this.token.approve(spender, amountWei);
    return tx.wait();
  }

  /**
   * Ensure sufficient allowance for a contract
   * @param {string} spender - Contract address
   * @param {bigint} amount - Required amount in wei
   */
  async _ensureAllowance(spender, amount) {
    const owner = await this.signer.getAddress();
    const allowance = await this.token.allowance(owner, spender);
    
    if (allowance < amount) {
      const tx = await this.token.approve(spender, amount);
      await tx.wait();
    }
  }

  // =========================================================================
  // Claim Operations
  // =========================================================================

  /**
   * Submit a new claim
   * @param {string} content - The claim text
   * @param {Object} options
   * @param {number|string} options.stake - Stake amount in EMET
   * @param {string} [options.evidence] - Evidence URL
   * @returns {Promise<{claimId: number, txHash: string, receipt: ethers.TransactionReceipt}>}
   */
  async submitClaim(content, options = {}) {
    this._requireSigner();
    
    const stake = options.stake || 100;
    const evidence = options.evidence || '';
    
    const decimals = await this.token.decimals();
    const stakeWei = ethers.parseUnits(stake.toString(), decimals);
    
    // Ensure allowance
    await this._ensureAllowance(ADDRESSES.EMETRegistry, stakeWei);
    
    // Submit claim
    const tx = await this.registry.submitClaim(content, evidence, stakeWei);
    const receipt = await tx.wait();
    
    // Parse ClaimSubmitted event to get claimId
    let claimId = null;
    for (const log of receipt.logs) {
      try {
        const parsed = this.registry.interface.parseLog({
          topics: log.topics,
          data: log.data
        });
        if (parsed && parsed.name === 'ClaimSubmitted') {
          claimId = Number(parsed.args.claimId);
          break;
        }
      } catch (e) {
        // Not our event
      }
    }
    
    return {
      claimId,
      txHash: receipt.hash,
      receipt
    };
  }

  /**
   * Get a claim by ID
   * @param {number} claimId
   * @returns {Promise<Object>}
   */
  async getClaim(claimId) {
    try {
      // Try getClaim first, fall back to claims mapping
      let claim;
      try {
        claim = await this.registry.getClaim(claimId);
      } catch (e) {
        // Try direct mapping access
        claim = await this.registry.claims(claimId);
      }
      
      // Handle struct: { bytes32 id, string evidence, address submitter, uint256 timestamp, uint256 stake, uint8 status, bool exists }
      const claimHash = claim.id || claim[0];
      const evidence = claim.evidence || claim[1];
      const submitter = claim.submitter || claim[2];
      const timestamp = claim.timestamp || claim[3];
      const stakeRaw = claim.stake || claim[4];
      const status = claim.status !== undefined ? claim.status : claim[5];
      
      // Check if claim exists (non-zero submitter or non-zero hash)
      const isZeroAddress = submitter === '0x0000000000000000000000000000000000000000';
      const isZeroHash = claimHash === '0x0000000000000000000000000000000000000000000000000000000000000000';
      if (isZeroAddress && isZeroHash) {
        throw new Error(`Claim ${claimId} not found`);
      }
      
      return {
        id: claimId,
        claimHash,
        submitter,
        content: '', // Content stored off-chain, hash on-chain
        evidence: evidence || '',
        stake: {
          raw: stakeRaw,
          formatted: ethers.formatUnits(stakeRaw || 0n, 18)
        },
        timestamp: Number(timestamp || 0),
        status: Number(status || 0),
        statusName: ClaimStatusName[Number(status || 0)] || 'Unknown'
      };
    } catch (err) {
      throw new Error(`Failed to get claim ${claimId}: ${err.message}`);
    }
  }

  /**
   * Get total number of claims
   * @returns {Promise<number>}
   */
  async getClaimCount() {
    try {
      const count = await this.registry.claimCount();
      return Number(count);
    } catch (e) {
      // Try alternative function name
      try {
        const count = await this.registry.nextClaimId();
        return Number(count);
      } catch (e2) {
        return 0;
      }
    }
  }

  /**
   * List claims with optional status filter
   * @param {Object} options
   * @param {string} [options.status] - Filter by status: active, verified, rejected
   * @param {number} [options.limit] - Max claims to return
   * @param {number} [options.offset] - Starting offset
   * @returns {Promise<Object[]>}
   */
  async listClaims(options = {}) {
    const count = await this.getClaimCount();
    const limit = options.limit || 50;
    const offset = options.offset || 0;
    
    const statusFilter = options.status 
      ? this._parseStatusFilter(options.status)
      : null;
    
    const claims = [];
    const end = Math.min(count, offset + limit);
    
    for (let i = offset; i < end; i++) {
      try {
        const claim = await this.getClaim(i);
        if (!statusFilter || statusFilter.includes(claim.status)) {
          claims.push(claim);
        }
      } catch (err) {
        // Skip invalid claims
      }
    }
    
    return claims;
  }

  _parseStatusFilter(status) {
    const mapping = {
      'pending': [ClaimStatus.PENDING],
      'active': [ClaimStatus.ACTIVE],
      'verified': [ClaimStatus.VERIFIED],
      'rejected': [ClaimStatus.REJECTED],
      'disputed': [ClaimStatus.DISPUTED],
      'resolved': [ClaimStatus.RESOLVED]
    };
    return mapping[status.toLowerCase()] || null;
  }

  // =========================================================================
  // Staking Operations
  // =========================================================================

  /**
   * Stake tokens in support of a claim
   * @param {number} claimId
   * @param {number|string} amount - Amount in EMET
   * @returns {Promise<{txHash: string, receipt: ethers.TransactionReceipt}>}
   */
  async stakeFor(claimId, amount) {
    this._requireSigner();
    
    const decimals = await this.token.decimals();
    const amountWei = ethers.parseUnits(amount.toString(), decimals);
    
    // Ensure allowance
    await this._ensureAllowance(ADDRESSES.EMETStake, amountWei);
    
    const tx = await this.stake.stakeFor(claimId, amountWei);
    const receipt = await tx.wait();
    
    return { txHash: receipt.hash, receipt };
  }

  /**
   * Stake tokens against a claim
   * @param {number} claimId
   * @param {number|string} amount - Amount in EMET
   * @returns {Promise<{txHash: string, receipt: ethers.TransactionReceipt}>}
   */
  async stakeAgainst(claimId, amount) {
    this._requireSigner();
    
    const decimals = await this.token.decimals();
    const amountWei = ethers.parseUnits(amount.toString(), decimals);
    
    // Ensure allowance
    await this._ensureAllowance(ADDRESSES.EMETStake, amountWei);
    
    const tx = await this.stake.stakeAgainst(claimId, amountWei);
    const receipt = await tx.wait();
    
    return { txHash: receipt.hash, receipt };
  }

  /**
   * Get stake info for a claim
   * @param {number} claimId
   * @returns {Promise<{totalFor: string, totalAgainst: string}>}
   */
  async getStakeInfo(claimId) {
    const [totalFor, totalAgainst] = await Promise.all([
      this.stake.totalStakeFor(claimId),
      this.stake.totalStakeAgainst(claimId)
    ]);
    
    return {
      totalFor: ethers.formatUnits(totalFor, 18),
      totalAgainst: ethers.formatUnits(totalAgainst, 18)
    };
  }

  /**
   * Get a user's stake on a claim
   * @param {number} claimId
   * @param {string} [address]
   * @returns {Promise<{forAmount: string, againstAmount: string}>}
   */
  async getUserStake(claimId, address) {
    const targetAddress = address || (this.signer ? await this.signer.getAddress() : null);
    if (!targetAddress) {
      throw new Error('Address required');
    }
    
    const stake = await this.stake.stakes(claimId, targetAddress);
    
    return {
      forAmount: ethers.formatUnits(stake[0] || stake.forAmount, 18),
      againstAmount: ethers.formatUnits(stake[1] || stake.againstAmount, 18)
    };
  }

  /**
   * Withdraw stake from a resolved claim
   * @param {number} claimId
   * @returns {Promise<{txHash: string, receipt: ethers.TransactionReceipt}>}
   */
  async withdrawStake(claimId) {
    this._requireSigner();
    
    const tx = await this.stake.withdrawStake(claimId);
    const receipt = await tx.wait();
    
    return { txHash: receipt.hash, receipt };
  }

  // =========================================================================
  // Challenge Operations
  // =========================================================================

  /**
   * Challenge a claim
   * @param {number} claimId
   * @param {Object} options
   * @param {string} options.evidence - Evidence URL
   * @param {number|string} options.stake - Stake amount
   * @returns {Promise<{txHash: string, receipt: ethers.TransactionReceipt}>}
   */
  async challenge(claimId, options = {}) {
    this._requireSigner();
    
    const evidence = options.evidence || '';
    const stake = options.stake || 100;
    
    const decimals = await this.token.decimals();
    const stakeWei = ethers.parseUnits(stake.toString(), decimals);
    
    // Ensure allowance
    await this._ensureAllowance(ADDRESSES.EMETChallenge, stakeWei);
    
    const tx = await this.challenge.challenge(claimId, evidence, stakeWei);
    const receipt = await tx.wait();
    
    return { txHash: receipt.hash, receipt };
  }

  /**
   * Get challenge info for a claim
   * @param {number} claimId
   * @returns {Promise<Object>}
   */
  async getChallenge(claimId) {
    try {
      const challenge = await this.challenge.challenges(claimId);
      
      return {
        claimId,
        challenger: challenge[0] || challenge.challenger,
        evidence: challenge[1] || challenge.evidence,
        stake: {
          raw: challenge[2] || challenge.stake,
          formatted: ethers.formatUnits(challenge[2] || challenge.stake, 18)
        },
        timestamp: Number(challenge[3] || challenge.timestamp),
        status: Number(challenge[4] || challenge.status),
        statusName: ChallengeStatusName[Number(challenge[4] || challenge.status)] || 'Unknown'
      };
    } catch (err) {
      return null;
    }
  }

  /**
   * Check if a challenge can be resolved
   * @param {number} claimId
   * @returns {Promise<boolean>}
   */
  async canResolveChallenge(claimId) {
    try {
      return await this.challenge.canResolve(claimId);
    } catch (err) {
      return false;
    }
  }

  /**
   * Resolve a challenge (requires appropriate permissions)
   * @param {number} claimId
   * @param {boolean} [challengeSucceeded=true]
   * @returns {Promise<{txHash: string, receipt: ethers.TransactionReceipt}>}
   */
  async resolveChallenge(claimId, challengeSucceeded = true) {
    this._requireSigner();
    
    const tx = await this.challenge.resolveChallenge(claimId, challengeSucceeded);
    const receipt = await tx.wait();
    
    return { txHash: receipt.hash, receipt };
  }

  // =========================================================================
  // Reputation Operations (stub)
  // =========================================================================

  /**
   * Get reputation for an address (stub - contract not yet deployed)
   * @param {string} [address]
   * @returns {Promise<{score: number, available: boolean}>}
   */
  async getReputation(address) {
    if (!this.reputation) {
      return {
        score: 0,
        available: false,
        message: 'Reputation contract not yet deployed'
      };
    }
    
    const targetAddress = address || (this.signer ? await this.signer.getAddress() : null);
    if (!targetAddress) {
      throw new Error('Address required');
    }
    
    const score = await this.reputation.reputation(targetAddress);
    return {
      score: Number(score),
      available: true
    };
  }

  // =========================================================================
  // Utility Methods
  // =========================================================================

  /**
   * Get current network info
   * @returns {Promise<{chainId: number, name: string, blockNumber: number}>}
   */
  async getNetworkInfo() {
    const network = await this.provider.getNetwork();
    const blockNumber = await this.provider.getBlockNumber();
    
    return {
      chainId: Number(network.chainId),
      name: network.name,
      blockNumber,
      isBase: Number(network.chainId) === CHAIN_ID
    };
  }

  /**
   * Get all contract addresses
   * @returns {Object}
   */
  getAddresses() {
    return { ...ADDRESSES };
  }

  /**
   * Wait for a transaction to be mined
   * @param {string} txHash
   * @param {number} [confirmations=1]
   * @returns {Promise<ethers.TransactionReceipt>}
   */
  async waitForTransaction(txHash, confirmations = 1) {
    return this.provider.waitForTransaction(txHash, confirmations);
  }

  /**
   * Estimate gas for a transaction
   * @param {Object} tx - Transaction object
   * @returns {Promise<bigint>}
   */
  async estimateGas(tx) {
    return this.provider.estimateGas(tx);
  }
}

export default EMETClient;
