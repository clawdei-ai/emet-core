/**
 * Reputation System Tests
 */

const {
  ReputationStore,
  BASELINE_REPUTATION,
  CORRECT_VERIFICATION_BOOST,
  INCORRECT_VERIFICATION_PENALTY
} = require('../reputation');

describe('ReputationStore', () => {
  let store;

  beforeEach(() => {
    store = new ReputationStore(); // In-memory only
  });

  describe('getReputation', () => {
    test('new agent starts at baseline reputation', () => {
      const rep = store.getReputation('new-agent');
      
      expect(rep.score).toBe(BASELINE_REPUTATION.score);
      expect(rep.claims).toBe(0);
      expect(rep.verifications).toBe(0);
      expect(rep.accuracy).toBe(BASELINE_REPUTATION.accuracy);
    });

    test('unknown agent returns baseline values', () => {
      const rep = store.getReputation('nonexistent-agent-xyz');
      
      expect(rep.score).toBe(50);
      expect(rep.accuracy).toBe(0.5);
    });
  });

  describe('recordClaim', () => {
    test('claims increase count', () => {
      store.recordClaim('agent-1', 'claim-1');
      store.recordClaim('agent-1', 'claim-2');
      store.recordClaim('agent-1', 'claim-3');
      
      const rep = store.getReputation('agent-1');
      expect(rep.claims).toBe(3);
    });

    test('duplicate claims are not recorded', () => {
      const first = store.recordClaim('agent-1', 'claim-1');
      const second = store.recordClaim('agent-1', 'claim-1');
      
      expect(first).toBe(true);
      expect(second).toBe(false);
      
      const rep = store.getReputation('agent-1');
      expect(rep.claims).toBe(1);
    });

    test('different agents can make the same claim', () => {
      store.recordClaim('agent-1', 'claim-1');
      store.recordClaim('agent-2', 'claim-1');
      
      expect(store.getReputation('agent-1').claims).toBe(1);
      expect(store.getReputation('agent-2').claims).toBe(1);
    });
  });

  describe('recordVerification', () => {
    test('correct verifications boost score', () => {
      const initialRep = store.getReputation('agent-1');
      const initialScore = initialRep.score;
      
      store.recordVerification('agent-1', 'claim-1', true);
      
      const rep = store.getReputation('agent-1');
      expect(rep.score).toBe(initialScore + CORRECT_VERIFICATION_BOOST);
      expect(rep.verifications).toBe(1);
    });

    test('incorrect verifications reduce score', () => {
      const initialRep = store.getReputation('agent-1');
      const initialScore = initialRep.score;
      
      store.recordVerification('agent-1', 'claim-1', false);
      
      const rep = store.getReputation('agent-1');
      expect(rep.score).toBe(initialScore - INCORRECT_VERIFICATION_PENALTY);
      expect(rep.verifications).toBe(1);
    });

    test('score cannot exceed maximum', () => {
      // Boost many times
      for (let i = 0; i < 20; i++) {
        store.recordVerification('agent-1', `claim-${i}`, true);
      }
      
      const rep = store.getReputation('agent-1');
      expect(rep.score).toBeLessThanOrEqual(100);
    });

    test('score cannot go below minimum', () => {
      // Penalize many times
      for (let i = 0; i < 20; i++) {
        store.recordVerification('agent-1', `claim-${i}`, false);
      }
      
      const rep = store.getReputation('agent-1');
      expect(rep.score).toBeGreaterThanOrEqual(0);
    });

    test('accuracy updates after verifications', () => {
      store.recordVerification('agent-1', 'claim-1', true);
      store.recordVerification('agent-1', 'claim-2', true);
      store.recordVerification('agent-1', 'claim-3', false);
      
      const rep = store.getReputation('agent-1');
      expect(rep.accuracy).toBeCloseTo(2/3, 5);
    });
  });

  describe('updateAccuracy', () => {
    test('accuracy is 0.5 with no verifications', () => {
      store.recordClaim('agent-1', 'claim-1');
      const accuracy = store.updateAccuracy('agent-1');
      expect(accuracy).toBe(0.5);
    });

    test('accuracy reflects verification results', () => {
      store.recordVerification('agent-1', 'claim-1', true);
      store.recordVerification('agent-1', 'claim-2', false);
      
      const accuracy = store.updateAccuracy('agent-1');
      expect(accuracy).toBe(0.5);
    });
  });

  describe('calculateTrust', () => {
    test('trust is 0 for new agent with no claims', () => {
      const trust = store.calculateTrust('new-agent');
      // accuracy (0.5) * log(0 + 1) = 0.5 * 0 = 0
      expect(trust).toBe(0);
    });

    test('trust increases with more claims', () => {
      store.recordClaim('agent-1', 'claim-1');
      const trust1 = store.calculateTrust('agent-1');
      
      store.recordClaim('agent-1', 'claim-2');
      store.recordClaim('agent-1', 'claim-3');
      const trust2 = store.calculateTrust('agent-1');
      
      expect(trust2).toBeGreaterThan(trust1);
    });

    test('trust increases with better accuracy', () => {
      store.recordClaim('agent-1', 'claim-1');
      store.recordClaim('agent-2', 'claim-2');
      
      // Agent 1: all correct
      store.recordVerification('agent-1', 'claim-1', true);
      store.recordVerification('agent-1', 'claim-1b', true);
      
      // Agent 2: all incorrect
      store.recordVerification('agent-2', 'claim-2', false);
      store.recordVerification('agent-2', 'claim-2b', false);
      
      expect(store.calculateTrust('agent-1')).toBeGreaterThan(store.calculateTrust('agent-2'));
    });
  });

  describe('applyDecay', () => {
    test('decay reduces inactive scores towards baseline', () => {
      // Create agent with high score
      for (let i = 0; i < 5; i++) {
        store.recordVerification('agent-1', `claim-${i}`, true);
      }
      
      const beforeDecay = store.getReputation('agent-1').score;
      expect(beforeDecay).toBeGreaterThan(BASELINE_REPUTATION.score);
      
      // Simulate inactivity by backdating
      store.agents.get('agent-1').lastActivity = Date.now() - 100000000;
      
      store.applyDecay(0.5, 1000); // 50% decay, 1s threshold
      
      const afterDecay = store.getReputation('agent-1').score;
      expect(afterDecay).toBeLessThan(beforeDecay);
      expect(afterDecay).toBeGreaterThanOrEqual(BASELINE_REPUTATION.score);
    });

    test('active agents are not affected by decay', () => {
      store.recordVerification('agent-1', 'claim-1', true);
      const beforeDecay = store.getReputation('agent-1').score;
      
      store.applyDecay(0.5, 86400000); // 24h threshold
      
      const afterDecay = store.getReputation('agent-1').score;
      expect(afterDecay).toBe(beforeDecay);
    });
  });

  describe('getLeaderboard', () => {
    test('leaderboard ordering is correct', () => {
      // Create agents with different trust levels
      store.recordClaim('low-agent', 'claim-1');
      
      store.recordClaim('mid-agent', 'claim-1');
      store.recordClaim('mid-agent', 'claim-2');
      store.recordVerification('mid-agent', 'v1', true);
      
      store.recordClaim('high-agent', 'claim-1');
      store.recordClaim('high-agent', 'claim-2');
      store.recordClaim('high-agent', 'claim-3');
      store.recordVerification('high-agent', 'v1', true);
      store.recordVerification('high-agent', 'v2', true);
      
      const leaderboard = store.getLeaderboard(10);
      
      expect(leaderboard[0].agentId).toBe('high-agent');
      expect(leaderboard[1].agentId).toBe('mid-agent');
      expect(leaderboard[2].agentId).toBe('low-agent');
    });

    test('leaderboard respects limit', () => {
      for (let i = 0; i < 10; i++) {
        store.recordClaim(`agent-${i}`, 'claim-1');
      }
      
      const leaderboard = store.getLeaderboard(5);
      expect(leaderboard.length).toBe(5);
    });

    test('leaderboard returns all agents if fewer than limit', () => {
      store.recordClaim('agent-1', 'claim-1');
      store.recordClaim('agent-2', 'claim-1');
      
      const leaderboard = store.getLeaderboard(10);
      expect(leaderboard.length).toBe(2);
    });

    test('leaderboard includes correct fields', () => {
      store.recordClaim('agent-1', 'claim-1');
      store.recordVerification('agent-1', 'v1', true);
      
      const leaderboard = store.getLeaderboard(1);
      const entry = leaderboard[0];
      
      expect(entry).toHaveProperty('agentId');
      expect(entry).toHaveProperty('trust');
      expect(entry).toHaveProperty('score');
      expect(entry).toHaveProperty('claims');
      expect(entry).toHaveProperty('accuracy');
    });
  });

  describe('edge cases', () => {
    test('handles empty store gracefully', () => {
      const leaderboard = store.getLeaderboard(10);
      expect(leaderboard).toEqual([]);
    });

    test('handles special characters in agent IDs', () => {
      const weirdId = 'agent:with/special\\chars@123';
      store.recordClaim(weirdId, 'claim-1');
      
      const rep = store.getReputation(weirdId);
      expect(rep.claims).toBe(1);
    });

    test('clear removes all data', () => {
      store.recordClaim('agent-1', 'claim-1');
      store.recordClaim('agent-2', 'claim-1');
      
      store.clear();
      
      expect(store.getAllAgents()).toEqual([]);
    });
  });
});
