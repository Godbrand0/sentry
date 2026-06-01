// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {ReputationAggregator} from "../src/reactive/ReputationAggregator.sol";
import {RedistributionScheduler} from "../src/reactive/RedistributionScheduler.sol";

/// @notice Deploy Reactive Network contracts to Reactive Kopli.
/// Usage: forge script script/DeployReactive.s.sol --rpc-url $REACTIVE_RPC_URL --broadcast
contract DeployReactive is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER");
        address subscriptionService = vm.envAddress("REACTIVE_SUBSCRIPTION_SERVICE");

        vm.startBroadcast(deployer);

        ReputationAggregator aggregator = new ReputationAggregator(subscriptionService, deployer);
        console2.log("ReputationAggregator:", address(aggregator));

        RedistributionScheduler scheduler = new RedistributionScheduler(subscriptionService, deployer);
        console2.log("RedistributionScheduler:", address(scheduler));

        vm.stopBroadcast();
    }
}
