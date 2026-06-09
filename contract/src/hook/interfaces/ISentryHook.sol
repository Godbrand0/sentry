// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ISentryHook {
    struct Position {
        uint128 capital;         // Liquidity units at deposit
        uint64 openedAt;         // block.timestamp at open
        uint64 lastTouched;      // Updated on partial withdrawal
        uint128 feesAccrued;     // Lifetime fees earned (token0 equivalent)
        uint16 concentrationBps; // Concentration score at open (0-10000)
    }

    struct PoolState {
        uint128 redistributionPool;  // Accumulated taxed fees
        uint128 totalLongTermScore;  // Σ(capital × min(tenure, cap)) for eligible LPs
        uint64 lastRedistributionAt; // Timestamp of last payout
    }

    event PositionOpened(
        address indexed lp,
        bytes32 indexed positionKey,
        uint128 capital,
        uint64 timestamp,
        uint16 concentrationBps
    );

    event PositionClosed(
        address indexed lp,
        bytes32 indexed positionKey,
        uint128 capital,
        uint64 timeHeld,
        uint128 feesEarned,
        uint128 taxPaid
    );

    event TaxAccumulated(bytes32 indexed poolId, uint128 amount);

    event RedistributionExecuted(bytes32 indexed poolId, uint128 totalPaid, uint128 protocolFee);

    event RedistributionReceived(address indexed lp, bytes32 indexed poolId, uint128 amount);

    // Emitted when an LP subscribes their PositionManager NFT to Sentry for opt-in tracking.
    event SubscriberRegistered(uint256 indexed tokenId, address indexed lp, bytes32 poolId);

    // Emitted when a subscribed position is closed or unsubscribed.
    event SubscriberDeregistered(uint256 indexed tokenId, address indexed lp);

    function getPosition(bytes32 positionKey) external view returns (Position memory);

    function calculateTax(uint64 timeHeld, uint16 concentrationBps) external view returns (uint256);

    function executeRedistribution(bytes32 poolId) external;
}
