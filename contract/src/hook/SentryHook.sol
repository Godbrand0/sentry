// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {ISubscriber} from "v4-periphery/src/interfaces/ISubscriber.sol";
import {PositionInfo} from "v4-periphery/src/libraries/PositionInfoLibrary.sol";

import {BaseHook} from "./BaseHook.sol";
import {ISentryHook} from "./interfaces/ISentryHook.sol";
import {IReputationOracle} from "./interfaces/IReputationOracle.sol";
import {TaxCurve} from "./libraries/TaxCurve.sol";
import {PositionKey} from "./libraries/PositionKey.sol";
import {FeeAccounting} from "./libraries/FeeAccounting.sol";
import {RedistributionPool} from "./auxiliary/RedistributionPool.sol";

interface IERC721Minimal {
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @notice Sentry V4 hook — defends long-term LPs from JIT MEV by taxing short-lived
/// positions and redistributing captured fees to loyal LPs.
///
/// Hook permission bits required (encode into contract address via CREATE2):
///   afterInitialize, afterAddLiquidity, afterRemoveLiquidity, afterSwap,
///   afterRemoveLiquidityReturnDelta
///
/// ISubscriber: LPs using PositionManager can subscribe their NFT for accurate
/// per-position tracking and correct redistribution attribution.
contract SentryHook is BaseHook, ISentryHook, ISubscriber {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using TaxCurve for uint64;

    // ── Constants ───────────────────────────────────────────────────────────────

    uint256 public constant PROTOCOL_FEE_CAP_BPS = 1000; // governance hard cap: 10%
    uint64 public constant LONG_TERM_THRESHOLD = 24 hours;

    // ── Governance ──────────────────────────────────────────────────────────────

    address public owner;
    address public pendingOwner;

    uint256 public maxTaxBps = 6500;       // 65% total (60% to LPs + 5% to platform)
    uint256 public halfLife = 600;          // 10 minutes
    uint256 public maxTenureCap = 90 days;
    uint256 public protocolFeeBps = 769;   // ~7.69% of tax = 5% of total fees

    address public treasury;
    IReputationOracle public reputationOracle;

    /// @notice Authorised callers of executeRedistribution (Reactive Network callback gateway).
    mapping(address => bool) public authorizedCallbacks;

    /// @notice V4 PositionManager. When set, subscriber callbacks are accepted from this address
    /// and `params.salt = bytes32(tokenId)` is used to resolve the actual LP owner.
    address public positionManager;

    // ── Per-position state ──────────────────────────────────────────────────────

    mapping(bytes32 => Position) public positions;

    // ── Per-pool state ──────────────────────────────────────────────────────────

    // Pool token0 address for fee transfers
    mapping(PoolId => address) public poolToken0;

    // Redistribution pool per pool
    mapping(PoolId => RedistributionPool) public redistributionPools;

    // Fee growth accumulators (lazy — only read on add/remove liquidity)
    mapping(PoolId => FeeAccounting.PoolFeeState) private _feeState;

    // Per-position fee snapshot (to compute fees earned since last touch)
    mapping(bytes32 => FeeAccounting.PositionFeeSnapshot) private _feeSnapshots;

    // ── Subscriber state ────────────────────────────────────────────────────────
    // tokenId → full PoolId (set on notifySubscribe; used to resolve pool in notifyBurn)
    mapping(uint256 => PoolId) private _tokenPoolId;
    // tokenId → actual LP address (NFT owner at subscribe time; updated on modify)
    mapping(uint256 => address) private _tokenOwner;

    // ── Errors ──────────────────────────────────────────────────────────────────

    error NotOwner();
    error NotAuthorizedCallback();
    error ProtocolFeeCapExceeded();
    error PoolNotRegistered();
    error NotPositionManager();

    // ── Modifiers ───────────────────────────────────────────────────────────────

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyAuthorizedCallback() {
        if (!authorizedCallbacks[msg.sender]) revert NotAuthorizedCallback();
        _;
    }

    modifier onlyPositionManager() {
        if (msg.sender != positionManager) revert NotPositionManager();
        _;
    }

    // ── Constructor ─────────────────────────────────────────────────────────────

    constructor(IPoolManager _poolManager, address _reputationOracle, address _treasury, address _owner)
        BaseHook(_poolManager)
    {
        reputationOracle = IReputationOracle(_reputationOracle);
        treasury = _treasury;
        owner = _owner;
    }

    // ── Hook permissions ────────────────────────────────────────────────────────

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: true,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: true
        });
    }

    // ── Hook callbacks ──────────────────────────────────────────────────────────

    /// @notice Register the pool and deploy its RedistributionPool.
    function afterInitialize(address, PoolKey calldata key, uint160, int24)
        external
        override
        onlyPoolManager
        returns (bytes4)
    {
        PoolId poolId = key.toId();
        address token0 = Currency.unwrap(key.currency0);
        poolToken0[poolId] = token0;

        RedistributionPool rPool = new RedistributionPool(address(this), treasury);
        // Pass the Currency type so RedistributionPool handles both ETH and ERC-20 pools correctly.
        rPool.initPool(PoolId.unwrap(poolId), key.currency0);
        redistributionPools[poolId] = rPool;

        return IHooks.afterInitialize.selector;
    }

    /// @notice Record new position data and snapshot fee growth.
    function afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
        if (params.liquidityDelta <= 0) return (IHooks.afterAddLiquidity.selector, BalanceDelta.wrap(0));

        PoolId poolId = key.toId();
        // Use params.salt (not bytes32(0)) so that PositionManager positions, which set
        // salt = bytes32(tokenId), are keyed uniquely per NFT rather than colliding.
        bytes32 posKey = PositionKey.compute(
            sender, PoolId.unwrap(poolId), params.tickLower, params.tickUpper, params.salt
        );

        uint128 liquidity = uint128(uint256(params.liquidityDelta));

        // If position already exists (add to existing), only update capital; preserve openedAt.
        Position storage pos = positions[posKey];
        bool isNew = pos.openedAt == 0;

        if (isNew) {
            // Concentration score: compare this liquidity to current in-range total.
            // Simplified: pool total liquidity accessible via StateLibrary.getLiquidity(poolManager, poolId).
            // We snapshot at open and store; don't recompute on swap (gas optimization per spec).
            uint16 concentrationBps = _computeConcentrationBps(poolId, liquidity);

            pos.capital = liquidity;
            pos.openedAt = uint64(block.timestamp);
            pos.lastTouched = uint64(block.timestamp);
            pos.feesAccrued = 0;
            pos.concentrationBps = concentrationBps;

            // Snapshot fee growth so we can compute fees earned on close
            FeeAccounting.PoolFeeState storage fs = _feeState[poolId];
            _feeSnapshots[posKey] = FeeAccounting.PositionFeeSnapshot({
                feeGrowthInside0LastX128: fs.feeGrowthGlobal0X128,
                feeGrowthInside1LastX128: fs.feeGrowthGlobal1X128
            });

            // Emit with the actual LP address (resolved from subscriber state if using PositionManager)
            emit PositionOpened(_resolveLP(sender, params.salt), posKey, liquidity, uint64(block.timestamp), concentrationBps);
        } else {
            // Existing position: add capital, keep original openedAt (partial re-add).
            pos.capital += liquidity;
            pos.lastTouched = uint64(block.timestamp);
        }

        return (IHooks.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    /// @notice Calculate tax on fees earned, route to redistribution pool, return delta.
    function afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
        PoolId poolId = key.toId();
        // Use params.salt (not bytes32(0)) — matches the key written in afterAddLiquidity.
        // PositionManager sets salt = bytes32(tokenId), uniquely identifying each NFT position.
        bytes32 posKey = PositionKey.compute(
            sender, PoolId.unwrap(poolId), params.tickLower, params.tickUpper, params.salt
        );

        Position storage pos = positions[posKey];
        if (pos.openedAt == 0) return (IHooks.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));

        // Resolve the actual LP address: if sender is PositionManager and the tokenId (salt)
        // is subscribed, use the stored NFT owner; otherwise fall back to sender.
        address lp = _resolveLP(sender, params.salt);

        uint64 timeHeld = uint64(block.timestamp) - pos.openedAt;
        uint128 removedLiquidity = uint128(uint256(-params.liquidityDelta));

        // Compute fees earned since snapshot using the fee growth accumulator
        (uint128 fees0, ) = FeeAccounting.feesEarned(
            _feeSnapshots[posKey], _feeState[poolId], removedLiquidity
        );

        // Add any fees passed directly by PoolManager for this withdrawal
        int128 feesDirect = feesAccrued.amount0();
        if (feesDirect > 0) fees0 += uint128(feesDirect);

        uint256 taxBps = TaxCurve.calculateFinalTaxBps(timeHeld, pos.concentrationBps);

        // Apply cross-chain reputation discount: global tenure can reduce effective tax.
        taxBps = _applyReputationDiscount(lp, taxBps);

        uint128 taxAmount = 0;
        BalanceDelta hookDelta = BalanceDelta.wrap(0);

        if (taxBps > 0 && fees0 > 0) {
            taxAmount = uint128((uint256(fees0) * taxBps) / 10000);

            // Route tax: take token0 from the LP's payout, send to RedistributionPool
            RedistributionPool rPool = redistributionPools[poolId];

            if (taxAmount > 0 && address(rPool) != address(0)) {
                // Positive hookDelta: callerDelta = callerDelta - hookDelta → LP receives taxAmount less.
                // PM credits hook taxAmount; hook settles by calling take() to route it to rPool.
                hookDelta = toBalanceDelta(int128(taxAmount), 0);

                poolManager.take(key.currency0, address(rPool), taxAmount);
                rPool.deposit(PoolId.unwrap(poolId), taxAmount);

                pos.feesAccrued += fees0;

                emit TaxAccumulated(PoolId.unwrap(poolId), taxAmount);
            }
        }

        bool isFullClose = pos.capital <= removedLiquidity;

        if (isFullClose) {
            emit PositionClosed(lp, posKey, pos.capital, timeHeld, fees0, taxAmount);

            // Deregister from redistribution eligibility using the resolved LP address
            RedistributionPool rPool = redistributionPools[poolId];
            if (address(rPool) != address(0)) {
                rPool.deregisterEligibleLP(PoolId.unwrap(poolId), lp, pos.openedAt);
            }

            delete positions[posKey];
            delete _feeSnapshots[posKey];
        } else {
            // Partial removal: reduce capital, preserve openedAt (tenure continues)
            pos.capital -= removedLiquidity;
            pos.lastTouched = uint64(block.timestamp);
            // Update fee snapshot to current growth for remaining liquidity
            _feeSnapshots[posKey].feeGrowthInside0LastX128 = _feeState[poolId].feeGrowthGlobal0X128;
            _feeSnapshots[posKey].feeGrowthInside1LastX128 = _feeState[poolId].feeGrowthGlobal1X128;
        }

        // Register as eligible long-term LP if just crossed the threshold on partial removal
        if (!isFullClose && timeHeld >= LONG_TERM_THRESHOLD) {
            RedistributionPool rPool = redistributionPools[poolId];
            if (address(rPool) != address(0)) {
                rPool.registerEligibleLP(PoolId.unwrap(poolId), lp, pos.capital, pos.openedAt);
            }
        }

        return (IHooks.afterRemoveLiquidity.selector, hookDelta);
    }

    /// @notice Update global fee accumulator. Runs on every swap — must be cheap.
    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        BalanceDelta swapDelta,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, int128) {
        PoolId poolId = key.toId();

        // Extract fees from swap delta (fees earned are embedded in the PoolManager's accounting).
        // For a swap where zeroForOne, fee is in token0 (amount0 is negative for the swapper,
        // the difference between exact input and output is the fee). We approximate via delta sign.
        // Full precision requires hooking into PoolManager fee state — done here at pool level.
        int128 amount0 = swapDelta.amount0();
        int128 amount1 = swapDelta.amount1();

        uint128 fee0 = amount0 < 0 ? 0 : uint128(amount0);
        uint128 fee1 = amount1 < 0 ? 0 : uint128(amount1);

        // We need total in-range liquidity to update growth per unit. Use poolManager.getLiquidity.
        // This is the only poolManager call in afterSwap — acceptable gas cost.
        uint128 totalLiquidity = StateLibrary.getLiquidity(poolManager, poolId);
        FeeAccounting.accumulateFees(_feeState[poolId], fee0, fee1, totalLiquidity);

        return (IHooks.afterSwap.selector, 0);
    }

    // ── ISubscriber ─────────────────────────────────────────────────────────────
    //
    // LPs using the V4 PositionManager can subscribe their NFT to SentryHook.
    // The PositionManager passes salt = bytes32(tokenId) into every modifyLiquidity call,
    // so hook callbacks and subscriber callbacks share the same position key.
    //
    // Subscription flow:
    //   1. LP calls PositionManager.subscribe(tokenId, address(this), abi.encode(poolId))
    //   2. notifySubscribe records tokenId → actual LP owner + poolId
    //   3. All subsequent hook callbacks resolve the true LP via _resolveLP()
    //   4. On burn, notifyBurn cleans up subscriber state

    function notifySubscribe(uint256 tokenId, bytes memory data) external onlyPositionManager {
        PoolId poolId = abi.decode(data, (PoolId));
        _tokenPoolId[tokenId] = poolId;
        // Record who owns the NFT at subscription time for correct redistribution attribution
        _tokenOwner[tokenId] = IERC721Minimal(positionManager).ownerOf(tokenId);
        emit SubscriberRegistered(tokenId, _tokenOwner[tokenId], PoolId.unwrap(poolId));
    }

    function notifyUnsubscribe(uint256 tokenId) external onlyPositionManager {
        // Gas is capped for this call (EIP-150 / unsubscribeGasLimit). Keep it minimal.
        address lp = _tokenOwner[tokenId];
        _tokenPoolId[tokenId] = PoolId.wrap(bytes32(0));
        delete _tokenOwner[tokenId];
        emit SubscriberDeregistered(tokenId, lp);
    }

    /// @notice Called by PositionManager when the subscribed position modifies liquidity or collects fees.
    /// Used to keep the stored LP address current in case the NFT was transferred.
    function notifyModifyLiquidity(uint256 tokenId, int256, BalanceDelta) external onlyPositionManager {
        // If the NFT has changed hands since subscribe, update the stored owner so that
        // redistribution rewards always target the current holder.
        address currentOwner = IERC721Minimal(positionManager).ownerOf(tokenId);
        if (_tokenOwner[tokenId] != currentOwner) {
            _tokenOwner[tokenId] = currentOwner;
        }
    }

    /// @notice Called by PositionManager when the subscribed position is burned.
    /// The hook's afterRemoveLiquidity has already applied the tax (it runs inside unlock).
    /// This callback fires outside unlock and handles subscriber-state cleanup.
    function notifyBurn(uint256 tokenId, address burnOwner, PositionInfo, uint256, BalanceDelta)
        external
        onlyPositionManager
    {
        emit SubscriberDeregistered(tokenId, burnOwner);
        _tokenPoolId[tokenId] = PoolId.wrap(bytes32(0));
        delete _tokenOwner[tokenId];
    }

    // ── Redistribution ──────────────────────────────────────────────────────────

    /// @notice Trigger a redistribution for a pool. Called by Reactive Network callback.
    /// Permissionless with authorized-callback guard to prevent abuse.
    function executeRedistribution(bytes32 poolId) external onlyAuthorizedCallback {
        PoolId pid = PoolId.wrap(poolId);
        RedistributionPool rPool = redistributionPools[pid];
        if (address(rPool) == address(0)) revert PoolNotRegistered();
        rPool.execute(poolId);
        emit RedistributionExecuted(poolId, rPool.balance(poolId), 0);
    }

    // ── View functions ──────────────────────────────────────────────────────────

    function getPosition(bytes32 positionKey) external view override returns (Position memory) {
        return positions[positionKey];
    }

    function calculateTax(uint64 timeHeld, uint16 concentrationBps)
        external
        pure
        override
        returns (uint256)
    {
        return TaxCurve.calculateFinalTaxBps(timeHeld, concentrationBps);
    }

    // ── Governance ──────────────────────────────────────────────────────────────

    function setProtocolFee(uint256 bps) external onlyOwner {
        if (bps > PROTOCOL_FEE_CAP_BPS) revert ProtocolFeeCapExceeded();
        protocolFeeBps = bps;
    }

    function setReputationOracle(address oracle) external onlyOwner {
        reputationOracle = IReputationOracle(oracle);
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function setPositionManager(address pm) external onlyOwner {
        positionManager = pm;
    }

    function authorizeCallback(address sender) external onlyOwner {
        authorizedCallbacks[sender] = true;
    }

    function revokeCallback(address sender) external onlyOwner {
        authorizedCallbacks[sender] = false;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        pendingOwner = newOwner;
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "SentryHook: not pending owner");
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    // ── Internal helpers ────────────────────────────────────────────────────────

    /// @dev Resolve the true LP address for redistribution attribution.
    /// When using the V4 PositionManager, `sender` is the PM contract and `salt = bytes32(tokenId)`.
    /// If the tokenId is subscribed, return the stored NFT owner; otherwise return sender as-is.
    function _resolveLP(address sender, bytes32 salt) internal view returns (address) {
        if (sender != positionManager || positionManager == address(0)) return sender;
        address subscribedOwner = _tokenOwner[uint256(salt)];
        return subscribedOwner != address(0) ? subscribedOwner : sender;
    }

    /// @dev Concentration score: position liquidity as a fraction of current pool in-range liquidity.
    function _computeConcentrationBps(PoolId poolId, uint128 addedLiquidity)
        internal
        view
        returns (uint16)
    {
        // afterAddLiquidity fires after the position is added, so currentTotal already
        // includes addedLiquidity. Subtract to recover the pre-add pool depth.
        uint128 currentTotal = StateLibrary.getLiquidity(poolManager, poolId);
        if (currentTotal <= addedLiquidity) return 0; // first LP — no prior depth to compare against
        uint256 score = (uint256(addedLiquidity) * 10000) / uint256(currentTotal);
        return uint16(score > 10000 ? 10000 : score);
    }

    /// @dev Discount tax for LPs with strong cross-chain reputation. If global tenure
    /// exceeds LONG_TERM_THRESHOLD, reduce tax proportionally (max 100% reduction).
    function _applyReputationDiscount(address lp, uint256 taxBps) internal view returns (uint256) {
        if (address(reputationOracle) == address(0) || taxBps == 0) return taxBps;

        try reputationOracle.getReputation(lp) returns (IReputationOracle.Reputation memory rep) {
            if (rep.currentCapital == 0) return taxBps;
            uint64 globalTenure = uint64(rep.totalCapitalSeconds / rep.currentCapital);
            if (globalTenure >= LONG_TERM_THRESHOLD) return 0;
            // Linear discount: 0 at 0 global tenure, 100% discount at LONG_TERM_THRESHOLD
            uint256 discount = (taxBps * globalTenure) / LONG_TERM_THRESHOLD;
            return taxBps - discount;
        } catch {
            return taxBps; // Oracle unavailable — no discount
        }
    }
}
