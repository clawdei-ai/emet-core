import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import { Agent, Protocol } from "../generated/schema";

// ── Agent helpers ────────────────────────────────────────────────────────────

export function loadOrCreateAgent(address: Bytes, timestamp: BigInt): Agent {
  let id = address.toHexString();
  let agent = Agent.load(id);
  if (!agent) {
    agent = new Agent(id);
    agent.reputation     = BigInt.fromI32(0);
    agent.slashCount     = 0;
    agent.taskCount      = 0;
    agent.stakeAmount    = BigInt.fromI32(0);
    agent.slashRatioBps  = 0;
    agent.emetScore      = 50;           // new agents start at 50/100
    agent.firstSeen      = timestamp;
    agent.lastActive     = timestamp;
    agent.save();

    // Increment global counter
    let protocol = loadOrCreateProtocol();
    protocol.totalAgents += 1;
    protocol.save();
  }
  return agent as Agent;
}

/**
 * Recompute the EMET score from raw stats.
 * Mirrors emet-agent-gate.js scoring logic.
 *
 *   base        = 50
 *   +reputation bonus (capped at +30)
 *   -slash penalty (5 per slash, capped at -50)
 *   -slash ratio penalty (slashBps × 0.002, capped at -30)
 *
 * Result clamped to [0, 100].
 */
export function computeEmetScore(
  reputation: BigInt,
  slashCount: i32,
  taskCount: i32
): i32 {
  let base = 50;

  // Reputation bonus: +1 per 5 points, max +30
  let repI32 = reputation.toI32();
  let repBonus = repI32 > 0 ? repI32 / 5 : 0;
  if (repBonus > 30) repBonus = 30;

  // Slash penalty: -5 per slash, max -50
  let slashPenalty = slashCount * 5;
  if (slashPenalty > 50) slashPenalty = 50;

  // Slash ratio penalty: slashBps × 0.002 = slashBps / 500, max -30
  let slashBps = taskCount > 0 ? (slashCount * 10000) / taskCount : 0;
  let ratioPenalty = slashBps / 500;
  if (ratioPenalty > 30) ratioPenalty = 30;

  let score = base + repBonus - slashPenalty - ratioPenalty;
  if (score < 0) score = 0;
  if (score > 100) score = 100;
  return score;
}

// ── Protocol helpers ─────────────────────────────────────────────────────────

export function loadOrCreateProtocol(): Protocol {
  let protocol = Protocol.load("EMET_PROTOCOL");
  if (!protocol) {
    protocol = new Protocol("EMET_PROTOCOL");
    protocol.totalAgents           = 0;
    protocol.totalReputationEvents = 0;
    protocol.totalStakes           = 0;
    protocol.totalChallenges       = 0;
    protocol.totalResolved         = 0;
    protocol.totalUpheld           = 0;
    protocol.totalDismissed        = 0;
    protocol.totalOutcomes         = 0;
    protocol.lastBlock             = BigInt.fromI32(0);
  }
  return protocol as Protocol;
}
