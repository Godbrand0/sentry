// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {SentryHook} from "../src/hook/SentryHook.sol";
import {Treasury} from "../src/hook/auxiliary/Treasury.sol";
import {ReputationOracle} from "../src/hook/auxiliary/ReputationOracle.sol";

/// @notice Deploy SentryHook with a CREATE2 address satisfying the hook permission bits.
///
/// Hook permissions required (see SentryHook.getHookPermissions):
///   afterInitialize                   (bit 12) = 0x1000
///   afterAddLiquidity                 (bit 10) = 0x0400
///   afterRemoveLiquidity              (bit  8) = 0x0100
///   afterSwap                         (bit  6) = 0x0040
///   afterRemoveLiquidityReturnDelta   (bit  0) = 0x0001
/// Required address suffix: 0x1541 (bits 12,10,8,6,0 set)
///
/// Usage: forge script script/DeployHook.s.sol --rpc-url $RPC_URL --broadcast
contract DeployHook is Script {
    // Required permission flags ORed together
    uint160 constant REQUIRED_FLAGS = uint160(
        Hooks.AFTER_INITIALIZE_FLAG |
        Hooks.AFTER_ADD_LIQUIDITY_FLAG |
        Hooks.AFTER_REMOVE_LIQUIDITY_FLAG |
        Hooks.AFTER_SWAP_FLAG |
        Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG
    );

    function run() external {
        address deployer = vm.envAddress("DEPLOYER");
        address poolManager = vm.envAddress("POOL_MANAGER");
        address reputationOracle = vm.envOr("REPUTATION_ORACLE", address(0));

        vm.startBroadcast(deployer);

        // Deploy Treasury
        Treasury treasury = new Treasury(deployer);
        console2.log("Treasury:", address(treasury));

        // If no oracle provided, deploy a fresh one
        if (reputationOracle == address(0)) {
            ReputationOracle oracle = new ReputationOracle(deployer);
            reputationOracle = address(oracle);
            console2.log("ReputationOracle:", reputationOracle);
        }

        // Mine a CREATE2 salt so the hook address has the correct permission bits.
        // HookMiner pattern: iterate salts until address & ALL_HOOK_MASK == REQUIRED_FLAGS
        bytes memory creationCode = abi.encodePacked(
            type(SentryHook).creationCode,
            abi.encode(IPoolManager(poolManager), reputationOracle, address(treasury), deployer)
        );

        (address hookAddr, bytes32 salt) = _mineAddress(deployer, creationCode);
        console2.log("Mined hook address:", hookAddr);
        console2.log("Salt:", vm.toString(salt));

        // Deploy with mined salt
        SentryHook hook;
        assembly {
            hook := create2(0, add(creationCode, 0x20), mload(creationCode), salt)
        }
        require(address(hook) != address(0), "Hook deploy failed");
        require(uint160(address(hook)) & Hooks.ALL_HOOK_MASK == REQUIRED_FLAGS, "Hook address invalid");

        console2.log("SentryHook deployed:", address(hook));

        vm.stopBroadcast();
    }

    function _mineAddress(address deployer, bytes memory creationCode)
        internal
        view
        returns (address found, bytes32 salt)
    {
        for (uint256 i = 0; i < 200_000; i++) {
            salt = bytes32(i);
            address candidate = _computeCreate2(deployer, salt, creationCode);
            if (uint160(candidate) & Hooks.ALL_HOOK_MASK == REQUIRED_FLAGS) {
                return (candidate, salt);
            }
        }
        revert("HookMiner: salt not found in 200k iterations");
    }

    function _computeCreate2(address deployer, bytes32 salt, bytes memory creationCode)
        internal
        pure
        returns (address)
    {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), deployer, salt, keccak256(creationCode))
                    )
                )
            )
        );
    }
}
