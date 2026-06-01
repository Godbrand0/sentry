// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IReputationOracle {
    struct Reputation {
        uint128 totalCapitalSeconds; // Σ(capital × duration) across all chains
        uint128 currentCapital;      // Sum of currently-open positions
        uint64 lastUpdate;
    }

    /// @notice Returns the cross-chain reputation for an LP address.
    function getReputation(address lp) external view returns (Reputation memory);

    /// @notice Called by Reactive Network callback to update an LP's reputation.
    function setReputation(
        address lp,
        uint128 totalCapitalSeconds,
        uint128 currentCapital,
        uint64 timestamp
    ) external;
}
