/**
 * EMET Reputation System
 * 
 * Tracks agent reputation based on claim accuracy and verification outcomes.
 * Implements trust scoring with decay mechanics for inactive agents.
 */

const fs = require('fs');
const path = require('path');

// Default baseline reputation for new agents
const BASELINE_REPUTATION = {
  score: 50,
  claims: 0,
  verifications: 0,
  correctVerifications: 0,
  accuracy: 0.5,
  lastActivity: Date.now()
};

// Scoring constants
const CORRECT_VERIFICATION_BOOST = 5;
const INCORRECT_VERIFICATION_PENALTY = 10;
const MIN_SCORE = 0;
const MAX_SCORE = 100;

class ReputationStore {
  /**
   * @param {string} [persistPath] - Path to JSON file for persistence (optional)
   */
  constructor(persistPath = null) {
    this.agents = new Map();
    this.persistPath = persistPath;
    
    if (persistPath && fs.existsSync(persistPath)) {
      this._load();
    }
  }

  /**
   * Load state from JSON file
   * @private
   */
  _load() {
    try {
      const data = JSON.parse(fs.readFileSync(this.persistPath, 'utf8'));
      this.agents = new Map(Object.entries(data.agents || {}));
    } catch (err) {
      console.error('Failed to load reputation store:', err.message);
      this.agents = new Map();
    }
  }

  /**
   * Save state to JSON file
   * @private
   */
  _save() {
    if (!this.persistPath) return;
    
    const data = {
      version: 1,
      savedAt: new Date().toISOString(),
      agents: Object.fromEntries(this.agents)
    };
    
    const dir = path.dirname(this.persistPath);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    
    fs.writeFileSync(this.persistPath, JSON.stringify(data, null, 2));
  }

  /**
   * Get or create agent reputation data
   * @param {string} agentId
   * @returns {object} Reputation data
   */
  _getOrCreate(agentId) {
    if (!this.agents.has(agentId)) {
      this.agents.set(agentId, {
        ...BASELINE_REPUTATION,
        claims: [],
        verificationResults: []
      });
    }
    return this.agents.get(agentId);
  }

  /**
   * Get reputation for an agent
   * @param {string} agentId
   * @returns {{score: number, claims: number, verifications: number, accuracy: number}}
   */
  getReputation(agentId) {
    const agent = this._getOrCreate(agentId);
    return {
      score: agent.score,
      claims: agent.claims.length,
      verifications: agent.verifications,
      accuracy: agent.accuracy
    };
  }

  /**
   * Record that an agent made a claim
   * @param {string} agentId
   * @param {string} claimId
   * @returns {boolean} True if claim was recorded (false if duplicate)
   */
  recordClaim(agentId, claimId) {
    const agent = this._getOrCreate(agentId);
    
    // Check for duplicate claim
    if (agent.claims.includes(claimId)) {
      return false;
    }
    
    agent.claims.push(claimId);
    agent.lastActivity = Date.now();
    this._save();
    return true;
  }

  /**
   * Record a verification outcome for an agent
   * @param {string} agentId
   * @param {string} claimId
   * @param {boolean} result - True if verification was correct
   */
  recordVerification(agentId, claimId, result) {
    const agent = this._getOrCreate(agentId);
    
    agent.verifications++;
    agent.verificationResults.push({ claimId, result, timestamp: Date.now() });
    
    if (result) {
      agent.correctVerifications++;
      agent.score = Math.min(MAX_SCORE, agent.score + CORRECT_VERIFICATION_BOOST);
    } else {
      agent.score = Math.max(MIN_SCORE, agent.score - INCORRECT_VERIFICATION_PENALTY);
    }
    
    agent.lastActivity = Date.now();
    this.updateAccuracy(agentId);
    this._save();
  }

  /**
   * Recalculate accuracy score for an agent
   * @param {string} agentId
   * @returns {number} Updated accuracy
   */
  updateAccuracy(agentId) {
    const agent = this._getOrCreate(agentId);
    
    if (agent.verifications === 0) {
      agent.accuracy = 0.5; // Baseline for no data
    } else {
      agent.accuracy = agent.correctVerifications / agent.verifications;
    }
    
    return agent.accuracy;
  }

  /**
   * Calculate weighted trust score
   * Formula: accuracy * log(claims + 1)
   * @param {string} agentId
   * @returns {number} Trust score
   */
  calculateTrust(agentId) {
    const agent = this._getOrCreate(agentId);
    const claimCount = agent.claims.length;
    
    // Trust = accuracy * log(claims + 1)
    // This rewards both accuracy AND participation
    return agent.accuracy * Math.log(claimCount + 1);
  }

  /**
   * Apply decay to inactive agents' scores
   * @param {number} decayRate - Rate of decay (0-1), e.g., 0.05 = 5% decay
   * @param {number} [inactivityThreshold=86400000] - Ms of inactivity before decay (default: 24h)
   */
  applyDecay(decayRate, inactivityThreshold = 86400000) {
    const now = Date.now();
    
    for (const [agentId, agent] of this.agents) {
      const timeSinceActivity = now - agent.lastActivity;
      
      if (timeSinceActivity > inactivityThreshold) {
        // Decay towards baseline
        const decayAmount = (agent.score - BASELINE_REPUTATION.score) * decayRate;
        agent.score = Math.max(BASELINE_REPUTATION.score, agent.score - Math.abs(decayAmount));
        
        // Also decay accuracy towards baseline
        const accuracyDecay = (agent.accuracy - BASELINE_REPUTATION.accuracy) * decayRate;
        agent.accuracy = Math.max(0, Math.min(1, agent.accuracy - accuracyDecay));
      }
    }
    
    this._save();
  }

  /**
   * Get leaderboard of top agents by trust score
   * @param {number} [limit=10] - Number of agents to return
   * @returns {Array<{agentId: string, trust: number, score: number, claims: number, accuracy: number}>}
   */
  getLeaderboard(limit = 10) {
    const leaderboard = [];
    
    for (const [agentId] of this.agents) {
      const rep = this.getReputation(agentId);
      leaderboard.push({
        agentId,
        trust: this.calculateTrust(agentId),
        score: rep.score,
        claims: rep.claims,
        accuracy: rep.accuracy
      });
    }
    
    // Sort by trust score descending
    leaderboard.sort((a, b) => b.trust - a.trust);
    
    return leaderboard.slice(0, limit);
  }

  /**
   * Check if an agent exists in the store
   * @param {string} agentId
   * @returns {boolean}
   */
  hasAgent(agentId) {
    return this.agents.has(agentId);
  }

  /**
   * Get all agent IDs
   * @returns {string[]}
   */
  getAllAgents() {
    return Array.from(this.agents.keys());
  }

  /**
   * Clear all data (useful for testing)
   */
  clear() {
    this.agents.clear();
    this._save();
  }
}

// Singleton instance for module-level functions
let defaultStore = null;

function getDefaultStore() {
  if (!defaultStore) {
    defaultStore = new ReputationStore();
  }
  return defaultStore;
}

// Module-level convenience functions
function getReputation(agentId) {
  return getDefaultStore().getReputation(agentId);
}

function recordClaim(agentId, claimId) {
  return getDefaultStore().recordClaim(agentId, claimId);
}

function recordVerification(agentId, claimId, result) {
  return getDefaultStore().recordVerification(agentId, claimId, result);
}

function updateAccuracy(agentId) {
  return getDefaultStore().updateAccuracy(agentId);
}

function calculateTrust(agentId) {
  return getDefaultStore().calculateTrust(agentId);
}

function applyDecay(decayRate, inactivityThreshold) {
  return getDefaultStore().applyDecay(decayRate, inactivityThreshold);
}

function getLeaderboard(limit) {
  return getDefaultStore().getLeaderboard(limit);
}

module.exports = {
  ReputationStore,
  BASELINE_REPUTATION,
  CORRECT_VERIFICATION_BOOST,
  INCORRECT_VERIFICATION_PENALTY,
  MIN_SCORE,
  MAX_SCORE,
  getReputation,
  recordClaim,
  recordVerification,
  updateAccuracy,
  calculateTrust,
  applyDecay,
  getLeaderboard
};
