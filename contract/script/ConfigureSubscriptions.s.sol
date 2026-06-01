// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {ReputationAggregator} from "../src/reactive/ReputationAggregator.sol";
import {RedistributionScheduler} from "../src/reactive/RedistributionScheduler.sol";

/// @notice Wire event subscriptions and destinations after all contracts are deployed.
/// Run this against Reactive Kopli after DeployReactive.s.sol and DeployHook.s.sol.
///
/// Required env vars:
///   DEPLOYER, AGGREGATOR, SCHEDULER,
///   UNICHAIN_CHAIN_ID, UNICHAIN_HOOK,
///   BASE_CHAIN_ID, BASE_HOOK,
///   UNICHAIN_ORACLE, BASE_ORACLE
contract ConfigureSubscriptions is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER");
        address aggregator = vm.envAddress("AGGREGATOR");
        address scheduler = vm.envAddress("SCHEDULER");

        uint256 unichainId = vm.envUint("UNICHAIN_CHAIN_ID");
        address unichainHook = vm.envAddress("UNICHAIN_HOOK");
        address unichainOracle = vm.envAddress("UNICHAIN_ORACLE");

        uint256 baseId = vm.envUint("BASE_CHAIN_ID");
        address baseHook = vm.envAddress("BASE_HOOK");
        address baseOracle = vm.envAddress("BASE_ORACLE");

        vm.startBroadcast(deployer);

        ReputationAggregator agg = ReputationAggregator(aggregator);
        RedistributionScheduler sched = RedistributionScheduler(scheduler);

        // Subscribe aggregator to hook events on each chain
        agg.addSubscription(unichainId, unichainHook);
        agg.addSubscription(baseId, baseHook);

        // Add destination oracles for reputation callbacks
        agg.addDestination(unichainId, unichainOracle);
        agg.addDestination(baseId, baseOracle);

        // Subscribe scheduler to tax events on each chain
        sched.addSubscription(unichainId, unichainHook);
        sched.addSubscription(baseId, baseHook);

        console2.log("Subscriptions configured.");

        vm.stopBroadcast();
    }
}
