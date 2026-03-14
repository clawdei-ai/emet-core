/**
 * EMET Protocol — Envio HyperIndex Handlers
 *
 * TypeScript port of The Graph AssemblyScript handlers.
 * Indexes EMETReputation, EMETStake, EMETChallengeV3 on Base mainnet.
 *
 * Contracts:
 *   EMETReputation  0x358a775b74f9369D23Ce95EDa57dcbA39A1F4d4e
 *   EMETStake       0xb4A3Cf08194E445db65862Fb92bbC0cE587345bb
 *   EMETChallengeV3 0x12062513c3d41e5D4f0A0f2B079712D758f11EfC
 *
 * @author Clawdei × @JeanClawd99
 * @date   2026-03-14
 */

import {
  EMETReputation,
  EMETStake,
  EMETChallengeV3,
  Agent,
  ReputationEvent,
  Stake,
  Challenge,
  Vote,
  Protocol,
} from "generated";

// ── Constants ──────────────────────────────────────────────────────────────

const PROTOCOL_ID = "EMET_PROTOCOL";

// ── Helpers ────────────────────────────────────────────────────────────────

function computeEmetScore(
  reputation: bigint,
  slashCount: number,
  taskCount: number
): number {
  const base = 50;
  const repI32 = Number(reputation);
  const repBonus = Math.min(repI32 > 0 ? Math.floor(repI32 / 5) : 0, 30);
  const slashPenalty = Math.min(slashCount * 5, 50);
  const slashBps = taskCount > 0 ? Math.floor((slashCount * 10000) / taskCount) : 0;
  const ratioPenalty = Math.min(Math.floor(slashBps / 500), 30);
  return Math.max(0, Math.min(100, base + repBonus - slashPenalty - ratioPenalty));
}

function tierToString(tier: number): string {
  if (tier === 1) return "EXPEDITED";
  if (tier === 2) return "CRITICAL";
  return "STANDARD";
}

function voteToString(vote: number): string {
  if (vote === 1) return "DISMISS";
  if (vote === 2) return "ABSTAIN";
  return "UPHOLD";
}

function verdictToString(verdict: number): string {
  if (verdict === 1) return "DISMISSED";
  return "UPHELD";
}

async function loadOrCreateAgent(
  address: string,
  timestamp: bigint,
  context: any
): Promise<Agent> {
  const id = address.toLowerCase();
  let agent = await context.Agent.get(id);
  if (!agent) {
    agent = {
      id,
      reputation: 0n,
      slashCount: 0,
      taskCount: 0,
      stakeAmount: 0n,
      slashRatioBps: 0,
      emetScore: 50,
      firstSeen: timestamp,
      lastActive: timestamp,
    };
    // Increment protocol total agents
    const protocol = await loadOrCreateProtocol(context);
    context.Protocol.set({ ...protocol, totalAgents: protocol.totalAgents + 1 });
  }
  return agent as Agent;
}

async function loadOrCreateProtocol(context: any): Promise<Protocol> {
  let protocol = await context.Protocol.get(PROTOCOL_ID);
  if (!protocol) {
    protocol = {
      id: PROTOCOL_ID,
      totalAgents: 0,
      totalReputationEvents: 0,
      totalStakes: 0,
      totalChallenges: 0,
      totalResolved: 0,
      totalUpheld: 0,
      totalDismissed: 0,
      totalOutcomes: 0,
      lastBlock: 0n,
    };
  }
  return protocol as Protocol;
}

// ── EMETReputation handlers ────────────────────────────────────────────────

EMETReputation.ReputationUpdated.handler(async ({ event, context }) => {
  const { account, oldScore, newScore, delta, reason } = event.params;
  const timestamp = BigInt(event.block.timestamp);
  const blockNumber = BigInt(event.block.number);

  const agent = await loadOrCreateAgent(account, timestamp, context);

  const updatedAgent: Agent = {
    ...agent,
    reputation: newScore,
    lastActive: timestamp,
    emetScore: computeEmetScore(newScore, agent.slashCount, agent.taskCount),
  };
  context.Agent.set(updatedAgent);

  // Audit trail
  const repEventId = `${event.transaction.hash}-${event.logIndex}`;
  const repEvent: ReputationEvent = {
    id: repEventId,
    agent_id: agent.id,
    oldScore,
    newScore,
    delta,
    reason,
    timestamp,
    blockNumber,
    txHash: event.transaction.hash,
  };
  context.ReputationEvent.set(repEvent);

  // Protocol counters
  const protocol = await loadOrCreateProtocol(context);
  context.Protocol.set({
    ...protocol,
    totalReputationEvents: protocol.totalReputationEvents + 1,
    lastBlock: blockNumber,
  });
});

// ── EMETStake handlers ─────────────────────────────────────────────────────

EMETStake.Staked.handler(async ({ event, context }) => {
  const { claimId, staker, amount, isFor } = event.params;
  const timestamp = BigInt(event.block.timestamp);
  const blockNumber = BigInt(event.block.number);

  const agent = await loadOrCreateAgent(staker, timestamp, context);

  context.Agent.set({
    ...agent,
    stakeAmount: agent.stakeAmount + amount,
    lastActive: timestamp,
  });

  const stakeId = `${event.transaction.hash}-${event.logIndex}`;
  const stake: Stake = {
    id: stakeId,
    claimId,
    staker_id: agent.id,
    amount,
    isFor,
    withdrawn: false,
    timestamp,
    txHash: event.transaction.hash,
  };
  context.Stake.set(stake);

  const protocol = await loadOrCreateProtocol(context);
  context.Protocol.set({
    ...protocol,
    totalStakes: protocol.totalStakes + 1,
    lastBlock: blockNumber,
  });
});

EMETStake.Withdrawn.handler(async ({ event, context }) => {
  const { staker, amount } = event.params;
  const timestamp = BigInt(event.block.timestamp);

  const agent = await loadOrCreateAgent(staker, timestamp, context);

  const newStakeAmount =
    agent.stakeAmount >= amount ? agent.stakeAmount - amount : 0n;

  context.Agent.set({
    ...agent,
    stakeAmount: newStakeAmount,
    lastActive: timestamp,
  });
});

// ── EMETChallengeV3 handlers ───────────────────────────────────────────────

EMETChallengeV3.ChallengeCreated.handler(async ({ event, context }) => {
  const {
    challengeId,
    claimId,
    challenger,
    evidence,
    stake,
    tier,
    votingEnd,
  } = event.params;
  const timestamp = BigInt(event.block.timestamp);
  const blockNumber = BigInt(event.block.number);

  const challengerAgent = await loadOrCreateAgent(challenger, timestamp, context);

  const challenge: Challenge = {
    id: challengeId.toString(),
    claimId,
    challenger_id: challengerAgent.id,
    evidence,
    stake,
    tier: tierToString(tier),
    votingEnd: BigInt(votingEnd),
    verdict: "NONE",
    winner: null,
    winnerPayout: null,
    jurorPayout: null,
    createdAt: timestamp,
    resolvedAt: null,
  };
  context.Challenge.set(challenge);

  const protocol = await loadOrCreateProtocol(context);
  context.Protocol.set({
    ...protocol,
    totalChallenges: protocol.totalChallenges + 1,
    lastBlock: blockNumber,
  });
});

EMETChallengeV3.VoteCast.handler(async ({ event, context }) => {
  const { challengeId, juror, vote, reasoning } = event.params;
  const timestamp = BigInt(event.block.timestamp);

  const voteId = `${event.transaction.hash}-${event.logIndex}`;
  const voteRecord: Vote = {
    id: voteId,
    challenge_id: challengeId.toString(),
    juror,
    vote: voteToString(vote),
    reasoning,
    timestamp,
    txHash: event.transaction.hash,
  };
  context.Vote.set(voteRecord);
});

EMETChallengeV3.ChallengeResolved.handler(async ({ event, context }) => {
  const {
    challengeId,
    verdict,
    winner,
    winnerPayout,
    jurorPayout,
  } = event.params;
  const timestamp = BigInt(event.block.timestamp);
  const blockNumber = BigInt(event.block.number);

  const challenge = await context.Challenge.get(challengeId.toString());
  if (!challenge) return;

  const verdictStr = verdictToString(verdict);
  context.Challenge.set({
    ...challenge,
    verdict: verdictStr,
    winner,
    winnerPayout,
    jurorPayout,
    resolvedAt: timestamp,
  });

  // If UPHELD: challenger won, claim submitter gets slashed.
  // The EMETReputation.ReputationUpdated event handles agent score update.
  // Here we only track global protocol stats.
  const protocol = await loadOrCreateProtocol(context);
  context.Protocol.set({
    ...protocol,
    totalResolved: protocol.totalResolved + 1,
    totalUpheld:
      verdictStr === "UPHELD"
        ? protocol.totalUpheld + 1
        : protocol.totalUpheld,
    totalDismissed:
      verdictStr === "DISMISSED"
        ? protocol.totalDismissed + 1
        : protocol.totalDismissed,
    lastBlock: blockNumber,
  });
});

EMETChallengeV3.ChallengeAppealed.handler(async ({ event, context }) => {
  // Intentionally minimal: appeals don't modify schema entities yet.
  // Future: add Appeal entity when @JeanClawd99 confirms AgentGrid needs it.
  void event;
  void context;
});
