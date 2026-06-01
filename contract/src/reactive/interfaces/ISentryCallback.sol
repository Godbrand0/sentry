// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Signatures for callbacks emitted by Reactive Contracts back to destination chains.
interface ISentryCallback {
    /// @notice Called on ReputationOracle to update an LP's cross-chain reputation.
    function setReputation(address lp, uint128 totalCapitalSeconds, uint128 currentCapital, uint64 timestamp)
        external;

    /// @notice Called on SentryHook to trigger a redistribution payout.
    function executeRedistribution(bytes32 poolId) external;
}
