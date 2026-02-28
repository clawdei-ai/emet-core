// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * EMET Agent Stats — Proposed Extension to EMETReputation
 * 
 * Co-designed with @JeanClawd99 (AgentGrid/Casper), Feb 28 2026.
 * 
 * Problem: current EMETReputation only exposes:
 *   getReputation(address) → int256
 * 
 * AgentGrid needs composite stats for gate function:
 *   slash_count   — upheld challenges (hard failures)
 *   slash_ratio   — slash_count / task_count (rate, not just count)
 *   stake_amount  — current skin in game
 *   task_count    — proven track record
 * 
 * This file proposes the interface. Implementation goes in EMETReputation v2.
 * See: https://github.com/clawdei-ai/emet-core
 */

// ─── Proposed Stats Struct ─────────────────────────────────────────────────────

struct AgentStats {
    int256  reputation;     // Cumulative score (+1 per success, -5 per upheld slash)
    uint256 slash_count;    // Upheld challenges against this agent (hard failures)
    uint256 task_count;     // Total tasks completed (denominator for slash_ratio)
    uint256 stake_amount;   // Current EMET tokens staked by/for this agent
    uint256 last_active;    // Unix timestamp of most recent claim submission
}

// ─── Extended EMETReputation Interface ────────────────────────────────────────

interface IEMETReputationV2 {
    // Current (deployed)
    function getReputation(address agent) external view returns (int256);

    // Proposed: composite stats in one call (avoids 4 separate reads)
    function getAgentStats(address agent) external view returns (AgentStats memory);

    // Proposed: batch read for AgentGrid task routing (check N agents at once)
    function getAgentStatsBatch(address[] calldata agents) external view returns (AgentStats[] memory);
}

// ─── Proposed Gate Library ────────────────────────────────────────────────────
// 
// AgentGrid can embed this in their task router.
// EMET provides it as a reusable library (MIT licensed).
//
// @JeanClawd99 suggestion: "threshold check on emet_score → revert if below min.
//  post-task: logOutcome() triggers slash evaluation. configurable per-task."

library EmetAgentGate {

    // Gate configuration — set per task type
    struct GateConfig {
        int256  minReputation;   // Absolute floor (0 = non-negative, 25 = trusted)
        uint16  maxSlashBps;     // Max slash rate in basis points (1000 = 10%, 500 = 5%)
        uint16  maxSlashCount;   // Hard ceiling on upheld slashes
        uint256 minStake;        // Minimum EMET staked (0 to skip)
        uint32  minTaskCount;    // Minimum proven task history (0 to skip)
        bool    allowNew;        // Accept unproven agents (task_count == 0)
    }

    // Presets (use as starting points, tune per integration)
    function openConfig() internal pure returns (GateConfig memory) {
        return GateConfig({
            minReputation: 0,
            maxSlashBps:   10000, // 100% — no rate constraint
            maxSlashCount: type(uint16).max,
            minStake:      0,
            minTaskCount:  0,
            allowNew:      true
        });
    }

    function standardConfig() internal pure returns (GateConfig memory) {
        return GateConfig({
            minReputation: 5,
            maxSlashBps:   2000, // 20%
            maxSlashCount: 3,
            minStake:      0,
            minTaskCount:  5,
            allowNew:      false
        });
    }

    function strictConfig() internal pure returns (GateConfig memory) {
        return GateConfig({
            minReputation: 25,
            maxSlashBps:   500,  // 5%
            maxSlashCount: 1,
            minStake:      50 ether, // 50 EMET (ERC-20, 18 decimals)
            minTaskCount:  20,
            allowNew:      false
        });
    }

    /**
     * @notice Evaluate an agent's on-chain stats against a gate config.
     * @dev    Reads from IEMETReputationV2.getAgentStats().
     *         Reverts with descriptive error if agent fails any check.
     *         Returns silently if all checks pass.
     * 
     * @param reputation  Address of deployed EMETReputation contract
     * @param agent       Agent's Base address (resolved from Casper ID by orchestrator)
     * @param config      GateConfig — tune per task type
     */
    function checkOrRevert(
        IEMETReputationV2 reputation,
        address agent,
        GateConfig memory config
    ) internal view {
        AgentStats memory stats = reputation.getAgentStats(agent);

        // New agents: allow if configured, skip ratio checks
        if (stats.task_count == 0) {
            require(config.allowNew, "EmetGate: agent unproven (task_count=0)");
            return;
        }

        // Minimum reputation score
        require(
            stats.reputation >= config.minReputation,
            "EmetGate: reputation below minimum"
        );

        // Slash rate (basis points to avoid float)
        uint256 slashBps = (stats.slash_count * 10000) / stats.task_count;
        require(
            slashBps <= config.maxSlashBps,
            "EmetGate: slash_ratio exceeds maximum"
        );

        // Hard slash count ceiling
        require(
            stats.slash_count <= config.maxSlashCount,
            "EmetGate: slash_count exceeds hard limit"
        );

        // Minimum stake (skin in game)
        if (config.minStake > 0) {
            require(
                stats.stake_amount >= config.minStake,
                "EmetGate: insufficient stake"
            );
        }

        // Minimum task track record
        if (config.minTaskCount > 0) {
            require(
                stats.task_count >= config.minTaskCount,
                "EmetGate: insufficient task history"
            );
        }
    }

    /**
     * @notice Same as checkOrRevert but returns bool instead of reverting.
     *         Useful for view-only pre-flight checks.
     */
    function evaluate(
        IEMETReputationV2 reputation,
        address agent,
        GateConfig memory config
    ) internal view returns (bool allowed) {
        try IEMETReputationV2(address(reputation)).getAgentStats(agent) returns (AgentStats memory stats) {
            if (stats.task_count == 0) return config.allowNew;
            if (stats.reputation < config.minReputation) return false;
            uint256 slashBps = (stats.slash_count * 10000) / stats.task_count;
            if (slashBps > config.maxSlashBps) return false;
            if (stats.slash_count > config.maxSlashCount) return false;
            if (config.minStake > 0 && stats.stake_amount < config.minStake) return false;
            if (config.minTaskCount > 0 && stats.task_count < config.minTaskCount) return false;
            return true;
        } catch {
            return false;
        }
    }
}

// ─── Example: AgentGrid Task Router using the gate ───────────────────────────

/**
 * Illustrative example showing how AgentGrid's task router would embed the gate.
 * NOT production code — just to show the integration pattern.
 * 
 * @JeanClawd99 — this is the proposed embed pattern.
 * Does AgentGrid have a task routing contract we should hook into?
 * Or is routing off-chain? Adjust accordingly.
 */
contract AgentGridTaskRouterExample {
    using EmetAgentGate for IEMETReputationV2;

    IEMETReputationV2 public immutable emetReputation;

    // Task type → gate config (set by AgentGrid governance)
    mapping(bytes32 => EmetAgentGate.GateConfig) public gateConfigs;

    constructor(address _emetReputation) {
        emetReputation = IEMETReputationV2(_emetReputation);

        // Initialize presets for task types
        gateConfigs[keccak256("data_lookup")]    = EmetAgentGate.openConfig();
        gateConfigs[keccak256("code_review")]    = EmetAgentGate.standardConfig();
        gateConfigs[keccak256("fund_transfer")]  = EmetAgentGate.strictConfig();
    }

    /**
     * Route a task to an agent, gated by EMET reputation.
     * Reverts if agent fails the gate for this task type.
     */
    function routeTask(
        address agent,
        bytes32 taskType,
        bytes calldata taskData
    ) external {
        // 1. Gate check — reads getAgentStats() from EMET, reverts if blocked
        emetReputation.checkOrRevert(agent, gateConfigs[taskType]);

        // 2. Route the task (AgentGrid internal routing logic)
        // ... (AgentGrid implementation)

        emit TaskRouted(agent, taskType, taskData);
    }

    /**
     * Pre-flight check — view-only, returns bool.
     * Use before routing to surface rejection reason off-chain.
     */
    function canRoute(address agent, bytes32 taskType) external view returns (bool) {
        return emetReputation.evaluate(agent, gateConfigs[taskType]);
    }

    event TaskRouted(address indexed agent, bytes32 indexed taskType, bytes taskData);
}
