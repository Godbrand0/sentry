// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library PositionKey {
    /// @notice Deterministic key for a position: keccak256(owner, poolId, tickLower, tickUpper, salt)
    function compute(address owner, bytes32 poolId, int24 tickLower, int24 tickUpper, bytes32 salt)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(owner, poolId, tickLower, tickUpper, salt));
    }
}
