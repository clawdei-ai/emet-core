/**
 * EMET Protocol - Governance Module Tests
 * 
 * Tests for dispute resolution and challenge system.
 */

const {
  createChallenge,
  selectJury,
  submitVote,
  resolveChallenge,
  createAppeal,
  getActiveChallenges,
  getChallengeHistory,
  getChallenge,
  ChallengeStatus,
  DisputeTier,
  VoteOption,
  PROTOCOL_FEE_PERCENT,
  MIN_JUROR_REPUTATION,
  _reset
} = require('../governance');

describe('Governance Module', () => {
  // Reset state before each test
  beforeEach(() => {
    _reset();
  });

  describe('createChallenge', () => {
    it('should create a challenge with valid parameters', () => {
      const challenge = createChallenge(
        'emet:agent:challenger-1',
        'emet:claim:target-claim',
        'The claim contradicts established facts',
        50
      );

      expect(challenge).toBeDefined();
      expect(challenge.id).toMatch(/^emet:challenge:/);
      expect(challenge.challengerId).toBe('emet:agent:challenger-1');
      expect(challenge.claimId).toBe('emet:claim:target-claim');
      expect(challenge.evidence).toBe('The claim contradicts established facts');
      expect(challenge.stake).toBe(50);
      expect(challenge.status).toBe(ChallengeStatus.PENDING);
      expect(challenge.tier).toBe(DisputeTier.MINOR);
      expect(challenge.jurors).toEqual([]);
      expect(challenge.verdict).toBeNull();
    });

    it('should throw error for missing challenger ID', () => {
      expect(() => {
        createChallenge(null, 'emet:claim:target', 'evidence', 50);
      }).toThrow('Challenger ID is required');
    });

    it('should throw error for missing claim ID', () => {
      expect(() => {
        createChallenge('emet:agent:challenger', null, 'evidence', 50);
      }).toThrow('Claim ID is required');
    });

    it('should throw error for missing evidence', () => {
      expect(() => {
        createChallenge('emet:agent:challenger', 'emet:claim:target', '', 50);
      }).toThrow('Evidence is required');
    });

    it('should throw error for invalid stake', () => {
      expect(() => {
        createChallenge('emet:agent:challenger', 'emet:claim:target', 'evidence', -10);
      }).toThrow('Stake must be a positive number');

      expect(() => {
        createChallenge('emet:agent:challenger', 'emet:claim:target', 'evidence', 0);
      }).toThrow('Stake must be a positive number');
    });

    it('should throw error for stake below tier minimum', () => {
      expect(() => {
        createChallenge('emet:agent:challenger', 'emet:claim:target', 'evidence', 5);
      }).toThrow(/below minimum.*MINOR tier/);
    });

    it('should throw error for stake above tier maximum', () => {
      expect(() => {
        createChallenge('emet:agent:challenger', 'emet:claim:target', 'evidence', 200);
      }).toThrow(/exceeds maximum.*MINOR tier/);
    });

    it('should create challenge with MAJOR tier', () => {
      const challenge = createChallenge(
        'emet:agent:challenger',
        'emet:claim:target',
        'evidence',
        500,
        { tier: 'MAJOR' }
      );

      expect(challenge.tier).toBe(DisputeTier.MAJOR);
      expect(challenge.stake).toBe(500);
    });

    it('should prevent duplicate active challenges on same claim', () => {
      createChallenge('emet:agent:challenger-1', 'emet:claim:same', 'evidence 1', 50);

      expect(() => {
        createChallenge('emet:agent:challenger-2', 'emet:claim:same', 'evidence 2', 60);
      }).toThrow(/already has an active challenge/);
    });

    it('should allow challenge after previous is resolved', () => {
      const challenge1 = createChallenge(
        'emet:agent:challenger-1',
        'emet:claim:target',
        'evidence 1',
        50
      );

      // Setup and resolve the challenge
      const reputationStore = {
        'emet:agent:juror-1': 80,
        'emet:agent:juror-2': 85,
        'emet:agent:juror-3': 90
      };
      selectJury(challenge1, reputationStore);
      submitVote(challenge1.id, 'emet:agent:juror-1', VoteOption.UPHOLD_CLAIM);
      submitVote(challenge1.id, 'emet:agent:juror-2', VoteOption.UPHOLD_CLAIM);
      submitVote(challenge1.id, 'emet:agent:juror-3', VoteOption.UPHOLD_CLAIM);
      resolveChallenge(challenge1.id);

      // Should now be able to create a new challenge
      const challenge2 = createChallenge(
        'emet:agent:challenger-2',
        'emet:claim:target',
        'new evidence',
        50
      );

      expect(challenge2).toBeDefined();
      expect(challenge2.claimId).toBe('emet:claim:target');
    });
  });

  describe('selectJury', () => {
    it('should select correct number of jurors for MINOR tier', () => {
      const challenge = createChallenge(
        'emet:agent:challenger',
        'emet:claim:target',
        'evidence',
        50
      );

      const reputationStore = {
        'emet:agent:juror-1': 80,
        'emet:agent:juror-2': 85,
        'emet:agent:juror-3': 90,
        'emet:agent:juror-4': 75,
        'emet:agent:juror-5': 95
      };

      const jurors = selectJury(challenge, reputationStore);

      expect(jurors.length).toBe(3); // MINOR tier = 3 jurors
      expect(challenge.status).toBe(ChallengeStatus.JURY_SELECTED);
      expect(challenge.jurors).toEqual(jurors);
    });

    it('should select correct number of jurors for MAJOR tier', () => {
      const challenge = createChallenge(
        'emet:agent:challenger',
        'emet:claim:target',
        'evidence',
        500,
        { tier: 'MAJOR' }
      );

      const reputationStore = {};
      for (let i = 1; i <= 10; i++) {
        reputationStore[`emet:agent:juror-${i}`] = 50 + i * 5;
      }

      const jurors = selectJury(challenge, reputationStore);

      expect(jurors.length).toBe(7); // MAJOR tier = 7 jurors
    });

    it('should respect minimum reputation threshold', () => {
      const challenge = createChallenge(
        'emet:agent:challenger',
        'emet:claim:target',
        'evidence',
        50
      );

      const reputationStore = {
        'emet:agent:juror-1': 30, // Below threshold
        'emet:agent:juror-2': 40, // Below threshold
        'emet:agent:juror-3': MIN_JUROR_REPUTATION,
        'emet:agent:juror-4': 60,
        'emet:agent:juror-5': 70
      };

      const jurors = selectJury(challenge, reputationStore);

      // Should not include low-reputation agents
      expect(jurors).not.toContain('emet:agent:juror-1');
      expect(jurors).not.toContain('emet:agent:juror-2');
    });

    it('should exclude challenger from jury selection', () => {
      const challenge = createChallenge(
        'emet:agent:challenger',
        'emet:claim:target',
        'evidence',
        50
      );

      const reputationStore = {
        'emet:agent:challenger': 95, // The challenger - should be excluded
        'emet:agent:juror-1': 80,
        'emet:agent:juror-2': 85,
        'emet:agent:juror-3': 90
      };

      const jurors = selectJury(challenge, reputationStore);

      expect(jurors).not.toContain('emet:agent:challenger');
    });

    it('should throw error when insufficient eligible jurors', () => {
      const challenge = createChallenge(
        'emet:agent:challenger',
        'emet:claim:target',
        'evidence',
        50
      );

      const reputationStore = {
        'emet:agent:juror-1': 80,
        'emet:agent:juror-2': 85
        // Only 2 eligible jurors, but MINOR tier needs 3
      };

      expect(() => {
        selectJury(challenge, reputationStore);
      }).toThrow(/Insufficient eligible jurors/);
    });

    it('should weight selection towards higher reputation agents', () => {
      const challenge = createChallenge(
        'emet:agent:challenger',
        'emet:claim:target',
        'evidence',
        50
      );

      // Create a pool with one very high rep and others at minimum
      const reputationStore = {
        'emet:agent:high-rep': 1000,
        'emet:agent:low-1': MIN_JUROR_REPUTATION,
        'emet:agent:low-2': MIN_JUROR_REPUTATION,
        'emet:agent:low-3': MIN_JUROR_REPUTATION,
        'emet:agent:low-4': MIN_JUROR_REPUTATION
      };

      // Run multiple selections to test weighting
      let highRepSelected = 0;
      const iterations = 100;

      for (let i = 0; i < iterations; i++) {
        _reset();
        const c = createChallenge('emet:agent:challenger', `emet:claim:${i}`, 'evidence', 50);
        const jurors = selectJury(c, reputationStore);
        if (jurors.includes('emet:agent:high-rep')) {
          highRepSelected++;
        }
      }

      // High-rep agent should be selected significantly more often than random chance
      // With 1000 vs 50*4=200 total, high-rep has ~83% of weight
      expect(highRepSelected).toBeGreaterThan(50); // Should be selected >50% of the time
    });
  });

  describe('submitVote', () => {
    let challenge;
    const reputationStore = {
      'emet:agent:juror-1': 80,
      'emet:agent:juror-2': 85,
      'emet:agent:juror-3': 90
    };

    beforeEach(() => {
      challenge = createChallenge(
        'emet:agent:challenger',
        'emet:claim:target',
        'evidence',
        50
      );
      selectJury(challenge, reputationStore);
    });

    it('should record a valid vote', () => {
      const jurorId = challenge.jurors[0];
      const voteRecord = submitVote(
        challenge.id,
        jurorId,
        VoteOption.UPHOLD_CHALLENGE,
        'The evidence is compelling'
      );

      expect(voteRecord).toBeDefined();
      expect(voteRecord.jurorId).toBe(jurorId);
      expect(voteRecord.vote).toBe(VoteOption.UPHOLD_CHALLENGE);
      expect(voteRecord.reasoning).toBe('The evidence is compelling');
      expect(voteRecord.hash).toBeDefined();
      expect(challenge.status).toBe(ChallengeStatus.VOTING);
    });

    it('should throw error for non-existent challenge', () => {
      expect(() => {
        submitVote('emet:challenge:nonexistent', 'emet:agent:juror', VoteOption.UPHOLD_CLAIM);
      }).toThrow('Challenge not found');
    });

    it('should throw error for non-juror voting', () => {
      expect(() => {
        submitVote(challenge.id, 'emet:agent:random', VoteOption.UPHOLD_CLAIM);
      }).toThrow('not a juror');
    });

    it('should throw error for duplicate votes', () => {
      const jurorId = challenge.jurors[0];
      submitVote(challenge.id, jurorId, VoteOption.UPHOLD_CLAIM);

      expect(() => {
        submitVote(challenge.id, jurorId, VoteOption.UPHOLD_CHALLENGE);
      }).toThrow('already voted');
    });

    it('should throw error for invalid vote option', () => {
      expect(() => {
        submitVote(challenge.id, challenge.jurors[0], 'invalid_vote');
      }).toThrow('Invalid vote');
    });

    it('should allow abstention', () => {
      const jurorId = challenge.jurors[0];
      const voteRecord = submitVote(challenge.id, jurorId, VoteOption.ABSTAIN);

      expect(voteRecord.vote).toBe(VoteOption.ABSTAIN);
    });
  });

  describe('resolveChallenge', () => {
    let challenge;
    const reputationStore = {
      'emet:agent:juror-1': 80,
      'emet:agent:juror-2': 85,
      'emet:agent:juror-3': 90
    };

    beforeEach(() => {
      challenge = createChallenge(
        'emet:agent:challenger',
        'emet:claim:target',
        'evidence',
        50
      );
      selectJury(challenge, reputationStore);
    });

    it('should resolve with majority uphold_claim verdict', () => {
      submitVote(challenge.id, challenge.jurors[0], VoteOption.UPHOLD_CLAIM, 'Claim is valid');
      submitVote(challenge.id, challenge.jurors[1], VoteOption.UPHOLD_CLAIM, 'Agree');
      submitVote(challenge.id, challenge.jurors[2], VoteOption.UPHOLD_CHALLENGE, 'Disagree');

      const result = resolveChallenge(challenge.id);

      expect(result.verdict).toBe(VoteOption.UPHOLD_CLAIM);
      expect(result.voteCounts[VoteOption.UPHOLD_CLAIM]).toBe(2);
      expect(result.voteCounts[VoteOption.UPHOLD_CHALLENGE]).toBe(1);
      expect(challenge.status).toBe(ChallengeStatus.RESOLVED);
    });

    it('should resolve with majority uphold_challenge verdict', () => {
      submitVote(challenge.id, challenge.jurors[0], VoteOption.UPHOLD_CHALLENGE);
      submitVote(challenge.id, challenge.jurors[1], VoteOption.UPHOLD_CHALLENGE);
      submitVote(challenge.id, challenge.jurors[2], VoteOption.UPHOLD_CLAIM);

      const result = resolveChallenge(challenge.id);

      expect(result.verdict).toBe(VoteOption.UPHOLD_CHALLENGE);
      expect(result.stakeDistribution.winner).toBe('emet:agent:challenger');
    });

    it('should calculate stake distribution correctly', () => {
      submitVote(challenge.id, challenge.jurors[0], VoteOption.UPHOLD_CHALLENGE);
      submitVote(challenge.id, challenge.jurors[1], VoteOption.UPHOLD_CHALLENGE);
      submitVote(challenge.id, challenge.jurors[2], VoteOption.UPHOLD_CHALLENGE);

      const result = resolveChallenge(challenge.id);

      // Stake is 50, protocol fee is 5%
      const expectedFee = Math.floor(50 * PROTOCOL_FEE_PERCENT / 100); // 2
      const expectedPayout = 50 - expectedFee; // 48

      expect(result.stakeDistribution.totalStake).toBe(50);
      expect(result.stakeDistribution.protocolFee).toBe(expectedFee);
      expect(result.stakeDistribution.winnerPayout).toBe(expectedPayout);
    });

    it('should handle tie by defaulting to uphold_claim', () => {
      // For a 3-juror panel, we need one abstain to create a tie
      submitVote(challenge.id, challenge.jurors[0], VoteOption.UPHOLD_CLAIM);
      submitVote(challenge.id, challenge.jurors[1], VoteOption.UPHOLD_CHALLENGE);
      submitVote(challenge.id, challenge.jurors[2], VoteOption.ABSTAIN);

      const result = resolveChallenge(challenge.id);

      expect(result.verdict).toBe('tie');
    });

    it('should handle all abstentions', () => {
      submitVote(challenge.id, challenge.jurors[0], VoteOption.ABSTAIN);
      submitVote(challenge.id, challenge.jurors[1], VoteOption.ABSTAIN);
      submitVote(challenge.id, challenge.jurors[2], VoteOption.ABSTAIN);

      const result = resolveChallenge(challenge.id);

      expect(result.verdict).toBe('no_verdict');
    });

    it('should throw error for already resolved challenge', () => {
      submitVote(challenge.id, challenge.jurors[0], VoteOption.UPHOLD_CLAIM);
      submitVote(challenge.id, challenge.jurors[1], VoteOption.UPHOLD_CLAIM);
      submitVote(challenge.id, challenge.jurors[2], VoteOption.UPHOLD_CLAIM);
      resolveChallenge(challenge.id);

      expect(() => {
        resolveChallenge(challenge.id);
      }).toThrow('already resolved');
    });

    it('should calculate juror rewards for majority voters', () => {
      submitVote(challenge.id, challenge.jurors[0], VoteOption.UPHOLD_CHALLENGE);
      submitVote(challenge.id, challenge.jurors[1], VoteOption.UPHOLD_CHALLENGE);
      submitVote(challenge.id, challenge.jurors[2], VoteOption.UPHOLD_CLAIM);

      const result = resolveChallenge(challenge.id);

      // 10% of stake goes to juror pool
      const jurorPool = Math.floor(50 * 0.1); // 5
      const rewardPerWinner = Math.floor(jurorPool / 2); // 2 winning jurors

      expect(result.stakeDistribution.jurorRewards[challenge.jurors[0]]).toBe(rewardPerWinner);
      expect(result.stakeDistribution.jurorRewards[challenge.jurors[1]]).toBe(rewardPerWinner);
      expect(result.stakeDistribution.jurorRewards[challenge.jurors[2]]).toBeUndefined();
    });
  });

  describe('createAppeal', () => {
    let originalChallenge;
    const reputationStore = {
      'emet:agent:juror-1': 80,
      'emet:agent:juror-2': 85,
      'emet:agent:juror-3': 90
    };

    beforeEach(() => {
      originalChallenge = createChallenge(
        'emet:agent:original-challenger',
        'emet:claim:target',
        'original evidence',
        50
      );
      selectJury(originalChallenge, reputationStore);
      submitVote(originalChallenge.id, originalChallenge.jurors[0], VoteOption.UPHOLD_CLAIM);
      submitVote(originalChallenge.id, originalChallenge.jurors[1], VoteOption.UPHOLD_CLAIM);
      submitVote(originalChallenge.id, originalChallenge.jurors[2], VoteOption.UPHOLD_CLAIM);
      resolveChallenge(originalChallenge.id);
    });

    it('should create appeal with higher stake requirement', () => {
      // MINOR tier has 2x appeal multiplier, so need 100
      const appeal = createAppeal(
        originalChallenge.id,
        'emet:agent:appellant',
        'new compelling evidence',
        100
      );

      expect(appeal).toBeDefined();
      expect(appeal.appealOf).toBe(originalChallenge.id);
      expect(appeal.stake).toBe(100);
      expect(originalChallenge.appealedTo).toBe(appeal.id);
    });

    it('should escalate to higher tier', () => {
      // Appeal from MINOR should go to MAJOR
      const appeal = createAppeal(
        originalChallenge.id,
        'emet:agent:appellant',
        'new evidence',
        200 // MAJOR tier minimum is 100
      );

      expect(appeal.tier).toBe(DisputeTier.MAJOR);
    });

    it('should throw error for insufficient appeal stake', () => {
      // MINOR tier needs 2x = 100, so 50 should fail
      expect(() => {
        createAppeal(
          originalChallenge.id,
          'emet:agent:appellant',
          'new evidence',
          50
        );
      }).toThrow(/below required/);
    });

    it('should throw error for unresolved challenge', () => {
      const unresolvedChallenge = createChallenge(
        'emet:agent:challenger',
        'emet:claim:other',
        'evidence',
        50
      );

      expect(() => {
        createAppeal(unresolvedChallenge.id, 'emet:agent:appellant', 'evidence', 100);
      }).toThrow('Can only appeal resolved challenges');
    });

    it('should throw error for already appealed challenge', () => {
      createAppeal(originalChallenge.id, 'emet:agent:appellant1', 'evidence 1', 100);

      expect(() => {
        createAppeal(originalChallenge.id, 'emet:agent:appellant2', 'evidence 2', 100);
      }).toThrow('already appealed');
    });
  });

  describe('getActiveChallenges', () => {
    it('should return only active challenges', () => {
      const active1 = createChallenge('emet:agent:c1', 'emet:claim:1', 'e1', 50);
      const active2 = createChallenge('emet:agent:c2', 'emet:claim:2', 'e2', 50);
      const toResolve = createChallenge('emet:agent:c3', 'emet:claim:3', 'e3', 50);

      // Resolve one challenge
      const reputationStore = {
        'emet:agent:j1': 80,
        'emet:agent:j2': 85,
        'emet:agent:j3': 90
      };
      selectJury(toResolve, reputationStore);
      submitVote(toResolve.id, toResolve.jurors[0], VoteOption.UPHOLD_CLAIM);
      submitVote(toResolve.id, toResolve.jurors[1], VoteOption.UPHOLD_CLAIM);
      submitVote(toResolve.id, toResolve.jurors[2], VoteOption.UPHOLD_CLAIM);
      resolveChallenge(toResolve.id);

      const active = getActiveChallenges();

      expect(active.length).toBe(2);
      expect(active.map(c => c.id)).toContain(active1.id);
      expect(active.map(c => c.id)).toContain(active2.id);
      expect(active.map(c => c.id)).not.toContain(toResolve.id);
    });
  });

  describe('getChallengeHistory', () => {
    it('should return full history for a claim', () => {
      const reputationStore = {
        'emet:agent:j1': 80,
        'emet:agent:j2': 85,
        'emet:agent:j3': 90
      };

      // Create and resolve first challenge
      const challenge1 = createChallenge('emet:agent:c1', 'emet:claim:target', 'e1', 50);
      selectJury(challenge1, reputationStore);
      submitVote(challenge1.id, challenge1.jurors[0], VoteOption.UPHOLD_CHALLENGE);
      submitVote(challenge1.id, challenge1.jurors[1], VoteOption.UPHOLD_CHALLENGE);
      submitVote(challenge1.id, challenge1.jurors[2], VoteOption.UPHOLD_CLAIM);
      resolveChallenge(challenge1.id);

      // Create and resolve appeal
      const appeal = createAppeal(challenge1.id, 'emet:agent:appellant', 'appeal evidence', 100);
      
      const history = getChallengeHistory('emet:claim:target');

      expect(history.claimId).toBe('emet:claim:target');
      expect(history.totalChallenges).toBe(2);
      expect(history.resolvedCount).toBe(1);
      expect(history.precedents.length).toBe(1);
      expect(history.precedents[0].verdict).toBe(VoteOption.UPHOLD_CHALLENGE);
    });

    it('should return empty history for unchallenged claim', () => {
      const history = getChallengeHistory('emet:claim:never-challenged');

      expect(history.challenges).toEqual([]);
      expect(history.precedents).toEqual([]);
      expect(history.totalChallenges).toBe(0);
    });
  });

  describe('Challenge serialization', () => {
    it('should serialize challenge to JSON correctly', () => {
      const challenge = createChallenge(
        'emet:agent:challenger',
        'emet:claim:target',
        'evidence',
        50
      );

      const json = challenge.toJSON();

      expect(json.id).toBe(challenge.id);
      expect(json.tier).toBe('minor');
      expect(json.votes).toEqual({});
      expect(typeof json.createdAt).toBe('string');
    });
  });
});
