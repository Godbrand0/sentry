// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";

/// @notice Per-pool accumulator for taxed fees. Settles to eligible long-term LPs
/// when triggered by the Reactive RedistributionScheduler or anyone calling execute().
///
/// Eligibility: continuously held > 24h (LONG_TERM_THRESHOLD).
/// Share: lp_score = capital × min(tenure, MAX_TENURE_CAP)
contract RedistributionPool {
    using CurrencyLibrary for Currency;

    uint64 public constant LONG_TERM_THRESHOLD = 24 hours;
    uint64 public constant MAX_TENURE_CAP = 90 days;
    uint256 public constant PROTOCOL_FEE_BPS = 769; // ~7.69% of tax = 5% of total fees (60% LP + 5% platform)

    address public hook;     // Only SentryHook may register positions and deposit
    address public treasury;

    struct EligibleLP {
        address lp;
        uint128 capital;
        uint64 openedAt;
    }

    struct PoolAccumulator {
        Currency currency;      // Supports both ERC-20 and native ETH pools
        uint128 balance;
        uint64 lastRedistributionAt;
        EligibleLP[] eligibleLPs;
    }

    mapping(bytes32 => PoolAccumulator) private _pools;

    event Deposited(bytes32 indexed poolId, uint128 amount);
    event Redistributed(bytes32 indexed poolId, uint128 totalPaid, uint128 protocolFee, uint32 lpCount);
    event LPPaid(bytes32 indexed poolId, address indexed lp, uint128 amount);

    modifier onlyHook() {
        require(msg.sender == hook, "RPool: not hook");
        _;
    }

    constructor(address _hook, address _treasury) {
        hook = _hook;
        treasury = _treasury;
    }

    /// @notice Register a pool's reward currency. Called by hook on afterInitialize.
    function initPool(bytes32 poolId, Currency currency) external onlyHook {
        _pools[poolId].currency = currency;
    }

    /// @notice Register a new long-term-eligible LP. Called by hook when position crosses threshold.
    function registerEligibleLP(bytes32 poolId, address lp, uint128 capital, uint64 openedAt)
        external
        onlyHook
    {
        _pools[poolId].eligibleLPs.push(EligibleLP({lp: lp, capital: capital, openedAt: openedAt}));
    }

    /// @notice Remove a position from the eligible list (called on close or partial withdrawal).
    function deregisterEligibleLP(bytes32 poolId, address lp, uint64 openedAt) external onlyHook {
        EligibleLP[] storage lps = _pools[poolId].eligibleLPs;
        for (uint256 i = 0; i < lps.length; i++) {
            if (lps[i].lp == lp && lps[i].openedAt == openedAt) {
                lps[i] = lps[lps.length - 1];
                lps.pop();
                return;
            }
        }
    }

    /// @notice Accumulate taxed fees. Hook must transfer tokens to this contract before calling.
    function deposit(bytes32 poolId, uint128 amount) external onlyHook {
        _pools[poolId].balance += amount;
        emit Deposited(poolId, amount);
    }

    /// @notice Distribute accumulated fees to eligible LPs. Permissionless — anyone may trigger,
    /// but primary caller is the Reactive RedistributionScheduler callback.
    function execute(bytes32 poolId) external {
        PoolAccumulator storage pool = _pools[poolId];
        uint128 total = pool.balance;
        if (total == 0) return;

        uint128 protocolFee = uint128((uint256(total) * PROTOCOL_FEE_BPS) / 10000);
        uint128 toDistribute = total - protocolFee;
        pool.balance = 0;
        pool.lastRedistributionAt = uint64(block.timestamp);

        // Send protocol fee to treasury (handles both ETH and ERC-20 pools)
        if (protocolFee > 0) {
            pool.currency.transfer(treasury, protocolFee);
        }

        // Compute LP scores and total
        EligibleLP[] storage lps = pool.eligibleLPs;
        uint256 n = lps.length;
        if (n == 0) {
            // No eligible LPs — return funds to protocol treasury rather than locking
            pool.currency.transfer(treasury, toDistribute);
            emit Redistributed(poolId, 0, protocolFee + toDistribute, 0);
            return;
        }

        uint256 totalScore = 0;
        uint256[] memory scores = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            uint64 tenure = uint64(block.timestamp) - lps[i].openedAt;
            uint64 cappedTenure = tenure > MAX_TENURE_CAP ? MAX_TENURE_CAP : tenure;
            scores[i] = uint256(lps[i].capital) * uint256(cappedTenure);
            totalScore += scores[i];
        }

        uint128 totalPaid = 0;
        for (uint256 i = 0; i < n; i++) {
            if (scores[i] == 0) continue;
            uint128 payout = uint128((uint256(toDistribute) * scores[i]) / totalScore);
            if (payout == 0) continue;
            pool.currency.transfer(lps[i].lp, payout);
            totalPaid += payout;
            emit LPPaid(poolId, lps[i].lp, payout);
        }

        emit Redistributed(poolId, totalPaid, protocolFee, uint32(n));
    }

    function balance(bytes32 poolId) external view returns (uint128) {
        return _pools[poolId].balance;
    }

    function eligibleLPCount(bytes32 poolId) external view returns (uint256) {
        return _pools[poolId].eligibleLPs.length;
    }

    function lastRedistributionAt(bytes32 poolId) external view returns (uint64) {
        return _pools[poolId].lastRedistributionAt;
    }
}
