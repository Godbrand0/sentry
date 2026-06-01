// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// NOTE: Deployed on Reactive Kopli. Subscribes to TaxAccumulated events from SentryHook
// and dispatches executeRedistribution callbacks when thresholds are met.

interface ISubscriptionService {
    function subscribe(uint256 chainId, address contractAddr, uint256 topic0, uint256 topic1, uint256 topic2, uint256 topic3) external;
}

interface IReactiveCallback {
    event Callback(uint256 indexed chainId, address indexed target, uint64 gasLimit, bytes payload);
}

contract RedistributionScheduler is IReactiveCallback {
    bytes32 private constant TAX_ACCUMULATED_SIG = keccak256("TaxAccumulated(bytes32,uint128)");

    uint128 public constant THRESHOLD_AMOUNT = 1_000e6;  // $1,000 equivalent (token0 units, adjust per pool)
    uint64 public constant COOLDOWN = 24 hours;

    address public owner;
    ISubscriptionService public immutable service;
    uint64 public constant CALLBACK_GAS_LIMIT = 500_000;

    struct PoolSchedule {
        uint128 accumulated;         // Tax accumulated since last redistribution
        uint64 lastRedistributionAt; // Timestamp of last triggered redistribution
    }

    // chainId → hookAddress → poolId → schedule
    mapping(uint256 => mapping(address => mapping(bytes32 => PoolSchedule))) private _schedules;

    // Destination hooks per chain
    mapping(uint256 => address) public destinationHooks;

    event SubscriptionAdded(uint256 chainId, address sentryHook);
    event RedistributionTriggered(uint256 chainId, bytes32 poolId, uint128 accumulated);

    modifier onlyOwner() {
        require(msg.sender == owner, "RS: not owner");
        _;
    }

    modifier vmOnly() {
        // TODO: replace with reactive-lib vmOnly
        _;
    }

    constructor(address _service, address _owner) {
        service = ISubscriptionService(_service);
        owner = _owner;
    }

    function addSubscription(uint256 chainId, address sentryHook) external onlyOwner {
        service.subscribe(chainId, sentryHook, uint256(TAX_ACCUMULATED_SIG), 0, 0, 0);
        destinationHooks[chainId] = sentryHook;
        emit SubscriptionAdded(chainId, sentryHook);
    }

    /// @notice Called by Reactive Network for each TaxAccumulated event.
    function react(
        uint256 chainId,
        address origin,
        bytes32 topic0,
        bytes32 topic1, /* indexed poolId */
        bytes32,
        bytes memory data
    ) external vmOnly {
        if (topic0 != TAX_ACCUMULATED_SIG) return;

        bytes32 poolId = topic1;
        (uint128 amount) = abi.decode(data, (uint128));

        PoolSchedule storage sched = _schedules[chainId][origin][poolId];
        sched.accumulated += amount;

        bool thresholdMet = sched.accumulated >= THRESHOLD_AMOUNT;
        bool cooldownExpired = block.timestamp >= sched.lastRedistributionAt + COOLDOWN;

        if (thresholdMet || cooldownExpired) {
            sched.accumulated = 0;
            sched.lastRedistributionAt = uint64(block.timestamp);

            address hookAddr = destinationHooks[chainId];
            if (hookAddr == address(0)) hookAddr = origin;

            bytes memory payload = abi.encodeWithSignature("executeRedistribution(bytes32)", poolId);
            emit Callback(chainId, hookAddr, CALLBACK_GAS_LIMIT, payload);

            emit RedistributionTriggered(chainId, poolId, sched.accumulated);
        }
    }
}
