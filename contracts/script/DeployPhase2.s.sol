// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Script, console} from "forge-std/Script.sol";
import {EMETPrecedent} from "../src/EMETPrecedent.sol";
import {EMETLPRewards} from "../src/EMETLPRewards.sol";
import {EMETTreasury} from "../src/EMETTreasury.sol";

/// @title DeployPhase2 — Deploy EMETPrecedent and EMETLPRewards to Base mainnet
/// @notice Wires them into the existing protocol stack
///
///   Deployed addresses (from DEPLOYMENTS.md):
///     ChallengeV3 v3 : 0x12062513c3d41e5D4f0A0f2B079712D758f11EfC
///     Treasury        : 0xe1230E68818CCE66275Ad95E1bC79517Ac1ae502
///
///   External addresses (Base mainnet):
///     UniV3 NonfungiblePositionManager : 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1
///     EMET token                       : 0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C
///     WETH on Base                     : 0x4200000000000000000000000000000000000006
///     EMET/WETH pool fee tier          : 10000 (1%)
contract DeployPhase2 is Script {
    // Existing protocol contracts
    address constant CHALLENGE_V3    = 0x12062513c3d41e5D4f0A0f2B079712D758f11EfC;
    address constant TREASURY        = 0xe1230E68818CCE66275Ad95E1bC79517Ac1ae502;

    // External Base mainnet addresses
    address constant POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
    address constant EMET_TOKEN       = 0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C;
    address constant WETH             = 0x4200000000000000000000000000000000000006;
    uint24  constant POOL_FEE_TIER    = 10000; // 1% — confirmed from pool.fee()

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy EMETPrecedent
        EMETPrecedent precedent = new EMETPrecedent();
        console.log("EMETPrecedent deployed:", address(precedent));

        // 2. Wire EMETPrecedent: set recorder to ChallengeV3
        precedent.setRecorder(CHALLENGE_V3);
        console.log("EMETPrecedent.recorder set to ChallengeV3:", CHALLENGE_V3);

        // 3. Deploy EMETLPRewards
        EMETLPRewards lpRewards = new EMETLPRewards(
            POSITION_MANAGER,
            EMET_TOKEN,
            WETH,
            POOL_FEE_TIER,
            TREASURY
        );
        console.log("EMETLPRewards deployed:", address(lpRewards));

        // 4. Wire EMETLPRewards into Treasury (set-once guard in Treasury)
        EMETTreasury(TREASURY).setLPRewardsContract(address(lpRewards));
        console.log("Treasury.lpRewardsContract set to:", address(lpRewards));

        vm.stopBroadcast();

        console.log("\n=== Phase 2 Deployment Complete ===");
        console.log("EMETPrecedent :", address(precedent));
        console.log("EMETLPRewards :", address(lpRewards));
        console.log("Both wired into existing protocol stack.");
    }
}
