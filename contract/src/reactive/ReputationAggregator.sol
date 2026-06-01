// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// NOTE: This contract is deployed on Reactive Kopli (ReactVM).
// It subscribes to PositionOpened / PositionClosed events from SentryHook deployments
// across multiple chains and broadcasts reputation updates to destination ReputationOracle
// contracts via Reactive Network callbacks.
//
// The AbstractReactive base and ISubscriptionService interfaces are provided by reactive-lib.
// Import paths assume reactive-lib is installed as a Foundry submodule at lib/reactive-lib/.
// Adjust if the package layout differs.

// Stub interfaces — replaced by reactive-lib imports when the submodule is in place.
interface ISubscriptionService {
    function subscribe(uint256 chainId, address contractAddr, uint256 topic0, uint256 topic1, uint256 topic2, uint256 topic3) external;
    function unsubscribe(uint256 chainId, address contractAddr, uint256 topic0) external;
}

/// @notice Emitted by Reactive Contracts to dispatch callbacks to destination chains.
/// The Reactive Network picks these up and submits the encoded call to the target contract.
interface IReactiveCallback {
    event Callback(uint256 indexed chainId, address indexed target, uint64 gasLimit, bytes payload);
}

/// @notice Cross-chain LP reputation aggregator. Runs on Reactive Kopli.
contract ReputationAggregator is IReactiveCallback {
    // ── Event signatures (keccak256 of the emitted event) ──────────────────────

    bytes32 private constant POSITION_OPENED_SIG =
        keccak256("PositionOpened(address,bytes32,uint128,uint64,uint16)");

    bytes32 private constant POSITION_CLOSED_SIG =
        keccak256("PositionClosed(address,bytes32,uint128,uint64,uint128,uint128)");

    // ── State ───────────────────────────────────────────────────────────────────

    address public owner;
    ISubscriptionService public immutable service;
    uint64 public constant CALLBACK_GAS_LIMIT = 1_000_000;

    struct GlobalReputation {
        uint128 totalCapitalSeconds; // Σ(capital × duration) across all chains
        uint128 currentCapital;      // Sum of currently-open positions (all chains)
        uint64 lastEventTimestamp;
    }

    mapping(address => GlobalReputation) public reputations;

    // Destination ReputationOracle contracts indexed by chain
    address[] public destinationOracles;
    uint256[] public destinationChainIds;

    // Track open positions to compute duration on close
    struct OpenPosition {
        uint128 capital;
        uint64 openedAt;
    }
    // positionKey → open position data (populated on PositionOpened)
    mapping(bytes32 => OpenPosition) private _openPositions;

    // ── Events ──────────────────────────────────────────────────────────────────

    event ReputationUpdated(address indexed lp, uint128 totalCapitalSeconds, uint128 currentCapital);
    event SubscriptionAdded(uint256 chainId, address sentryHook);
    event DestinationAdded(uint256 chainId, address oracle);

    // ── Modifiers ───────────────────────────────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, "RA: not owner");
        _;
    }

    /// @dev In production, restrict to the Reactive Network's VMOnly caller.
    /// Reactive-lib provides a vmOnly modifier — wire it in when the lib is available.
    modifier vmOnly() {
        // TODO: replace with reactive-lib's vmOnly once lib/reactive-lib is installed
        _;
    }

    // ── Constructor ─────────────────────────────────────────────────────────────

    constructor(address _service, address _owner) {
        service = ISubscriptionService(_service);
        owner = _owner;
    }

    // ── Subscription management ─────────────────────────────────────────────────

    /// @notice Subscribe to PositionOpened and PositionClosed events from a SentryHook deployment.
    function addSubscription(uint256 chainId, address sentryHook) external onlyOwner {
        service.subscribe(chainId, sentryHook, uint256(POSITION_OPENED_SIG), 0, 0, 0);
        service.subscribe(chainId, sentryHook, uint256(POSITION_CLOSED_SIG), 0, 0, 0);
        emit SubscriptionAdded(chainId, sentryHook);
    }

    /// @notice Add a destination ReputationOracle to receive callbacks.
    function addDestination(uint256 chainId, address oracle) external onlyOwner {
        destinationChainIds.push(chainId);
        destinationOracles.push(oracle);
        emit DestinationAdded(chainId, oracle);
    }

    // ── Reactive callback ───────────────────────────────────────────────────────

    /// @notice Entry point called by the Reactive Network for each subscribed event.
    /// In production this receives a `LogRecord` struct from reactive-lib; here we use
    /// individual decoded fields for clarity until the lib is wired.
    function react(
        uint256, /* chainId */
        address, /* origin contract */
        bytes32 topic0,
        bytes32 topic1, /* indexed lp address */
        bytes32 topic2, /* indexed positionKey */
        bytes memory data
    ) external vmOnly {
        address lp = address(uint160(uint256(topic1)));
        bytes32 posKey = topic2;

        if (topic0 == POSITION_OPENED_SIG) {
            _handleOpen(lp, posKey, data);
        } else if (topic0 == POSITION_CLOSED_SIG) {
            _handleClose(lp, posKey, data);
        }

        _broadcastUpdate(lp);
    }

    // ── Internal ─────────────────────────────────────────────────────────────────

    function _handleOpen(address lp, bytes32 posKey, bytes memory data) private {
        // PositionOpened non-indexed args: (uint128 capital, uint64 timestamp, uint16 concentrationBps)
        (uint128 capital, uint64 timestamp,) = abi.decode(data, (uint128, uint64, uint16));

        _openPositions[posKey] = OpenPosition({capital: capital, openedAt: timestamp});
        reputations[lp].currentCapital += capital;
        reputations[lp].lastEventTimestamp = timestamp;
    }

    function _handleClose(address lp, bytes32 posKey, bytes memory data) private {
        // PositionClosed non-indexed args: (uint128 capital, uint64 timeHeld, uint128 feesEarned, uint128 taxPaid)
        (uint128 capital, uint64 timeHeld,,) = abi.decode(data, (uint128, uint64, uint128, uint128));

        GlobalReputation storage rep = reputations[lp];

        // Accumulate capital-seconds for closed position
        unchecked {
            rep.totalCapitalSeconds += uint128(uint256(capital) * uint256(timeHeld));
        }

        // Reduce open capital (safe: cap at zero)
        rep.currentCapital = rep.currentCapital >= capital ? rep.currentCapital - capital : 0;
        rep.lastEventTimestamp = uint64(block.timestamp);

        delete _openPositions[posKey];
    }

    function _broadcastUpdate(address lp) private {
        GlobalReputation storage rep = reputations[lp];
        bytes memory payload = abi.encodeWithSignature(
            "setReputation(address,uint128,uint128,uint64)",
            lp,
            rep.totalCapitalSeconds,
            rep.currentCapital,
            rep.lastEventTimestamp
        );

        for (uint256 i = 0; i < destinationOracles.length; i++) {
            emit Callback(destinationChainIds[i], destinationOracles[i], CALLBACK_GAS_LIMIT, payload);
        }
    }
}
