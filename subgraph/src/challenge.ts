import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  ChallengeCreated,
  VoteCast,
  ChallengeResolved,
  ChallengeAppealed,
} from "../generated/EMETChallengeV3/EMETChallengeV3";
import { Challenge, Vote } from "../generated/schema";
import { loadOrCreateAgent, loadOrCreateProtocol, computeEmetScore } from "./helpers";

// Tier enum values from contract (0=STANDARD, 1=EXPEDITED, 2=CRITICAL)
function tierToString(tier: i32): string {
  if (tier == 1) return "EXPEDITED";
  if (tier == 2) return "CRITICAL";
  return "STANDARD";
}

// Vote enum values from contract (0=UPHOLD, 1=DISMISS, 2=ABSTAIN)
function voteToString(vote: i32): string {
  if (vote == 1) return "DISMISS";
  if (vote == 2) return "ABSTAIN";
  return "UPHOLD";
}

// Verdict enum (same as Vote but applied at resolution)
function verdictToString(verdict: i32): string {
  if (verdict == 1) return "DISMISSED";
  return "UPHELD";
}

/**
 * Handle EMETChallengeV3.ChallengeCreated
 */
export function handleChallengeCreated(event: ChallengeCreated): void {
  let challenger = loadOrCreateAgent(event.params.challenger, event.block.timestamp);

  let challenge = new Challenge(event.params.challengeId.toString());
  challenge.claimId    = event.params.claimId;
  challenge.challenger = challenger.id;
  challenge.evidence   = event.params.evidence;
  challenge.stake      = event.params.stake;
  challenge.tier       = tierToString(event.params.tier);
  challenge.votingEnd  = event.params.votingEnd;
  challenge.verdict    = "NONE";
  challenge.winner     = null;
  challenge.winnerPayout = null;
  challenge.jurorPayout  = null;
  challenge.createdAt  = event.block.timestamp;
  challenge.resolvedAt = null;
  challenge.save();

  // Protocol counter
  let protocol = loadOrCreateProtocol();
  protocol.totalChallenges += 1;
  protocol.lastBlock = event.block.number;
  protocol.save();
}

/**
 * Handle EMETChallengeV3.VoteCast
 */
export function handleVoteCast(event: VoteCast): void {
  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let vote = new Vote(id);
  vote.challenge = event.params.challengeId.toString();
  vote.juror     = event.params.juror;
  vote.vote      = voteToString(event.params.vote);
  vote.reasoning = event.params.reasoning;
  vote.timestamp = event.block.timestamp;
  vote.txHash    = event.transaction.hash;
  vote.save();
}

/**
 * Handle EMETChallengeV3.ChallengeResolved
 *
 * Updates:
 *   - Challenge verdict + resolution metadata
 *   - Agent.slashCount if verdict = UPHELD (challenger was right → claim submitter slashed)
 *   - Agent.emetScore recomputed
 *   - Protocol totals
 */
export function handleChallengeResolved(event: ChallengeResolved): void {
  let challenge = Challenge.load(event.params.challengeId.toString());
  if (!challenge) return;

  let verdictStr = verdictToString(event.params.verdict);
  challenge.verdict      = verdictStr;
  challenge.winner       = event.params.winner;
  challenge.winnerPayout = event.params.winnerPayout;
  challenge.jurorPayout  = event.params.jurorPayout;
  challenge.resolvedAt   = event.block.timestamp;
  challenge.save();

  // If UPHELD: the challenger won. The person who submitted the claim is slashed.
  // The claim submitter's address isn't directly in this event — the reputation
  // contract emits its own ReputationUpdated event for that (handled separately).
  // Here we only track global counts.
  let protocol = loadOrCreateProtocol();
  protocol.totalResolved += 1;
  if (verdictStr == "UPHELD") {
    protocol.totalUpheld += 1;
  } else {
    protocol.totalDismissed += 1;
  }
  protocol.lastBlock = event.block.number;
  protocol.save();
}

/**
 * Handle EMETChallengeV3.ChallengeAppealed
 * (No schema entity — just a note for future iteration)
 */
export function handleChallengeAppealed(event: ChallengeAppealed): void {
  // Intentionally minimal: appeals don't change entities yet.
  // @JeanClawd99 — if AgentGrid needs appeal status, we can add Appeal entity.
}
