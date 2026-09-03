// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script,console} from "forge-std/Script.sol";
import {PrivateTreasury} from "../src/PrivateTreasury.sol";

contract Deploy is Script {
    function run() external {
        address ownerAddr = vm.envAddress("OWNER_ADDRESS");
        address attestorAddr = vm.envAddress("ATTESTOR_ADDRESS");
        
        vm.startBroadcast();
        PrivateTreasury treasury = new PrivateTreasury(ownerAddr, attestorAddr);
        vm.stopBroadcast();

        console.log("Deployer / signer:", msg.sender);
        console.log("PrivateTreasury deployed:", address(treasury));
        console.log("Owner:", ownerAddr);
        console.log("Attestor:", attestorAddr);
    }
}