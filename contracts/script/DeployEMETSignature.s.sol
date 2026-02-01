// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Script, console} from "forge-std/Script.sol";
import {EMETSignature} from "../src/EMETSignature.sol";

contract DeployEMETSignature is Script {
    // Deployed EMETRegistry on Base mainnet
    address constant REGISTRY = 0x9D2550eB1Ee613E0f35c70524e1304B26392b0aC;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        EMETSignature sig = new EMETSignature(REGISTRY);
        
        console.log("EMETSignature deployed at:", address(sig));
        console.log("Registry:", REGISTRY);
        console.log("DOMAIN_SEPARATOR:", vm.toString(sig.DOMAIN_SEPARATOR()));
        
        vm.stopBroadcast();
    }
}
