// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";

/// @notice Minimal BaseHook for Uniswap V4 (replaces the removed periphery BaseHook).
/// Validates that only the PoolManager can invoke hook callbacks and provides default
/// no-op implementations for unused hooks.
abstract contract BaseHook is IHooks {
    IPoolManager public immutable poolManager;

    error NotPoolManager();
    error HookAddressInvalid(address hooks);

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
        _validateHookAddress(this);
    }

    function _validateHookAddress(IHooks self) internal pure virtual {
        Hooks.Permissions memory permissions = getHookPermissions();
        uint160 addr = uint160(address(self));

        if (
            (permissions.beforeInitialize && (addr & Hooks.BEFORE_INITIALIZE_FLAG == 0))
                || (!permissions.beforeInitialize && (addr & Hooks.BEFORE_INITIALIZE_FLAG != 0))
                || (permissions.afterInitialize && (addr & Hooks.AFTER_INITIALIZE_FLAG == 0))
                || (!permissions.afterInitialize && (addr & Hooks.AFTER_INITIALIZE_FLAG != 0))
                || (permissions.beforeAddLiquidity && (addr & Hooks.BEFORE_ADD_LIQUIDITY_FLAG == 0))
                || (!permissions.beforeAddLiquidity && (addr & Hooks.BEFORE_ADD_LIQUIDITY_FLAG != 0))
                || (permissions.afterAddLiquidity && (addr & Hooks.AFTER_ADD_LIQUIDITY_FLAG == 0))
                || (!permissions.afterAddLiquidity && (addr & Hooks.AFTER_ADD_LIQUIDITY_FLAG != 0))
                || (permissions.beforeRemoveLiquidity && (addr & Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG == 0))
                || (!permissions.beforeRemoveLiquidity && (addr & Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG != 0))
                || (permissions.afterRemoveLiquidity && (addr & Hooks.AFTER_REMOVE_LIQUIDITY_FLAG == 0))
                || (!permissions.afterRemoveLiquidity && (addr & Hooks.AFTER_REMOVE_LIQUIDITY_FLAG != 0))
                || (permissions.beforeSwap && (addr & Hooks.BEFORE_SWAP_FLAG == 0))
                || (!permissions.beforeSwap && (addr & Hooks.BEFORE_SWAP_FLAG != 0))
                || (permissions.afterSwap && (addr & Hooks.AFTER_SWAP_FLAG == 0))
                || (!permissions.afterSwap && (addr & Hooks.AFTER_SWAP_FLAG != 0))
                || (permissions.beforeDonate && (addr & Hooks.BEFORE_DONATE_FLAG == 0))
                || (!permissions.beforeDonate && (addr & Hooks.BEFORE_DONATE_FLAG != 0))
                || (permissions.afterDonate && (addr & Hooks.AFTER_DONATE_FLAG == 0))
                || (!permissions.afterDonate && (addr & Hooks.AFTER_DONATE_FLAG != 0))
                || (permissions.beforeSwapReturnDelta && (addr & Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG == 0))
                || (!permissions.beforeSwapReturnDelta && (addr & Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG != 0))
                || (permissions.afterSwapReturnDelta && (addr & Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG == 0))
                || (!permissions.afterSwapReturnDelta && (addr & Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG != 0))
                || (permissions.afterAddLiquidityReturnDelta && (addr & Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG == 0))
                || (!permissions.afterAddLiquidityReturnDelta && (addr & Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG != 0))
                || (permissions.afterRemoveLiquidityReturnDelta && (addr & Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG == 0))
                || (!permissions.afterRemoveLiquidityReturnDelta && (addr & Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG != 0))
        ) {
            revert HookAddressInvalid(address(self));
        }
    }

    function getHookPermissions() public pure virtual returns (Hooks.Permissions memory);

    // ── Default no-op implementations ──────────────────────────────────────────

    function beforeInitialize(address, PoolKey calldata, uint160) external virtual onlyPoolManager returns (bytes4) {
        return IHooks.beforeInitialize.selector;
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24)
        external
        virtual
        onlyPoolManager
        returns (bytes4)
    {
        return IHooks.afterInitialize.selector;
    }

    function beforeAddLiquidity(address, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata, bytes calldata)
        external
        virtual
        onlyPoolManager
        returns (bytes4)
    {
        return IHooks.beforeAddLiquidity.selector;
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external virtual onlyPoolManager returns (bytes4, BalanceDelta) {
        return (IHooks.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    function beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external virtual onlyPoolManager returns (bytes4) {
        return IHooks.beforeRemoveLiquidity.selector;
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external virtual onlyPoolManager returns (bytes4, BalanceDelta) {
        return (IHooks.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    function beforeSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, bytes calldata)
        external
        virtual
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        return (IHooks.beforeSwap.selector, BeforeSwapDelta.wrap(0), 0);
    }

    function afterSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        virtual
        onlyPoolManager
        returns (bytes4, int128)
    {
        return (IHooks.afterSwap.selector, 0);
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        virtual
        onlyPoolManager
        returns (bytes4)
    {
        return IHooks.beforeDonate.selector;
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        virtual
        onlyPoolManager
        returns (bytes4)
    {
        return IHooks.afterDonate.selector;
    }
}
