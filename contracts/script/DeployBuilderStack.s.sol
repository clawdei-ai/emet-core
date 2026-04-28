// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Script, console} from "forge-std/Script.sol";
import {EMETAgentProfile} from "../src/EMETAgentProfile.sol";
import {EMETTrustGate} from "../src/EMETTrustGate.sol";
import {EMETScorecard} from "../src/EMETScorecard.sol";

/// @title DeployBuilderStack — Deploy builder-facing trust integration contracts
/// @notice Deploys the v0.14-v0.16 stack used by SDK v1.1.0:
///         AgentProfile -> TrustGate -> Scorecard.
///
/// Required env:
///   PRIVATE_KEY     deployer key
///   EMET_REPUTATION deployed EMETReputation address
///   EMET_CHALLENGE  deployed EMETChallengeV3 address to authorize as profile updater
contract DeployBuilderStack is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address reputation = vm.envAddress("EMET_REPUTATION");
        address challenge = vm.envAddress("EMET_CHALLENGE");

        vm.startBroadcast(deployerPrivateKey);

        EMETAgentProfile agentProfile = new EMETAgentProfile();
        console.log("EMETAgentProfile deployed:", address(agentProfile));

        agentProfile.setUpdater(challenge);
        console.log("EMETAgentProfile.updater set to:", challenge);

        EMETTrustGate trustGate = new EMETTrustGate(address(agentProfile), reputation);
        console.log("EMETTrustGate deployed:", address(trustGate));

        EMETScorecard scorecard = new EMETScorecard(address(agentProfile), reputation, address(trustGate));
        console.log("EMETScorecard deployed:", address(scorecard));

        vm.stopBroadcast();

        console.log("\n=== Builder Trust Stack Deployment Complete ===");
        console.log("EMETAgentProfile:", address(agentProfile));
        console.log("EMETTrustGate    :", address(trustGate));
        console.log("EMETScorecard    :", address(scorecard));
        console.log("EMETReputation   :", reputation);
        console.log("Profile updater  :", challenge);
        console.log("\nSDK config addresses:");
        console.log("  EMETAgentProfile:", address(agentProfile));
        console.log("  EMETTrustGate:", address(trustGate));
        console.log("  EMETScorecard:", address(scorecard));
        console.log("  EMETReputation:", reputation);
    }
}
