// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2, Vm} from "forge-std/Test.sol";
import {ReputationAggregator} from "../../src/reactive/ReputationAggregator.sol";

/// @notice Simulates the Reactive Network VM delivering events to ReputationAggregator.
///
/// How Reactive Network works in production
/// ─────────────────────────────────────────
/// 1. SentryHook on Unichain emits PositionOpened or PositionClosed
/// 2. Reactive Network detects the event and calls react() on ReputationAggregator (on Kopli)
/// 3. ReputationAggregator updates the LP's global capital-seconds record
/// 4. It emits Callback events — one per registered destination oracle
/// 5. Reactive Network submits setReputation() to each oracle on each chain
///
/// In these tests we replace the Reactive VM with direct react() calls (the vmOnly
/// modifier is a no-op until reactive-lib is wired in) and assert:
///   - reputation state is updated correctly
///   - Callback events are emitted with the correct payload

contract MockSubscriptionService {
    // Records all subscribe() calls so we can assert they happened
    struct Sub {
        uint256 chainId;
        address contractAddr;
        uint256 topic0;
    }
    Sub[] public subs;

    function subscribe(uint256 chainId, address contractAddr, uint256 topic0, uint256, uint256, uint256) external {
        subs.push(Sub(chainId, contractAddr, topic0));
    }

    function unsubscribe(uint256, address, uint256) external {}

    function subCount() external view returns (uint256) {
        return subs.length;
    }
}

contract ReputationAggregatorTest is Test {
    // ── Event signatures (mirrors what the contracts use) ─────────────────────
    bytes32 constant POSITION_OPENED_SIG =
        keccak256("PositionOpened(address,bytes32,uint128,uint64,uint16)");
    bytes32 constant POSITION_CLOSED_SIG =
        keccak256("PositionClosed(address,bytes32,uint128,uint64,uint128,uint128)");

    // ── Contracts ─────────────────────────────────────────────────────────────
    MockSubscriptionService service;
    ReputationAggregator    aggregator;

    // ── Test actors ───────────────────────────────────────────────────────────
    address constant LP_ALICE   = address(0xA11ce);
    address constant LP_BOT     = address(0xB07);
    address constant HOOK_ADDR  = address(0x1111);
    address constant ORACLE_A   = address(0xAA);
    address constant ORACLE_B   = address(0xBB);
    uint256 constant CHAIN_A    = 1301;   // Unichain Sepolia
    uint256 constant CHAIN_B    = 84532;  // Base Sepolia
    bytes32 constant POOL_ID    = bytes32(uint256(0xdead));

    function setUp() public {
        service    = new MockSubscriptionService();
        aggregator = new ReputationAggregator(address(service), address(this));

        // Register two destination oracles
        aggregator.addDestination(CHAIN_A, ORACLE_A);
        aggregator.addDestination(CHAIN_B, ORACLE_B);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Subscription management
    // ─────────────────────────────────────────────────────────────────────────

    function test_addSubscription_registersWithService() public {
        aggregator.addSubscription(CHAIN_A, HOOK_ADDR);

        // Should have subscribed to both PositionOpened and PositionClosed
        assertEq(service.subCount(), 2, "should subscribe to both event signatures");

        (uint256 chainId0, address addr0, uint256 topic0_0) = service.subs(0);
        assertEq(chainId0, CHAIN_A);
        assertEq(addr0,    HOOK_ADDR);
        assertEq(topic0_0, uint256(POSITION_OPENED_SIG));

        (uint256 chainId1, address addr1, uint256 topic0_1) = service.subs(1);
        assertEq(chainId1, CHAIN_A);
        assertEq(addr1,    HOOK_ADDR);
        assertEq(topic0_1, uint256(POSITION_CLOSED_SIG));
    }

    function test_addSubscription_onlyOwner() public {
        vm.prank(address(0xbad));
        vm.expectRevert("RA: not owner");
        aggregator.addSubscription(CHAIN_A, HOOK_ADDR);
    }

    function test_addDestination_onlyOwner() public {
        vm.prank(address(0xbad));
        vm.expectRevert("RA: not owner");
        aggregator.addDestination(CHAIN_A, ORACLE_A);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PositionOpened handling
    // ─────────────────────────────────────────────────────────────────────────

    function test_react_positionOpened_updatesCurrentCapital() public {
        uint128 capital        = 500_000e18;
        uint64  openedAt       = uint64(block.timestamp);
        uint16  concentration  = 300; // 3%

        _reactOpened(LP_ALICE, bytes32(uint256(1)), capital, openedAt, concentration);

        (uint128 totalCapSec, uint128 currentCap,) = aggregator.reputations(LP_ALICE);
        assertEq(currentCap,   capital, "currentCapital should equal deposited liquidity");
        assertEq(totalCapSec,  0,       "totalCapitalSeconds should be 0: position not yet closed");
    }

    function test_react_positionOpened_accumulatesAcrossChains() public {
        // Alice opens two positions (simulating two different chains delivering events)
        _reactOpened(LP_ALICE, bytes32(uint256(1)), 100e18, uint64(block.timestamp), 0);
        _reactOpened(LP_ALICE, bytes32(uint256(2)), 200e18, uint64(block.timestamp), 0);

        (, uint128 currentCap,) = aggregator.reputations(LP_ALICE);
        assertEq(currentCap, 300e18, "currentCapital should sum across all open positions");
    }

    function test_react_positionOpened_emitsCallbackToAllOracles() public {
        uint128 capital  = 100e18;
        uint64  openedAt = uint64(block.timestamp);

        vm.recordLogs();
        _reactOpened(LP_ALICE, bytes32(uint256(1)), capital, openedAt, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertTrue(_hasCallbackForOracle(logs, ORACLE_A), "should emit Callback to ORACLE_A");
        assertTrue(_hasCallbackForOracle(logs, ORACLE_B), "should emit Callback to ORACLE_B");
        assertEq(_countCallbackLogs(logs), 2, "should emit exactly 2 Callback events");
    }

    function test_react_positionOpened_callbackPayloadCallsSetReputation() public {
        uint128 capital  = 250e18;
        uint64  openedAt = uint64(block.timestamp);

        vm.recordLogs();
        _reactOpened(LP_ALICE, bytes32(uint256(1)), capital, openedAt, 500);

        // Find the Callback event for ORACLE_A and decode its payload
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes memory payload = _findCallbackPayload(logs, ORACLE_A);

        bytes memory expected = abi.encodeWithSignature(
            "setReputation(address,uint128,uint128,uint64)",
            LP_ALICE,
            uint128(0),      // totalCapitalSeconds = 0 (position still open)
            capital,         // currentCapital
            openedAt
        );
        assertEq(payload, expected, "callback payload should encode setReputation correctly");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PositionClosed handling
    // ─────────────────────────────────────────────────────────────────────────

    function test_react_positionClosed_accumulatesCapitalSeconds() public {
        bytes32 posKey  = bytes32(uint256(42));
        uint128 capital = 200e18;
        uint64  openedAt = uint64(block.timestamp);

        _reactOpened(LP_ALICE, posKey, capital, openedAt, 0);

        // Warp 7 days then close
        vm.warp(block.timestamp + 7 days);
        uint64 timeHeld = 7 days;

        _reactClosed(LP_ALICE, posKey, capital, timeHeld, 1000e18, 650e18);

        (uint128 totalCapSec, uint128 currentCap,) = aggregator.reputations(LP_ALICE);

        uint128 expectedCapSec = uint128(uint256(capital) * uint256(timeHeld));
        assertEq(totalCapSec, expectedCapSec, "totalCapitalSeconds = capital * timeHeld");
        assertEq(currentCap,  0,              "currentCapital should drop to 0 after close");
    }

    function test_react_positionClosed_partialCloseReducesCapital() public {
        bytes32 posKey1 = bytes32(uint256(1));
        bytes32 posKey2 = bytes32(uint256(2));

        _reactOpened(LP_ALICE, posKey1, 100e18, uint64(block.timestamp), 0);
        _reactOpened(LP_ALICE, posKey2, 300e18, uint64(block.timestamp), 0);

        // Close only the first position
        _reactClosed(LP_ALICE, posKey1, 100e18, 1 days, 500e18, 325e18);

        (, uint128 currentCap,) = aggregator.reputations(LP_ALICE);
        assertEq(currentCap, 300e18, "remaining capital should equal second position only");
    }

    function test_react_positionClosed_callbackIncludesTotalCapitalSeconds() public {
        bytes32 posKey   = bytes32(uint256(99));
        uint128 capital  = 100e18;
        uint64  timeHeld = 30 days;

        _reactOpened(LP_ALICE, posKey, capital, uint64(block.timestamp), 0);
        vm.warp(block.timestamp + timeHeld);

        vm.recordLogs();
        _reactClosed(LP_ALICE, posKey, capital, timeHeld, 500e18, 325e18);

        bytes memory payload = _findCallbackPayload(vm.getRecordedLogs(), ORACLE_A);

        // Verify selector matches setReputation
        bytes4 expectedSelector = bytes4(keccak256("setReputation(address,uint128,uint128,uint64)"));
        assertEq(bytes4(payload), expectedSelector, "payload selector should be setReputation");

        // Decode the four arguments (skip 4-byte selector)
        bytes memory args = _skipSelector(payload);
        (address lpAddr, uint128 totalCapSec, uint128 currentCap,) =
            abi.decode(args, (address, uint128, uint128, uint64));

        uint128 expectedCapSec = uint128(uint256(capital) * uint256(timeHeld));
        assertEq(lpAddr,      LP_ALICE,        "lp address in payload should be Alice");
        assertEq(totalCapSec, expectedCapSec,  "totalCapitalSeconds = capital * timeHeld");
        assertEq(currentCap,  uint128(0),      "currentCapital should be 0 after close");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Multi-LP isolation
    // ─────────────────────────────────────────────────────────────────────────

    function test_reputations_isolatedPerLP() public {
        _reactOpened(LP_ALICE, bytes32(uint256(1)), 500e18, uint64(block.timestamp), 0);
        _reactOpened(LP_BOT,   bytes32(uint256(2)), 100e18, uint64(block.timestamp), 9100);

        (, uint128 aliceCap,) = aggregator.reputations(LP_ALICE);
        (, uint128 botCap,)   = aggregator.reputations(LP_BOT);

        assertEq(aliceCap, 500e18, "Alice's capital should not be affected by bot's position");
        assertEq(botCap,   100e18, "Bot's capital should not be affected by Alice's position");
    }

    function test_unknownTopic_isIgnored() public {
        bytes32 unknownTopic = keccak256("UnknownEvent(address)");
        // Should not revert and should not update any state
        aggregator.react(
            CHAIN_A, HOOK_ADDR, unknownTopic,
            bytes32(uint256(uint160(LP_ALICE))),
            bytes32(0),
            abi.encode(uint128(100e18))
        );

        (uint128 totalCapSec, uint128 currentCap,) = aggregator.reputations(LP_ALICE);
        assertEq(totalCapSec, 0);
        assertEq(currentCap,  0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _reactOpened(address lp, bytes32 posKey, uint128 capital, uint64 ts, uint16 conc) internal {
        aggregator.react(
            CHAIN_A,
            HOOK_ADDR,
            POSITION_OPENED_SIG,
            bytes32(uint256(uint160(lp))),
            posKey,
            abi.encode(capital, ts, conc)
        );
    }

    function _reactClosed(
        address lp,
        bytes32 posKey,
        uint128 capital,
        uint64 timeHeld,
        uint128 feesEarned,
        uint128 taxPaid
    ) internal {
        aggregator.react(
            CHAIN_A,
            HOOK_ADDR,
            POSITION_CLOSED_SIG,
            bytes32(uint256(uint160(lp))),
            posKey,
            abi.encode(capital, timeHeld, feesEarned, taxPaid)
        );
    }

    bytes32 constant CALLBACK_SIG = keccak256("Callback(uint256,address,uint64,bytes)");

    function _skipSelector(bytes memory data) internal pure returns (bytes memory result) {
        require(data.length >= 4, "too short");
        result = new bytes(data.length - 4);
        for (uint256 i = 0; i < result.length; i++) result[i] = data[i + 4];
    }

    function _findCallbackPayload(Vm.Log[] memory logs, address oracle) internal pure returns (bytes memory) {
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length >= 3 && address(uint160(uint256(logs[i].topics[2]))) == oracle) {
                (, bytes memory payload) = abi.decode(logs[i].data, (uint64, bytes));
                return payload;
            }
        }
        revert("_findCallbackPayload: no Callback found for oracle");
    }

    function _hasCallbackForOracle(Vm.Log[] memory logs, address oracle) internal pure returns (bool) {
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length >= 3 && address(uint160(uint256(logs[i].topics[2]))) == oracle) {
                return true;
            }
        }
        return false;
    }

    function _countCallbackLogs(Vm.Log[] memory logs) internal pure returns (uint256 count) {
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == CALLBACK_SIG) count++;
        }
    }
}
