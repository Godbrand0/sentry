// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2, Vm} from "forge-std/Test.sol";
import {RedistributionScheduler} from "../../src/reactive/RedistributionScheduler.sol";

/// @notice Tests for the Reactive Network redistribution trigger.
///
/// How it works in production
/// ─────────────────────────────────────────
/// 1. SentryHook taxes a JIT bot → emits TaxAccumulated(poolId, amount)
/// 2. Reactive Network delivers this to RedistributionScheduler.react() on Kopli
/// 3. Scheduler checks: accumulated >= $1,000 OR 24h since last redistribution
/// 4. If triggered: emits Callback(chainId, hookAddr, executeRedistribution(poolId))
/// 5. Reactive Network submits that call back to SentryHook on the source chain
///
/// In these tests we call react() directly (vmOnly is a no-op TODO) and assert
/// the trigger conditions, Callback payloads, and cooldown logic.

contract MockSubscriptionService {
    function subscribe(uint256, address, uint256, uint256, uint256, uint256) external {}
    function unsubscribe(uint256, address, uint256) external {}
}

contract RedistributionSchedulerTest is Test {
    bytes32 constant TAX_ACCUMULATED_SIG = keccak256("TaxAccumulated(bytes32,uint128)");

    RedistributionScheduler scheduler;
    MockSubscriptionService service;

    address constant HOOK_ADDR = address(0x1234);
    uint256 constant CHAIN_ID  = 1301; // Unichain Sepolia
    bytes32 constant POOL_A    = bytes32(uint256(0xAAA));
    bytes32 constant POOL_B    = bytes32(uint256(0xBBB));

    uint128 constant THRESHOLD = 1_000e6; // $1,000 in token units
    uint64  constant COOLDOWN  = 24 hours;

    function setUp() public {
        service   = new MockSubscriptionService();
        scheduler = new RedistributionScheduler(address(service), address(this));
        scheduler.addSubscription(CHAIN_ID, HOOK_ADDR);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Subscription management
    // ─────────────────────────────────────────────────────────────────────────

    function test_addSubscription_onlyOwner() public {
        vm.prank(address(0xbad));
        vm.expectRevert("RS: not owner");
        scheduler.addSubscription(CHAIN_ID, HOOK_ADDR);
    }

    function test_addSubscription_registersDestinationHook() public {
        assertEq(scheduler.destinationHooks(CHAIN_ID), HOOK_ADDR);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Below-threshold — no trigger
    // ─────────────────────────────────────────────────────────────────────────

    function test_react_belowThreshold_noCallback() public {
        uint128 smallAmount = THRESHOLD / 2; // $500 — below threshold

        vm.recordLogs();
        _reactTax(POOL_A, smallAmount);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertFalse(_hasCallbackLog(logs), "should not emit Callback below threshold");
    }

    function test_react_accumulatesAcrossMultipleEvents() public {
        // Three events each at $400 — total $1,200, should trigger on third
        vm.recordLogs();
        _reactTax(POOL_A, 400e6);
        assertFalse(_hasCallbackLog(vm.getRecordedLogs()), "first event should not trigger");

        vm.recordLogs();
        _reactTax(POOL_A, 400e6);
        assertFalse(_hasCallbackLog(vm.getRecordedLogs()), "second event should not trigger (still $800)");

        vm.recordLogs();
        _reactTax(POOL_A, 400e6); // now $1,200 — threshold crossed
        assertTrue(_hasCallbackLog(vm.getRecordedLogs()), "third event should trigger at $1,200");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Threshold trigger
    // ─────────────────────────────────────────────────────────────────────────

    function test_react_thresholdMet_emitsCallback() public {
        vm.recordLogs();
        _reactTax(POOL_A, THRESHOLD);
        assertTrue(_hasCallbackLog(vm.getRecordedLogs()), "should emit Callback when threshold is met");
    }

    function test_react_thresholdMet_callbackPayloadIsExecuteRedistribution() public {
        vm.recordLogs();
        _reactTax(POOL_A, THRESHOLD);

        bytes memory payload = _getCallbackPayload(vm.getRecordedLogs());
        bytes memory expected = abi.encodeWithSignature("executeRedistribution(bytes32)", POOL_A);
        assertEq(payload, expected, "payload should call executeRedistribution with correct poolId");
    }

    function test_react_thresholdMet_resetsAccumulator() public {
        _reactTax(POOL_A, THRESHOLD); // triggers, resets to 0

        // Next event at $400 — below threshold on fresh counter
        vm.recordLogs();
        _reactTax(POOL_A, 400e6);
        assertFalse(_hasCallbackLog(vm.getRecordedLogs()), "accumulator should have reset after trigger");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Cooldown trigger (24h elapsed regardless of amount)
    // ─────────────────────────────────────────────────────────────────────────

    function test_react_cooldownExpired_triggerEvenBelowThreshold() public {
        // First event triggers at threshold, starting the cooldown clock
        _reactTax(POOL_A, THRESHOLD);

        // 24 hours pass
        vm.warp(block.timestamp + COOLDOWN + 1);

        // Even a tiny amount should now trigger because cooldown expired
        vm.recordLogs();
        _reactTax(POOL_A, 1);
        assertTrue(_hasCallbackLog(vm.getRecordedLogs()), "cooldown expired should trigger regardless of amount");
    }

    function test_react_withinCooldown_doesNotRetrigger() public {
        _reactTax(POOL_A, THRESHOLD); // triggers, resets accumulator to 0

        // 12 hours later — still within 24h cooldown
        vm.warp(block.timestamp + 12 hours);

        // $400 — below threshold AND cooldown not expired: no trigger
        vm.recordLogs();
        _reactTax(POOL_A, 400e6);
        assertFalse(_hasCallbackLog(vm.getRecordedLogs()), "should not retrigger within cooldown with below-threshold amount");
    }

    function test_react_exactCooldownBoundary() public {
        _reactTax(POOL_A, THRESHOLD);

        // Exactly at the cooldown boundary (lastRedistributionAt + COOLDOWN)
        // cooldownExpired = block.timestamp >= lastRedistributionAt + COOLDOWN
        vm.warp(block.timestamp + COOLDOWN);

        vm.recordLogs();
        _reactTax(POOL_A, 1);
        assertTrue(_hasCallbackLog(vm.getRecordedLogs()), "should trigger exactly at cooldown boundary");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Pool isolation — different pools are tracked independently
    // ─────────────────────────────────────────────────────────────────────────

    function test_react_poolsTrackedIndependently() public {
        // Pool A accumulates $800
        _reactTax(POOL_A, 800e6);

        // Pool B accumulates $600 — different pool, should not mix with Pool A
        vm.recordLogs();
        _reactTax(POOL_B, 600e6);
        assertFalse(_hasCallbackLog(vm.getRecordedLogs()), "Pool B should not trigger from Pool A's accumulation");

        // Pool B adds another $500 — now $1,100, should trigger
        vm.recordLogs();
        _reactTax(POOL_B, 500e6);
        assertTrue(_hasCallbackLog(vm.getRecordedLogs()), "Pool B should trigger independently");
    }

    function test_react_callbackTargetsCorrectPool() public {
        _reactTax(POOL_A, 800e6);

        vm.recordLogs();
        _reactTax(POOL_B, THRESHOLD); // triggers for POOL_B

        bytes memory payload = _getCallbackPayload(vm.getRecordedLogs());
        bytes memory expected = abi.encodeWithSignature("executeRedistribution(bytes32)", POOL_B);
        assertEq(payload, expected, "Callback should target Pool B, not Pool A");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Wrong topic — ignored
    // ─────────────────────────────────────────────────────────────────────────

    function test_react_wrongTopic_isIgnored() public {
        bytes32 wrongTopic = keccak256("SomethingElse(bytes32,uint128)");

        vm.recordLogs();
        scheduler.react(CHAIN_ID, HOOK_ADDR, wrongTopic, POOL_A, bytes32(0), abi.encode(uint128(THRESHOLD * 10)));

        assertFalse(_hasCallbackLog(vm.getRecordedLogs()), "wrong topic should be ignored");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Cooldown resets after each trigger
    // ─────────────────────────────────────────────────────────────────────────

    function test_react_multipleCycles() public {
        // Cycle 1: threshold hit
        _reactTax(POOL_A, THRESHOLD);

        // 25 hours later: cooldown expired, tiny amount triggers cycle 2
        vm.warp(block.timestamp + 25 hours);
        vm.recordLogs();
        _reactTax(POOL_A, 1);
        assertTrue(_hasCallbackLog(vm.getRecordedLogs()), "cycle 2 should trigger");

        // 12 hours later: within new cooldown, below-threshold amount — should not trigger
        vm.warp(block.timestamp + 12 hours);
        vm.recordLogs();
        _reactTax(POOL_A, 400e6);
        assertFalse(_hasCallbackLog(vm.getRecordedLogs()), "within cycle 2 cooldown, should not trigger");

        // 13 more hours (total 25h from cycle 2): cooldown expires, triggers cycle 3
        vm.warp(block.timestamp + 13 hours);
        vm.recordLogs();
        _reactTax(POOL_A, 1);
        assertTrue(_hasCallbackLog(vm.getRecordedLogs()), "cycle 3 should trigger after cooldown");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _reactTax(bytes32 poolId, uint128 amount) internal {
        scheduler.react(
            CHAIN_ID,
            HOOK_ADDR,
            TAX_ACCUMULATED_SIG,
            poolId,
            bytes32(0),
            abi.encode(amount)
        );
    }

    function _hasCallbackLog(Vm.Log[] memory logs) internal pure returns (bool) {
        bytes32 callbackSig = keccak256("Callback(uint256,address,uint64,bytes)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == callbackSig) {
                return true;
            }
        }
        return false;
    }

    function _getCallbackPayload(Vm.Log[] memory logs) internal pure returns (bytes memory) {
        bytes32 callbackSig = keccak256("Callback(uint256,address,uint64,bytes)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == callbackSig) {
                (, bytes memory payload) = abi.decode(logs[i].data, (uint64, bytes));
                return payload;
            }
        }
        revert("_getCallbackPayload: no Callback log found");
    }
}
