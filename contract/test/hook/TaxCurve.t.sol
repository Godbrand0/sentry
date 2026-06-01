// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TaxCurve} from "../../src/hook/libraries/TaxCurve.sol";

contract TaxCurveTest is Test {
    // ── Boundary values ──────────────────────────────────────────────────────────

    function test_zeroSeconds_maxTax() public pure {
        uint256 tax = TaxCurve.calculateTaxBps(0);
        assertEq(tax, TaxCurve.MAX_TAX_BPS, "0s should equal MAX_TAX");
    }

    function test_pastTableDomain_zeroTax() public pure {
        uint256 tax = TaxCurve.calculateTaxBps(uint64(TaxCurve.TABLE_DOMAIN));
        assertEq(tax, 0, "At domain boundary tax should be 0");

        tax = TaxCurve.calculateTaxBps(type(uint64).max);
        assertEq(tax, 0, "Far future should be 0");
    }

    function test_oneMinute_approximately84pct() public pure {
        // With piecewise-linear interpolation between half-life breakpoints,
        // 60s → expValue ≈ 0.937 → ~84.3%. True exp(-0.1) = 0.905 but
        // linear interpolation within the first interval overestimates slightly.
        uint256 tax = TaxCurve.calculateTaxBps(60);
        assertApproxEqAbs(tax, 8431, 100, "60s tax should be ~84%");
        assertGt(tax, 8000, "60s tax should be > 80%");
        assertLt(tax, TaxCurve.MAX_TAX_BPS, "60s tax should be below max");
    }

    function test_tenMinutes_halfOfMax() public pure {
        // exp(-1) ≈ 0.368 → 90% * 0.368 ≈ 33.1%
        uint256 tax = TaxCurve.calculateTaxBps(600);
        assertApproxEqAbs(tax, 3311, 300, "10min tax should be ~33%");
    }

    function test_thirtyMinutes_low() public pure {
        // exp(-3) ≈ 0.05 → ~4.5%
        uint256 tax = TaxCurve.calculateTaxBps(1800);
        assertLt(tax, 1000, "30min tax should be < 10%");
    }

    function test_oneHour_veryLow() public pure {
        uint256 tax = TaxCurve.calculateTaxBps(3600);
        assertLt(tax, 200, "1h tax should be < 2%");
    }

    // ── Monotonic decrease ────────────────────────────────────────────────────────

    function test_monotonicallyDecreasing() public pure {
        uint256 prev = TaxCurve.calculateTaxBps(0);
        uint64[6] memory times = [uint64(60), uint64(300), uint64(600), uint64(1800), uint64(3600), uint64(5000)];
        for (uint256 i = 0; i < times.length; i++) {
            uint256 curr = TaxCurve.calculateTaxBps(times[i]);
            assertLe(curr, prev, "Tax must not increase over time");
            prev = curr;
        }
    }

    // ── Concentration multiplier ─────────────────────────────────────────────────

    function test_concentrationBelow50pct_noMultiplier() public pure {
        uint256 base = TaxCurve.calculateTaxBps(0);
        uint256 final_ = TaxCurve.calculateFinalTaxBps(0, 4999);
        assertEq(base, final_, "Below 50% concentration should not multiply");
    }

    function test_extremeConcentration_capsAt99pct() public pure {
        uint256 tax = TaxCurve.calculateFinalTaxBps(0, 10000);
        assertEq(tax, 9900, "Should cap at 99%");
    }

    function test_highConcentration_multipliesBase() public pure {
        // 0s hold, 90% concentration: score=0.9, multiplier=1+(0.9-0.5)*2=1.8
        // 90%*1.8 = 162% → capped at 99%
        uint256 tax = TaxCurve.calculateFinalTaxBps(0, 9000);
        assertEq(tax, 9900, "Extreme concentration should hit cap");

        // 30min hold (~4.5% base tax), 70% concentration: multiplier=1.4 → 4.5%*1.4=6.3%
        uint256 tax2 = TaxCurve.calculateFinalTaxBps(1800, 7000);
        uint256 base2 = TaxCurve.calculateTaxBps(1800);
        assertGt(tax2, base2, "Concentration should increase tax");
    }

    // ── Gas benchmark ─────────────────────────────────────────────────────────────

    function test_gasUnder5000() public {
        uint256 gasBefore = gasleft();
        TaxCurve.calculateFinalTaxBps(120, 6000);
        uint256 gasUsed = gasBefore - gasleft();
        assertLt(gasUsed, 5000, "Tax calculation should use < 5000 gas");
    }
}
