// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IReputationOracle} from "../interfaces/IReputationOracle.sol";

/// @notice Destination contract on each target chain. Receives cross-chain LP reputation
/// updates pushed by the ReputationAggregator Reactive Contract on Reactive Kopli.
contract ReputationOracle is IReputationOracle {
    address public owner;
    /// @notice Authorised callback senders (the Reactive Network gateway on this chain).
    mapping(address => bool) public authorizedSenders;

    mapping(address => Reputation) private _reputations;

    event ReputationUpdated(address indexed lp, uint128 totalCapitalSeconds, uint128 currentCapital);
    event SenderAuthorized(address indexed sender);
    event SenderRevoked(address indexed sender);

    modifier onlyOwner() {
        require(msg.sender == owner, "Oracle: not owner");
        _;
    }

    modifier onlyAuthorized() {
        require(authorizedSenders[msg.sender], "Oracle: unauthorized sender");
        _;
    }

    constructor(address _owner) {
        owner = _owner;
    }

    function authorizeSender(address sender) external onlyOwner {
        authorizedSenders[sender] = true;
        emit SenderAuthorized(sender);
    }

    function revokeSender(address sender) external onlyOwner {
        authorizedSenders[sender] = false;
        emit SenderRevoked(sender);
    }

    function getReputation(address lp) external view override returns (Reputation memory) {
        return _reputations[lp];
    }

    /// @notice Effective tenure in seconds derived from accumulated capital-seconds.
    /// Used by SentryHook to adjust tax rate for LPs with cross-chain history.
    /// Returns 0 if lp has no cross-chain history (fresh address).
    function effectiveTenure(address lp) external view returns (uint64) {
        Reputation memory rep = _reputations[lp];
        if (rep.currentCapital == 0) return 0;
        // Approximate effective tenure: total capital-seconds / current capital
        return uint64(rep.totalCapitalSeconds / rep.currentCapital);
    }

    function setReputation(
        address lp,
        uint128 totalCapitalSeconds,
        uint128 currentCapital,
        uint64 timestamp
    ) external override onlyAuthorized {
        _reputations[lp] = Reputation({
            totalCapitalSeconds: totalCapitalSeconds,
            currentCapital: currentCapital,
            lastUpdate: timestamp
        });
        emit ReputationUpdated(lp, totalCapitalSeconds, currentCapital);
    }
}
