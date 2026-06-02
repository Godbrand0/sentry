// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {HookMiner} from "v4-periphery/test/shared/HookMiner.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";

import {SentryHook} from "../../src/hook/SentryHook.sol";
import {Treasury} from "../../src/hook/auxiliary/Treasury.sol";
import {ReputationOracle} from "../../src/hook/auxiliary/ReputationOracle.sol";
import {RedistributionPool} from "../../src/hook/auxiliary/RedistributionPool.sol";
import {PositionKey} from "../../src/hook/libraries/PositionKey.sol";
import {ISentryHook} from "../../src/hook/interfaces/ISentryHook.sol";
import {TaxCurve} from "../../src/hook/libraries/TaxCurve.sol";

/// @notice End-to-end simulation of Sentry hook behaviour on a local PoolManager.
///
/// Actor model
/// ─────────────────────────────────────────────────────────────────
/// lpRouter   — PoolModifyLiquidityTest instance used by the long-term LP.
///              Because this router calls PoolManager, `sender` in hook callbacks
///              = address(lpRouter), giving Alice her own position key.
/// botRouter  — Separate PoolModifyLiquidityTest instance for the JIT bot.
///              Different address → different position key → independent position.
/// swapRouter — PoolSwapTest for executing swaps.
/// address(this) (test contract) — holds all tokens; approves each router.
///
/// Scenarios
/// ─────────────────────────────────────────────────────────────────
/// 1. test_positionRecordedOnAddLiquidity  — opening a position stores correct data
/// 2. test_jitBot_sameBlock_pays65pctTax   — bot adds, swap, bot removes in t=0 → 65% tax
/// 3. test_longTermLP_paysZeroTax          — LP held 30 days → 0% tax
/// 4. test_redistribution_paysLongTermLP   — full flow: Alice gets paid from bot's tax

contract ForkScenario is Test {
    using PoolIdLibrary for PoolKey;

    // ── Hook permission flags (must match SentryHook.getHookPermissions) ────────
    uint160 constant REQUIRED_FLAGS = uint160(
        Hooks.AFTER_INITIALIZE_FLAG
            | Hooks.AFTER_ADD_LIQUIDITY_FLAG
            | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
            | Hooks.AFTER_SWAP_FLAG
            | Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG
    );

    // ── V4 price constants ───────────────────────────────────────────────────────
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint160 constant MIN_PRICE_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
    uint160 constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

    // ── Infrastructure ───────────────────────────────────────────────────────────
    IPoolManager poolManager;
    PoolModifyLiquidityTest lpRouter;   // long-term LP router  (sender in hook = address(lpRouter))
    PoolModifyLiquidityTest botRouter;  // JIT bot router       (sender in hook = address(botRouter))
    PoolSwapTest            swapRouter;

    MockERC20 token0;
    MockERC20 token1;

    SentryHook        hook;
    Treasury          treasury;
    ReputationOracle  oracle;
    RedistributionPool rPool;
    PoolKey  poolKey;
    PoolId   poolId;

    // ── setUp ────────────────────────────────────────────────────────────────────
    function setUp() public {
        // 1. Fresh PoolManager (acts as the on-chain V4 hub)
        poolManager = new PoolManager(address(this));

        // 2. Separate routers so lpRouter.address ≠ botRouter.address,
        //    giving each a distinct `sender` in hook callbacks.
        lpRouter   = new PoolModifyLiquidityTest(poolManager);
        botRouter  = new PoolModifyLiquidityTest(poolManager);
        swapRouter = new PoolSwapTest(poolManager);

        // 3. Test tokens
        token0 = new MockERC20("TokenA", "TKA", 18);
        token1 = new MockERC20("TokenB", "TKB", 18);
        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }

        // 4. Sentry supporting contracts
        treasury = new Treasury(address(this));
        oracle   = new ReputationOracle(address(this));

        // 5. Deploy SentryHook at a CREATE2 address whose low bits satisfy permission flags
        _deployHook();

        // 6. Initialise the Sentry-protected pool (triggers afterInitialize → deploys rPool)
        poolKey = PoolKey({
            currency0:   Currency.wrap(address(token0)),
            currency1:   Currency.wrap(address(token1)),
            fee:         3000,   // 0.3%
            tickSpacing: 60,
            hooks:       IHooks(address(hook))
        });
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, SQRT_PRICE_1_1);
        rPool = hook.redistributionPools(poolId);

        // 7. Fund test contract and approve routers
        //    Routers call transferFrom(address(this), poolManager, amount),
        //    so they need approval from this contract.
        token0.mint(address(this), 1_000_000_000e18);
        token1.mint(address(this), 1_000_000_000e18);

        token0.approve(address(lpRouter),   type(uint256).max);
        token1.approve(address(lpRouter),   type(uint256).max);
        token0.approve(address(botRouter),  type(uint256).max);
        token1.approve(address(botRouter),  type(uint256).max);
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // Scenario 1 — Position is recorded when LP adds liquidity
    // ────────────────────────────────────────────────────────────────────────────
    function test_positionRecordedOnAddLiquidity() public {
        uint128 liquidity = 1_000e18;
        _lpAdd(-6000, 6000, int256(uint256(liquidity)));

        bytes32 posKey = PositionKey.compute(
            address(lpRouter), PoolId.unwrap(poolId), -6000, 6000, bytes32(0)
        );
        ISentryHook.Position memory pos = hook.getPosition(posKey);

        assertEq(pos.capital, liquidity, "capital should equal deposited liquidity");
        assertEq(pos.openedAt, block.timestamp, "openedAt should be current timestamp");
        // First LP has no prior pool depth to compare against → concentration = 0
        assertEq(pos.concentrationBps, 0, "first LP with no prior depth should score 0 concentration");
    }

    // ────────────────────────────────────────────────────────────────────────────
    // Scenario 2 — JIT bot adds concentrated liquidity, swap fires, bot exits
    //              immediately → 65% tax applied, redistribution pool funded
    // ────────────────────────────────────────────────────────────────────────────
    function test_jitBot_sameBlock_pays65pctTax() public {
        // Alice provides broad background liquidity so the pool has depth
        _lpAdd(-6000, 6000, int256(100_000e18));

        // Bot enters with a very tight 1-tick range (high concentration)
        uint128 botLiquidity = 5_000_000e18;
        _botAdd(-60, 60, int256(uint256(botLiquidity)));

        bytes32 botPosKey = PositionKey.compute(
            address(botRouter), PoolId.unwrap(poolId), -60, 60, bytes32(0)
        );
        ISentryHook.Position memory botPos = hook.getPosition(botPosKey);
        assertGt(botPos.concentrationBps, 5000, "tight range bot should score > 50% concentration");

        // Large swap — generates fees in the same block
        _swap(true, -500_000e18);

        // Bot exits in same block (timeHeld = 0 → MAX_TAX = 6500 bps)
        uint256 rPoolBefore = rPool.balance(PoolId.unwrap(poolId));
        _botRemove(-60, 60, -int256(uint256(botLiquidity)));
        uint256 rPoolAfter = rPool.balance(PoolId.unwrap(poolId));

        assertGt(rPoolAfter, rPoolBefore, "redistribution pool should be funded after JIT exit");

        uint256 tax = hook.calculateTax(0, botPos.concentrationBps);
        assertEq(tax, TaxCurve.MAX_TAX_BPS, "0-second hold should pay MAX_TAX (65%)");

        console2.log("Redistribution pool funded:", rPoolAfter - rPoolBefore, "token0 units");
    }

    // ────────────────────────────────────────────────────────────────────────────
    // Scenario 3 — Long-term LP holds 30 days, removes with zero tax
    // ────────────────────────────────────────────────────────────────────────────
    function test_longTermLP_paysZeroTax() public {
        _lpAdd(-6000, 6000, int256(1_000e18));
        _swap(true, -100_000e18);

        // 30 days passes — position is well past the decay window (~100 min)
        vm.warp(block.timestamp + 30 days);

        uint256 rPoolBefore = rPool.balance(PoolId.unwrap(poolId));
        _lpRemove(-6000, 6000, -int256(1_000e18));
        uint256 rPoolAfter = rPool.balance(PoolId.unwrap(poolId));

        assertEq(rPoolAfter, rPoolBefore, "long-term LP should pay zero tax");

        uint256 tax = hook.calculateTax(30 days, 0);
        assertEq(tax, 0, "calculateTax at 30 days should return 0");
    }

    // ────────────────────────────────────────────────────────────────────────────
    // Scenario 4 — Full redistribution flow
    //   Alice adds wide liquidity → 25 hours pass → Alice does small partial remove
    //   to register as eligible → JIT bot attacks → redistribution executes →
    //   lpRouter (Alice proxy) receives token0 payout
    // ────────────────────────────────────────────────────────────────────────────
    function test_redistribution_paysLongTermLP() public {
        // Alice adds wide, low-concentration liquidity
        _lpAdd(-6000, 6000, int256(500_000e18));

        // 25 hours pass — Alice is now a long-term LP (> 24h threshold)
        vm.warp(block.timestamp + 25 hours);

        // Partial removal registers Alice as eligible for redistribution.
        // This is the trigger: !isFullClose && timeHeld >= LONG_TERM_THRESHOLD
        _lpRemove(-6000, 6000, -int256(1e18));

        uint256 eligibleCount = rPool.eligibleLPCount(PoolId.unwrap(poolId));
        assertEq(eligibleCount, 1, "Alice should be registered as eligible LP");

        // JIT bot attacks — funds the redistribution pool
        _botAdd(-60, 60, int256(5_000_000e18));
        _swap(true, -500_000e18);
        _botRemove(-60, 60, -int256(5_000_000e18));

        uint256 poolBalance = rPool.balance(PoolId.unwrap(poolId));
        assertGt(poolBalance, 0, "redistribution pool should have funds from JIT tax");

        // Execute redistribution (permissionless — anyone may trigger)
        uint256 lpRouterBalanceBefore = token0.balanceOf(address(lpRouter));
        rPool.execute(PoolId.unwrap(poolId));
        uint256 lpRouterBalanceAfter = token0.balanceOf(address(lpRouter));

        assertGt(lpRouterBalanceAfter, lpRouterBalanceBefore, "long-term LP should receive payout");
        assertGt(token0.balanceOf(address(treasury)), 0,      "treasury should receive protocol fee");

        console2.log("LP payout:       ", lpRouterBalanceAfter - lpRouterBalanceBefore);
        console2.log("Protocol fee:    ", token0.balanceOf(address(treasury)));
        console2.log("Pool funded was: ", poolBalance);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // Scenario 5 — Tax decays over time (5 min hold vs 0 sec hold)
    // ────────────────────────────────────────────────────────────────────────────
    function test_taxDecaysOverTime() public {
        uint256 taxAt0   = hook.calculateTax(0,         0);
        uint256 taxAt5m  = hook.calculateTax(5 minutes, 0);
        uint256 taxAt1h  = hook.calculateTax(1 hours,   0);
        uint256 taxAt24h = hook.calculateTax(24 hours,  0);

        assertEq(taxAt0, 6500,  "0s should be MAX_TAX 65%");
        assertLt(taxAt5m,  taxAt0,  "5m tax should be less than 0s tax");
        assertLt(taxAt1h,  taxAt5m, "1h tax should be less than 5m tax");
        assertEq(taxAt24h, 0,       "24h tax should be 0");

        console2.log("Tax at 0s:   ", taxAt0,  "bps");
        console2.log("Tax at 5min: ", taxAt5m, "bps");
        console2.log("Tax at 1h:   ", taxAt1h, "bps");
        console2.log("Tax at 24h:  ", taxAt24h,"bps");
    }

    // ────────────────────────────────────────────────────────────────────────────
    // Scenario 6 — Concentration multiplier increases tax for tight positions
    // ────────────────────────────────────────────────────────────────────────────
    function test_concentrationMultiplier() public {
        uint256 baseAt0   = hook.calculateTax(0, 0);     // no concentration
        uint256 taxHigh   = hook.calculateTax(0, 9000);  // 90% concentration — capped at 6500

        assertEq(baseAt0, 6500, "base 0s = 65%");
        assertEq(taxHigh, 6500, "high concentration at 0s should still be capped at 65%");

        // After 5 min, concentration multiplier does push tax above base
        uint256 baseAt5m = hook.calculateTax(5 minutes, 0);
        uint256 taxAt5m  = hook.calculateTax(5 minutes, 9000);
        assertGt(taxAt5m, baseAt5m, "concentration should increase tax at 5 min hold");
    }

    // ────────────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ────────────────────────────────────────────────────────────────────────────

    function _lpAdd(int24 tickLower, int24 tickUpper, int256 liquidityDelta) internal {
        lpRouter.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower:      tickLower,
                tickUpper:      tickUpper,
                liquidityDelta: liquidityDelta,
                salt:           bytes32(0)
            }),
            ""
        );
    }

    function _lpRemove(int24 tickLower, int24 tickUpper, int256 liquidityDelta) internal {
        lpRouter.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower:      tickLower,
                tickUpper:      tickUpper,
                liquidityDelta: liquidityDelta,
                salt:           bytes32(0)
            }),
            ""
        );
    }

    function _botAdd(int24 tickLower, int24 tickUpper, int256 liquidityDelta) internal {
        botRouter.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower:      tickLower,
                tickUpper:      tickUpper,
                liquidityDelta: liquidityDelta,
                salt:           bytes32(0)
            }),
            ""
        );
    }

    function _botRemove(int24 tickLower, int24 tickUpper, int256 liquidityDelta) internal {
        botRouter.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower:      tickLower,
                tickUpper:      tickUpper,
                liquidityDelta: liquidityDelta,
                salt:           bytes32(0)
            }),
            ""
        );
    }

    function _swap(bool zeroForOne, int256 amountSpecified) internal {
        swapRouter.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne:        zeroForOne,
                amountSpecified:   amountSpecified,
                sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
    }

    // ────────────────────────────────────────────────────────────────────────────
    // Hook deployment — mines a CREATE2 salt so the hook address encodes the
    // required V4 permission bits, then deploys the hook at that address.
    // ────────────────────────────────────────────────────────────────────────────
    // Use vm.getCode (exact artifact bytecode) + HookMiner so the address computation
    // is consistent with via_ir compilation, which can produce a different initcode hash
    // than type(SentryHook).creationCode at runtime.
    function _deployHook() internal {
        bytes memory constructorArgs = abi.encode(
            poolManager, address(oracle), address(treasury), address(this)
        );
        bytes memory creationCode = vm.getCode("SentryHook.sol:SentryHook");

        (address hookAddr, bytes32 salt) = HookMiner.find(
            address(this), REQUIRED_FLAGS, creationCode, constructorArgs
        );

        bytes memory initcode = abi.encodePacked(creationCode, constructorArgs);
        address deployed;
        assembly {
            deployed := create2(0, add(initcode, 0x20), mload(initcode), salt)
        }
        require(deployed != address(0) && deployed == hookAddr, "ForkScenario: hook deployment failed");
        hook = SentryHook(hookAddr);
    }
}
