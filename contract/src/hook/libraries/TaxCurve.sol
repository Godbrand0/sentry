// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Gas-efficient exponential tax curve.
/// tax_rate(t) = MAX_TAX * exp(-t / HALF_LIFE)
///
/// Implementation: 10 breakpoints covering exp(-x) for x in [0, 10] (one per half-life),
/// with linear interpolation between them. After 10 half-lives the tax rounds to 0.
/// Keeps the contract small and predictable while staying within 5k gas.
library TaxCurve {
    uint64 internal constant HALF_LIFE = 600;       // 10 minutes
    uint256 internal constant MAX_TAX_BPS = 6500;   // 65% (60% to LPs + 5% to platform)
    uint256 internal constant TABLE_DOMAIN = HALF_LIFE * 10; // 6000 seconds
    uint256 internal constant SCALE = 1e18;

    // exp(-k) * 1e18 for k = 0..10 (one per half-life interval)
    // Computed as: round(exp(-k) * 1e18)
    function _exp(uint256 k) private pure returns (uint256) {
        if (k == 0)  return 1_000000000000000000;
        if (k == 1)  return   367879441171442321;
        if (k == 2)  return   135335283236612691;
        if (k == 3)  return    49787068367863943;
        if (k == 4)  return    18315638888734179;
        if (k == 5)  return     6737946999085467;
        if (k == 6)  return     2478752176666017;
        if (k == 7)  return      911882149321160;
        if (k == 8)  return      335462627902512;
        if (k == 9)  return      123409804086520;
        return 0; // k >= 10
    }

    /// @notice Returns the base tax in basis points (0–6500) for a given hold duration.
    function calculateTaxBps(uint64 timeHeldSeconds) internal pure returns (uint256) {
        if (timeHeldSeconds >= TABLE_DOMAIN) return 0;

        // Which interval are we in? [k * HALF_LIFE, (k+1) * HALF_LIFE)
        uint256 k = timeHeldSeconds / HALF_LIFE;
        uint256 remainder = timeHeldSeconds % HALF_LIFE; // 0..HALF_LIFE-1

        uint256 expLo = _exp(k);
        uint256 expHi = _exp(k + 1);

        // Linear interpolation: expLo - (expLo - expHi) * remainder / HALF_LIFE
        uint256 expValue = expLo - ((expLo - expHi) * remainder) / HALF_LIFE;

        return (MAX_TAX_BPS * expValue) / SCALE;
    }

    /// @notice Applies the concentration multiplier and returns final tax bps, capped at 6500 (65%).
    /// @param concentrationBps Position liquidity as a fraction of total in-range liquidity (0-10000).
    function calculateFinalTaxBps(uint64 timeHeldSeconds, uint16 concentrationBps)
        internal
        pure
        returns (uint256)
    {
        uint256 baseTax = calculateTaxBps(timeHeldSeconds);
        if (baseTax == 0) return 0;

        // Multiplier = 1 + (score - 0.5) * 2, kicks in above 50% concentration
        uint256 multiplierBps = 10000;
        if (concentrationBps > 5000) {
            multiplierBps = 10000 + uint256(concentrationBps - 5000) * 2;
        }

        uint256 finalTax = (baseTax * multiplierBps) / 10000;
        return finalTax > 6500 ? 6500 : finalTax;
    }
}
