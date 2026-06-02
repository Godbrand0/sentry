// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TaxCurve} from "../../src/hook/libraries/TaxCurve.sol";

/// @notice Headline scenario: bot opens + closes in the same block, pays 65% tax.
/// Math-layer test — does not require a live PoolManager.
contract JITScenarioTest is Test {
    // Mirrors the spec's Flow B numbers
    uint128 constant BOT_FEES = 2475e6;     // $2,475 USDC
    uint16 constant CONCENTRATION_BPS = 9100; // $50M into $5.5M pool ≈ 91%

    function test_sameBlockJIT_pays65pct() public pure {
        uint256 taxBps = TaxCurve.calculateFinalTaxBps(0, CONCENTRATION_BPS);
        // With 91% concentration: multiplier = 1 + (0.91-0.5)*2 = 1.82
        // base = 6500, final = min(6500*1.82, 6500) = 6500 (capped)
        assertEq(taxBps, 6500, "JIT bot with extreme concentration should hit 65% cap");

        uint128 taxAmount = uint128((uint256(BOT_FEES) * taxBps) / 10000);
        uint128 botKeeps = BOT_FEES - taxAmount;

        // Bot should keep ~35% of fees
        assertLt(botKeeps, (BOT_FEES * 40) / 100, "Bot should keep less than 40% of fees");

        // Redistribution pool should receive >= 65%
        assertGe(taxAmount, (BOT_FEES * 65) / 100, "Redistribution should receive >= 65%");
    }

    function test_sameBlockJIT_noConcentration() public pure {
        // Even without concentration, same-block should pay MAX_TAX
        uint256 taxBps = TaxCurve.calculateFinalTaxBps(0, 0);
        assertEq(taxBps, TaxCurve.MAX_TAX_BPS, "No-concentration JIT should pay MAX_TAX");
    }

    function test_longTermLP_paysZeroTax() public pure {
        // Held 30 days — well past the ~100-minute effective window
        uint64 thirtyDays = 30 days;
        uint256 taxBps = TaxCurve.calculateFinalTaxBps(thirtyDays, 0);
        assertEq(taxBps, 0, "Long-term LP should pay no tax");
    }
}
