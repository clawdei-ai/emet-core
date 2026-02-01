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
  DEFAULT_CLAIM_FEE,
  DEFAULT_RESOLUTION_FEE_BPS,
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
    
    // Core contracts
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
    
    // ChallengeV3 v2 (current)
    this.challengeV3 = new ethers.Contract(
      ADDRESSES.EMETChallengeV3,
      ABIS.EMETChallengeV3,
      signerOrProvider
    );
    
    // Legacy challenge (for backwards compatibility)
    this.challenge = ADDRESSES.EMETChallenge 
      ? new ethers.Contract(ADDRESSES.EMETChallenge, ABIS.EMETChallenge, signerOrProvider)
      : null;
    
    // Trust & Governance contracts
    this.reputation = ADDRESSES.EMETReputation 
      ? new ethers.Contract(ADDRESSES.EMETReputation, ABIS.EMETReputation, signerOrProvider)
      : null;
    
    this.treasury = ADDRESSES.EMETTreasury
      ? new ethers.Contract(ADDRESSES.EMETTreasury, ABIS.EMETTreasury, signerOrProvider)
      : null;
    
    this.juryPool = ADDRESSES.EMETJuryPool
      ? new ethers.Contract(ADDRESSES.EMETJuryPool, ABIS.EMETJuryPool, signerOrProvider)
      : null;
    
    this.bootstrap = ADDRESSES.EMETBootstrap
      ? new ethers.Contract(ADDRESSES.EMETBootstrap, ABIS.EMETBootstrap, signerOrProvider)
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
  // Fee Operations
  // =========================================================================

  /**
   * Get the current claim fee
   * @returns {Promise<{raw: bigint, formatted: string}>}
   */
  async getClaimFee() {
    try {
      const fee = await this.registry.claimFee();
      return {
        raw: fee,
        formatted: ethers.formatUnits(fee, 18)
      };
    } catch (e) {
      // Fallback to default if not available
      return {
        raw: ethers.parseUnits(DEFAULT_CLAIM_FEE, 18),
        formatted: DEFAULT_CLAIM_FEE
      };
    }
  }

  /**
   * Get the current resolution fee in basis points
   * @returns {Promise<{bps: number, percentage: string}>}
   */
  async getResolutionFee() {
    try {
      const feeBps = await this.challengeV3.resolutionFeeBps();
      return {
        bps: Number(feeBps),
        percentage: `${Number(feeBps) / 100}%`
      };
    } catch (e) {
      // Fallback to default
      return {
        bps: DEFAULT_RESOLUTION_FEE_BPS,
        percentage: `${DEFAULT_RESOLUTION_FEE_BPS / 100}%`
      };
    }
  }

  /**
   * Get the verified claims count
   * @returns {Promise<number>}
   */
  async getVerifiedClaimsCount() {
    try {
      const count = await this.registry.verifiedClaimsCount();
      return Number(count);
    } catch (e) {
      return 0;
    }
  }

  // =========================================================================
  // Claim Operations
  // =========================================================================

  /**
   * Submit a new claim
   * 
   * Registry v2 requires a claim fee (10 EMET by default) in addition to the stake.
   * The fee is transferred to the treasury on submission.
   * 
   * @param {string} content - The claim text
   * @param {Object} options
   * @param {number|string} options.stake - Stake amount in EMET
   * @param {string} [options.evidence] - Evidence URL
   * @returns {Promise<{claimId: number, txHash: string, receipt: ethers.TransactionReceipt, fee: string}>}
   */
  async submitClaim(content, options = {}) {
    this._requireSigner();
    
    const stake = options.stake || 100;
    const evidence = options.evidence || '';
    
    const decimals = await this.token.decimals();
    const stakeWei = ethers.parseUnits(stake.toString(), decimals);
    
    // Get current claim fee
    const claimFee = await this.getClaimFee();
    const totalRequired = stakeWei + claimFee.raw;
    
    // Ensure allowance for stake + fee
    await this._ensureAllowance(ADDRESSES.EMETRegistry, totalRequired);
    
    // Hash the claim content (keccak256)
    const claimHash = ethers.keccak256(ethers.toUtf8Bytes(content));
    
    // Submit claim with hash, evidence URI, and stake
    const tx = await this.registry.submitClaim(claimHash, evidence, stakeWei);
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
      receipt,
      fee: claimFee.formatted
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
  // Challenge Operations (ChallengeV3 v2)
  // =========================================================================

  /**
   * Initiate a challenge against a claim
   * 
   * ChallengeV3 v2 includes a resolution fee (5% / 500 bps) that is
   * deducted from the losing party's stake when the challenge resolves.
   * 
   * @param {number} claimId
   * @param {Object} options
   * @param {string} options.evidence - Evidence URL
   * @param {number|string} options.stake - Stake amount
   * @returns {Promise<{txHash: string, receipt: ethers.TransactionReceipt}>}
   */
  async initiateChallenge(claimId, options = {}) {
    this._requireSigner();
    
    const evidence = options.evidence || '';
    const stake = options.stake || 100;
    
    const decimals = await this.token.decimals();
    const stakeWei = ethers.parseUnits(stake.toString(), decimals);
    
    // Ensure allowance for ChallengeV3
    await this._ensureAllowance(ADDRESSES.EMETChallengeV3, stakeWei);
    
    const tx = await this.challengeV3.initiateChallenge(claimId, evidence, stakeWei);
    const receipt = await tx.wait();
    
    return { txHash: receipt.hash, receipt };
  }

  /**
   * Challenge a claim (alias for initiateChallenge)
   * @deprecated Use initiateChallenge instead
   */
  async challenge(claimId, options = {}) {
    return this.initiateChallenge(claimId, options);
  }

  /**
   * Cast a vote on a challenge
   * @param {number} claimId
   * @param {boolean} supportChallenge - True to support the challenger, false to support the claim
   * @returns {Promise<{txHash: string, receipt: ethers.TransactionReceipt}>}
   */
  async castVote(claimId, supportChallenge) {
    this._requireSigner();
    
    const tx = await this.challengeV3.castVote(claimId, supportChallenge);
    const receipt = await tx.wait();
    
    return { txHash: receipt.hash, receipt };
  }

  /**
   * Get challenge info for a claim (ChallengeV3)
   * @param {number} claimId
   * @returns {Promise<Object|null>}
   */
  async getChallenge(claimId) {
    try {
      // Check if challenge exists first
      const exists = await this.challengeV3.challengeExists(claimId);
      if (!exists) return null;
      
      const challenge = await this.challengeV3.challenges(claimId);
      
      return {
        claimId,
        challenger: challenge[0] || challenge.challenger,
        evidence: challenge[1] || challenge.evidence,
        stake: {
          raw: challenge[2] || challenge.stake,
          formatted: ethers.formatUnits(challenge[2] || challenge.stake, 18)
        },
        voteStart: Number(challenge[3] || challenge.voteStart),
        voteEnd: Number(challenge[4] || challenge.voteEnd),
        status: Number(challenge[5] || challenge.status),
        statusName: ChallengeStatusName[Number(challenge[5] || challenge.status)] || 'Unknown'
      };
    } catch (err) {
      return null;
    }
  }

  /**
   * Check if a challenge exists for a claim
   * @param {number} claimId
   * @returns {Promise<boolean>}
   */
  async challengeExists(claimId) {
    try {
      return await this.challengeV3.challengeExists(claimId);
    } catch (err) {
      return false;
    }
  }

  /**
   * Check if a challenge can be resolved
   * @param {number} claimId
   * @returns {Promise<boolean>}
   */
  async canResolveChallenge(claimId) {
    try {
      return await this.challengeV3.canResolve(claimId);
    } catch (err) {
      return false;
    }
  }

  /**
   * Resolve a challenge
   * Anyone can call this after the voting period ends.
   * Resolution fee (5%) is deducted from the losing party's stake.
   * 
   * @param {number} claimId
   * @returns {Promise<{txHash: string, receipt: ethers.TransactionReceipt}>}
   */
  async resolveChallenge(claimId) {
    this._requireSigner();
    
    const tx = await this.challengeV3.resolve(claimId);
    const receipt = await tx.wait();
    
    return { txHash: receipt.hash, receipt };
  }

  // =========================================================================
  // Reputation Operations
  // =========================================================================

  /**
   * Get reputation for an address
   * @param {string} [address]
   * @returns {Promise<{score: number, multiplier: number, tier: string, isPositive: boolean, available: boolean}>}
   */
  async getReputation(address) {
    if (!this.reputation) {
      return {
        score: 0,
        multiplier: 1,
        tier: 'Unknown',
        isPositive: false,
        available: false,
        message: 'Reputation contract not available'
      };
    }
    
    const targetAddress = address || (this.signer ? await this.signer.getAddress() : null);
    if (!targetAddress) {
      throw new Error('Address required');
    }
    
    try {
      const [score, multiplierRaw, isPositive, tier] = await Promise.all([
        this.reputation.getReputation(targetAddress),
        this.reputation.getReputationMultiplier(targetAddress),
        this.reputation.hasPositiveReputation(targetAddress),
        this.reputation.getReputationTier(targetAddress)
      ]);
      
      return {
        score: Number(score),
        multiplier: Number(multiplierRaw) / 1e18,
        tier,
        isPositive,
        available: true
      };
    } catch (err) {
      return {
        score: 0,
        multiplier: 1,
        tier: 'Unknown',
        isPositive: false,
        available: false,
        error: err.message
      };
    }
  }

  // =========================================================================
  // Bootstrap Operations
  // =========================================================================

  /**
   * Claim bootstrap tokens (one-time per address)
   * @returns {Promise<{txHash: string, receipt: ethers.TransactionReceipt}>}
   */
  async claimBootstrapTokens() {
    this._requireSigner();
    
    if (!this.bootstrap) {
      throw new Error('Bootstrap contract not available');
    }
    
    const address = await this.getAddress();
    const hasClaimed = await this.bootstrap.hasClaimed(address);
    if (hasClaimed) {
      throw new Error('Bootstrap tokens already claimed');
    }
    
    const tx = await this.bootstrap.claimBootstrapTokens();
    const receipt = await tx.wait();
    
    return { txHash: receipt.hash, receipt };
  }

  /**
   * Check if an address has claimed bootstrap tokens
   * @param {string} [address]
   * @returns {Promise<boolean>}
   */
  async hasClaimedBootstrap(address) {
    if (!this.bootstrap) return false;
    
    const targetAddress = address || (this.signer ? await this.signer.getAddress() : null);
    if (!targetAddress) return false;
    
    return await this.bootstrap.hasClaimed(targetAddress);
  }

  /**
   * Get bootstrap amount
   * @returns {Promise<{raw: bigint, formatted: string}>}
   */
  async getBootstrapAmount() {
    if (!this.bootstrap) {
      return { raw: 0n, formatted: '0' };
    }
    
    const amount = await this.bootstrap.boostrapAmount();
    return {
      raw: amount,
      formatted: ethers.formatUnits(amount, 18)
    };
  }

  // =========================================================================
  // Jury Pool Operations
  // =========================================================================

  /**
   * Check if an address is a juror
   * @param {string} [address]
   * @returns {Promise<boolean>}
   */
  async isJuror(address) {
    if (!this.juryPool) return false;
    
    const targetAddress = address || (this.signer ? await this.signer.getAddress() : null);
    if (!targetAddress) return false;
    
    return await this.juryPool.isJuror(targetAddress);
  }

  /**
   * Get the total number of jurors
   * @returns {Promise<number>}
   */
  async getJurorCount() {
    if (!this.juryPool) return 0;
    return Number(await this.juryPool.getJurorCount());
  }

  /**
   * Get the minimum stake required to be a juror
   * @returns {Promise<{raw: bigint, formatted: string}>}
   */
  async getMinimumJurorStake() {
    if (!this.juryPool) {
      return { raw: 0n, formatted: '0' };
    }
    
    const amount = await this.juryPool.minimumStakeToBeJuror();
    return {
      raw: amount,
      formatted: ethers.formatUnits(amount, 18)
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
