// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Script, console} from "forge-std/Script.sol";
import {EMETRegistry} from "../src/EMETRegistry.sol";
import {EMETStake} from "../src/EMETStake.sol";
import {EMETChallenge} from "../src/EMETChallenge.sol";
import {EMETChallengeV2} from "../src/EMETChallengeV2.sol";
import {EMETSignature} from "../src/EMETSignature.sol";
import {EMETTreasury} from "../src/EMETTreasury.sol";
import {EMETReputation} from "../src/EMETReputation.sol";

contract DeployAll is Script {
    uint256 constant MINIMUM_STAKE = 100e18;          // 100 EMET
    uint256 constant CHALLENGE_PERIOD = 7 days;
    uint256 constant MINIMUM_CHALLENGE_STAKE = 50e18;  // 50 EMET

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Registry (core - everything links to this)
        EMETRegistry registry = new EMETRegistry(MINIMUM_STAKE, CHALLENGE_PERIOD);
        console.log("EMETRegistry:", address(registry));

        // 2. Stake
        EMETStake stake = new EMETStake(address(registry));
        console.log("EMETStake:", address(stake));

        // 3. Treasury
        EMETTreasury treasury = new EMETTreasury(deployer);
        console.log("EMETTreasury:", address(treasury));

        // 4. Reputation
        EMETReputation reputation = new EMETReputation();
        console.log("EMETReputation:", address(reputation));

        // 5. Signature
        EMETSignature signature = new EMETSignature(address(registry));
        console.log("EMETSignature:", address(signature));

        // 6. ChallengeV2 (links to everything)
        EMETChallengeV2 challengeV2 = new EMETChallengeV2(
            address(registry),
            address(stake),
            address(treasury),
            address(reputation),
            address(signature),
            MINIMUM_CHALLENGE_STAKE
        );
        console.log("EMETChallengeV2:", address(challengeV2));

        // 7. Wire contracts together
        registry.setChallengeContract(address(challengeV2));
        stake.setChallengeContract(address(challengeV2));
        reputation.setUpdater(address(challengeV2));
        treasury.setFeeDistributor(address(challengeV2));

        console.log("--- All wired ---");
        console.log("Deployer:", deployer);

        vm.stopBroadcast();
    }
}
