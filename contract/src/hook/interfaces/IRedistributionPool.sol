// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IRedistributionPool {
    /// @notice Deposits taxed fees into the pool. Called by SentryHook on position close.
    function deposit(bytes32 poolId, address token, uint128 amount) external;

    /// @notice Executes a redistribution to eligible long-term LPs.
    /// Called by SentryHook.executeRedistribution (triggered by Reactive Network).
    function execute(bytes32 poolId) external;

    /// @notice Returns the current accumulated balance for a pool.
    function balance(bytes32 poolId) external view returns (uint128);
}
