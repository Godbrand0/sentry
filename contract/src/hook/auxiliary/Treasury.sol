// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @notice Receives the protocol's share of redistributed fees (default 5%).
/// Governance-controlled withdrawal. Hard-capped at 10% at the hook level.
contract Treasury {
    address public owner;
    address public pendingOwner;

    event Received(address indexed token, uint128 amount);
    event Withdrawn(address indexed token, address indexed to, uint256 amount);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "Treasury: not owner");
        _;
    }

    constructor(address _owner) {
        owner = _owner;
    }

    /// @notice Called by SentryHook when routing protocol fees here.
    function receive_(address token, uint128 amount) external {
        // Caller is responsible for transferring tokens before calling this.
        emit Received(token, amount);
    }

    function withdraw(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).transfer(to, amount);
        emit Withdrawn(token, to, amount);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "Treasury: not pending owner");
        emit OwnershipTransferred(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
    }
}
