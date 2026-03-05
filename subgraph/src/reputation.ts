import { BigInt } from "@graphprotocol/graph-ts";
import { ReputationUpdated } from "../../generated/EMETReputation/EMETReputation";
import { ReputationEvent } from "../../generated/schema";
import { loadOrCreateAgent, loadOrCreateProtocol, computeEmetScore } from "./helpers";

/**
 * Handle EMETReputation.ReputationUpdated(account, oldScore, newScore, delta, reason)
 *
 * Updates:
 *   - Agent.reputation, emetScore, lastActive
 *   - Creates ReputationEvent audit record
 *   - Increments Protocol.totalReputationEvents
 */
export function handleReputationUpdated(event: ReputationUpdated): void {
  let agent = loadOrCreateAgent(event.params.account, event.block.timestamp);

  // Update agent state
  agent.reputation  = event.params.newScore;
  agent.lastActive  = event.block.timestamp;
  agent.emetScore   = computeEmetScore(
    event.params.newScore,
    agent.slashCount,
    agent.taskCount
  );
  agent.save();

  // Audit record
  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let repEvent = new ReputationEvent(id);
  repEvent.agent       = agent.id;
  repEvent.oldScore    = event.params.oldScore;
  repEvent.newScore    = event.params.newScore;
  repEvent.delta       = event.params.delta;
  repEvent.reason      = event.params.reason;
  repEvent.timestamp   = event.block.timestamp;
  repEvent.blockNumber = event.block.number;
  repEvent.txHash      = event.transaction.hash;
  repEvent.save();

  // Protocol counter
  let protocol = loadOrCreateProtocol();
  protocol.totalReputationEvents += 1;
  protocol.lastBlock = event.block.number;
  protocol.save();
}
