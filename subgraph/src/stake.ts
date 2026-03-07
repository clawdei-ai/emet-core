import { BigInt } from "@graphprotocol/graph-ts";
import { Staked, Withdrawn } from "../generated/EMETStake/EMETStake";
import { Stake } from "../generated/schema";
import { loadOrCreateAgent, loadOrCreateProtocol } from "./helpers";

/**
 * Handle EMETStake.Staked(claimId, staker, amount, isFor)
 */
export function handleStaked(event: Staked): void {
  let agent = loadOrCreateAgent(event.params.staker, event.block.timestamp);

  // Update agent stake total
  agent.stakeAmount = agent.stakeAmount.plus(event.params.amount);
  agent.lastActive  = event.block.timestamp;
  agent.save();

  // Create Stake record
  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let stake = new Stake(id);
  stake.claimId   = event.params.claimId;
  stake.staker    = agent.id;
  stake.amount    = event.params.amount;
  stake.isFor     = event.params.isFor;
  stake.withdrawn = false;
  stake.timestamp = event.block.timestamp;
  stake.txHash    = event.transaction.hash;
  stake.save();

  // Protocol counter
  let protocol = loadOrCreateProtocol();
  protocol.totalStakes += 1;
  protocol.lastBlock = event.block.number;
  protocol.save();
}

/**
 * Handle EMETStake.Withdrawn(claimId, staker, amount)
 *
 * Marks the matching Stake as withdrawn and decrements the agent's stakeAmount.
 * We find the stake by scanning agent stakes — for a prod subgraph you'd
 * maintain a claimId→stakeId mapping, but this keeps the schema minimal.
 */
export function handleWithdrawn(event: Withdrawn): void {
  let agent = loadOrCreateAgent(event.params.staker, event.block.timestamp);

  // Decrement agent stake amount (floor at 0)
  if (agent.stakeAmount.ge(event.params.amount)) {
    agent.stakeAmount = agent.stakeAmount.minus(event.params.amount);
  } else {
    agent.stakeAmount = BigInt.fromI32(0);
  }
  agent.lastActive = event.block.timestamp;
  agent.save();
}
