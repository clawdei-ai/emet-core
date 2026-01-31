/**
 * EMET Protocol — Reputation SQLite Store
 * 
 * Tracks agent reputation based on claim accuracy and verification outcomes.
 * Implements trust scoring with decay mechanics for inactive agents.
 * 
 * @module @emet-protocol/api/db/reputation
 * @version 0.4.0
 */

const { getDatabase } = require('./index');

// Default baseline reputation for new agents
const BASELINE_REPUTATION = {
  score: 50,
  verifications: 0,
  correctVerifications: 0,
  accuracy: 0.5
};

// Scoring constants
const CORRECT_VERIFICATION_BOOST = 5;
const INCORRECT_VERIFICATION_PENALTY = 10;
const MIN_SCORE = 0;
const MAX_SCORE = 100;

/**
 * Create a reputation store with the given database
 * @param {Database.Database} [database] - Optional database instance
 * @returns {ReputationStore}
 */
function createReputationStore(database = null) {
  const getDb = () => database || getDatabase();
  
  return {
    /**
     * Get or create an agent record
     * @private
     */
    _getOrCreate(agentId) {
      const db = getDb();
      
      let agent = db.prepare('SELECT * FROM agents WHERE id = ?').get(agentId);
      
      if (!agent) {
        db.prepare(`
          INSERT INTO agents (id, score, verifications, correct_verifications, accuracy, last_activity)
          VALUES (?, ?, ?, ?, ?, ?)
        `).run(
          agentId,
          BASELINE_REPUTATION.score,
          BASELINE_REPUTATION.verifications,
          BASELINE_REPUTATION.correctVerifications,
          BASELINE_REPUTATION.accuracy,
          Date.now()
        );
        
        agent = db.prepare('SELECT * FROM agents WHERE id = ?').get(agentId);
      }
      
      return agent;
    },
    
    /**
     * Get reputation for an agent
     * @param {string} agentId
     * @returns {{score: number, claims: number, verifications: number, accuracy: number}}
     */
    getReputation(agentId) {
      const db = getDb();
      const agent = this._getOrCreate(agentId);
      
      // Count claims from agent_claims table
      const claimCount = db.prepare(
        'SELECT COUNT(*) as count FROM agent_claims WHERE agent_id = ?'
      ).get(agentId).count;
      
      return {
        score: agent.score,
        claims: claimCount,
        verifications: agent.verifications,
        accuracy: agent.accuracy
      };
    },
    
    /**
     * Record that an agent made a claim
     * @param {string} agentId
     * @param {string} claimId
     * @returns {boolean} True if claim was recorded (false if duplicate)
     */
    recordClaim(agentId, claimId) {
      const db = getDb();
      
      // Ensure agent exists
      this._getOrCreate(agentId);
      
      // Try to insert the claim relationship
      try {
        db.prepare(
          'INSERT INTO agent_claims (agent_id, claim_id) VALUES (?, ?)'
        ).run(agentId, claimId);
        
        // Update last activity
        db.prepare(
          "UPDATE agents SET last_activity = ?, updated_at = datetime('now') WHERE id = ?"
        ).run(Date.now(), agentId);
        
        return true;
      } catch (err) {
        // Duplicate claim (unique constraint violation)
        if (err.code === 'SQLITE_CONSTRAINT_PRIMARYKEY') {
          return false;
        }
        throw err;
      }
    },
    
    /**
     * Record a verification outcome for an agent
     * @param {string} agentId
     * @param {string} claimId
     * @param {boolean} result - True if verification was correct
     */
    recordVerification(agentId, claimId, result) {
      const db = getDb();
      
      const agent = this._getOrCreate(agentId);
      
      // Insert verification result
      db.prepare(`
        INSERT INTO verification_results (agent_id, claim_id, result, timestamp)
        VALUES (?, ?, ?, ?)
      `).run(agentId, claimId, result ? 1 : 0, Date.now());
      
      // Calculate new values
      const newVerifications = agent.verifications + 1;
      const newCorrect = agent.correct_verifications + (result ? 1 : 0);
      const newAccuracy = newVerifications > 0 ? newCorrect / newVerifications : 0.5;
      
      let newScore = agent.score;
      if (result) {
        newScore = Math.min(MAX_SCORE, newScore + CORRECT_VERIFICATION_BOOST);
      } else {
        newScore = Math.max(MIN_SCORE, newScore - INCORRECT_VERIFICATION_PENALTY);
      }
      
      // Update agent
      const now = Date.now();
      db.prepare(
        "UPDATE agents SET verifications = ?, correct_verifications = ?, accuracy = ?, score = ?, last_activity = ?, updated_at = datetime('now') WHERE id = ?"
      ).run(newVerifications, newCorrect, newAccuracy, newScore, now, agentId);
    },
    
    /**
     * Update accuracy score for an agent
     * @param {string} agentId
     * @returns {number} Updated accuracy
     */
    updateAccuracy(agentId) {
      const db = getDb();
      const agent = this._getOrCreate(agentId);
      
      const accuracy = agent.verifications === 0 
        ? 0.5 
        : agent.correct_verifications / agent.verifications;
      
      db.prepare(
        "UPDATE agents SET accuracy = ?, updated_at = datetime('now') WHERE id = ?"
      ).run(accuracy, agentId);
      
      return accuracy;
    },
    
    /**
     * Calculate weighted trust score
     * Formula: accuracy * log(claims + 1)
     * @param {string} agentId
     * @returns {number} Trust score
     */
    calculateTrust(agentId) {
      const db = getDb();
      const agent = this._getOrCreate(agentId);
      
      const claimCount = db.prepare(
        'SELECT COUNT(*) as count FROM agent_claims WHERE agent_id = ?'
      ).get(agentId).count;
      
      return agent.accuracy * Math.log(claimCount + 1);
    },
    
    /**
     * Apply decay to inactive agents' scores
     * @param {number} decayRate - Rate of decay (0-1)
     * @param {number} [inactivityThreshold=86400000] - Ms before decay (default: 24h)
     */
    applyDecay(decayRate, inactivityThreshold = 86400000) {
      const db = getDb();
      const now = Date.now();
      const threshold = now - inactivityThreshold;
      
      // Get inactive agents
      const inactiveAgents = db.prepare(
        'SELECT * FROM agents WHERE last_activity < ?'
      ).all(threshold);
      
      for (const agent of inactiveAgents) {
        // Decay towards baseline
        const scoreDelta = (agent.score - BASELINE_REPUTATION.score) * decayRate;
        const newScore = Math.max(
          BASELINE_REPUTATION.score, 
          agent.score - Math.abs(scoreDelta)
        );
        
        const accuracyDelta = (agent.accuracy - BASELINE_REPUTATION.accuracy) * decayRate;
        const newAccuracy = Math.max(0, Math.min(1, agent.accuracy - accuracyDelta));
        
        db.prepare(
          "UPDATE agents SET score = ?, accuracy = ?, updated_at = datetime('now') WHERE id = ?"
        ).run(newScore, newAccuracy, agent.id);
      }
    },
    
    /**
     * Get leaderboard of top agents by trust score
     * @param {number} [limit=10]
     * @returns {Array}
     */
    getLeaderboard(limit = 10) {
      const db = getDb();
      
      const agents = db.prepare('SELECT * FROM agents').all();
      
      const leaderboard = agents.map(agent => {
        const claimCount = db.prepare(
          'SELECT COUNT(*) as count FROM agent_claims WHERE agent_id = ?'
        ).get(agent.id).count;
        
        return {
          agentId: agent.id,
          trust: agent.accuracy * Math.log(claimCount + 1),
          score: agent.score,
          claims: claimCount,
          accuracy: agent.accuracy
        };
      });
      
      leaderboard.sort((a, b) => b.trust - a.trust);
      return leaderboard.slice(0, limit);
    },
    
    /**
     * Check if an agent exists
     * @param {string} agentId
     * @returns {boolean}
     */
    hasAgent(agentId) {
      const db = getDb();
      return db.prepare('SELECT 1 FROM agents WHERE id = ?').get(agentId) !== undefined;
    },
    
    /**
     * Get all agent IDs
     * @returns {string[]}
     */
    getAllAgents() {
      const db = getDb();
      return db.prepare('SELECT id FROM agents').all().map(r => r.id);
    },
    
    /**
     * Get agent claims
     * @param {string} agentId
     * @returns {string[]} Array of claim IDs
     */
    getAgentClaims(agentId) {
      const db = getDb();
      return db.prepare(
        'SELECT claim_id FROM agent_claims WHERE agent_id = ?'
      ).all(agentId).map(r => r.claim_id);
    },
    
    /**
     * Get verification history for an agent
     * @param {string} agentId
     * @param {number} [limit=100]
     * @returns {Array}
     */
    getVerificationHistory(agentId, limit = 100) {
      const db = getDb();
      return db.prepare(`
        SELECT claim_id, result, timestamp 
        FROM verification_results 
        WHERE agent_id = ? 
        ORDER BY timestamp DESC 
        LIMIT ?
      `).all(agentId, limit).map(r => ({
        claimId: r.claim_id,
        result: r.result === 1,
        timestamp: r.timestamp
      }));
    },
    
    /**
     * Clear all reputation data (for testing)
     */
    clear() {
      const db = getDb();
      db.exec('DELETE FROM verification_results');
      db.exec('DELETE FROM agent_claims');
      db.exec('DELETE FROM agents');
    }
  };
}

// Default singleton store
let defaultStore = null;

function getDefaultStore() {
  if (!defaultStore) {
    defaultStore = createReputationStore();
  }
  return defaultStore;
}

// Module exports
module.exports = {
  // Store factory
  createReputationStore,
  
  // Constants
  BASELINE_REPUTATION,
  CORRECT_VERIFICATION_BOOST,
  INCORRECT_VERIFICATION_PENALTY,
  MIN_SCORE,
  MAX_SCORE,
  
  // Convenience functions using default store
  getReputation: (agentId) => getDefaultStore().getReputation(agentId),
  recordClaim: (agentId, claimId) => getDefaultStore().recordClaim(agentId, claimId),
  recordVerification: (agentId, claimId, result) => getDefaultStore().recordVerification(agentId, claimId, result),
  updateAccuracy: (agentId) => getDefaultStore().updateAccuracy(agentId),
  calculateTrust: (agentId) => getDefaultStore().calculateTrust(agentId),
  applyDecay: (decayRate, inactivityThreshold) => getDefaultStore().applyDecay(decayRate, inactivityThreshold),
  getLeaderboard: (limit) => getDefaultStore().getLeaderboard(limit),
  hasAgent: (agentId) => getDefaultStore().hasAgent(agentId),
  getAllAgents: () => getDefaultStore().getAllAgents(),
  getAgentClaims: (agentId) => getDefaultStore().getAgentClaims(agentId),
  getVerificationHistory: (agentId, limit) => getDefaultStore().getVerificationHistory(agentId, limit),
  clear: () => getDefaultStore().clear()
};
