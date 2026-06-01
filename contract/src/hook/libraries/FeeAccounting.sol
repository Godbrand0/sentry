// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Tracks per-position fee accrual using a global fee-growth accumulator pattern
/// (analogous to Uniswap's feeGrowthInsideX128). Updated lazily — only touched on
/// add/remove liquidity, not on every swap.
library FeeAccounting {
    struct PoolFeeState {
        // fee growth per unit of liquidity, scaled by 2^128
        uint256 feeGrowthGlobal0X128;
        uint256 feeGrowthGlobal1X128;
    }

    struct PositionFeeSnapshot {
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
    }

    /// @notice Compute fees earned by a position since its last snapshot.
    function feesEarned(
        PositionFeeSnapshot memory snapshot,
        PoolFeeState memory pool,
        uint128 liquidity
    ) internal pure returns (uint128 fees0, uint128 fees1) {
        // Unchecked: overflow is intentional and expected here (matches Uniswap's pattern)
        unchecked {
            uint256 delta0 = pool.feeGrowthGlobal0X128 - snapshot.feeGrowthInside0LastX128;
            uint256 delta1 = pool.feeGrowthGlobal1X128 - snapshot.feeGrowthInside1LastX128;
            fees0 = uint128((uint256(liquidity) * delta0) >> 128);
            fees1 = uint128((uint256(liquidity) * delta1) >> 128);
        }
    }

    /// @notice Increment the global fee accumulator. Called in afterSwap with the swap's fee amounts.
    function accumulateFees(
        PoolFeeState storage pool,
        uint128 fees0,
        uint128 fees1,
        uint128 totalLiquidity
    ) internal {
        if (totalLiquidity == 0) return;
        unchecked {
            pool.feeGrowthGlobal0X128 += (uint256(fees0) << 128) / totalLiquidity;
            pool.feeGrowthGlobal1X128 += (uint256(fees1) << 128) / totalLiquidity;
        }
    }
}
