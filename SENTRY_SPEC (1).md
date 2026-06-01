# Sentry

> A Uniswap V4 hook that defends long-term liquidity providers from just-in-time (JIT) MEV extraction by taxing short-lived positions and redistributing those fees to LPs with real tenure. Cross-chain reputation portability is powered by Reactive Network.

**Hackathon:** Uniswap Hook Incubator — Theme: Impermanent Loss and Yield Systems
**Sponsor integration:** Reactive Network
**Target chains:** Unichain Sepolia (primary), Base Sepolia (cross-chain demo), Reactive Kopli (reputation layer)

---

## Table of Contents

1. [Problem Statement](#1-problem-statement)
2. [The Sentry Mechanism](#2-the-sentry-mechanism)
3. [User Flows](#3-user-flows)
4. [Mathematical Model](#4-mathematical-model)
5. [Financial Model](#5-financial-model)
6. [Architecture — Uniswap V4 Hook](#6-architecture--uniswap-v4-hook)
7. [Architecture — Reactive Network Layer](#7-architecture--reactive-network-layer)
8. [Cross-Chain Integration Flow](#8-cross-chain-integration-flow)
9. [Project Structure](#9-project-structure)
10. [Contract Specifications](#10-contract-specifications)
11. [Testing Strategy](#11-testing-strategy)
12. [Three-Week Build Sequence](#12-three-week-build-sequence)
13. [Risks and Mitigations](#13-risks-and-mitigations)
14. [Demo Storyboard](#14-demo-storyboard)

---

## 1. Problem Statement

### The measured harm

Just-in-time (JIT) liquidity is a structural exploit of Uniswap V3/V4's concentrated liquidity design. A bot watches the mempool for large pending swaps, deposits massive liquidity in a single tick right before the swap, captures most of the swap's fees, and withdraws — all within one block.

The harm is well-documented:

- An academic study identified **36,671 JIT attacks** on Ethereum over 20 months, generating ~7,500 ETH in profits.
- These attacks caused **85% average dilution of existing LP fee shares** on the affected swaps.
- ~**50% of Uniswap V3 LPs are unprofitable** versus simply holding the underlying tokens — JIT extraction is a major driver.
- The Uniswap Foundation has explicitly flagged MEV-mitigating hooks as a priority area for V4.

### Why existing solutions fall short

- **Kyber's antisniping vesting** — locks LP rewards entirely for some period. Too blunt; punishes legitimate active management.
- **Off-chain analytics dashboards** — diagnose the problem but don't fix it.
- **Existing V4 anti-JIT hooks** (LiquidityLock, Timelock Loyalty) — early experiments with binary lock periods, no smooth curve, no cross-chain reputation.

### What Sentry does differently

1. **Smooth exponential tax curve** instead of a binary lock — punishes single-block JIT severely while letting legitimate short-term LPs operate.
2. **Capital-weighted, tenure-weighted redistribution** — squatters with minimal deposits can't farm the system.
3. **Cross-chain reputation via Reactive Network** — an LP's tenure on Ethereum carries to Base, Unichain, Arbitrum. Loyalty becomes a portable identity, not a per-pool reset.
4. **Concentration-aware taxation** — even multi-block positions with abusively concentrated capital pay tax. Bots can't trivially adapt by waiting N+1 blocks.

---

## 2. The Sentry Mechanism

### Core rule

When a position is closed (liquidity removed), the hook calculates a tax on its fees earned during its lifetime. The tax rate is a smooth function of:

1. **Time held** — primary factor, decays exponentially
2. **Capital concentration** — multiplier for abusively concentrated positions
3. **Withdrawal completeness** — full vs. partial close affects tenure tracking

Taxed fees flow into a per-pool **Redistribution Pool**. Distributions are made periodically (or per-swap, gas-permitting) to eligible long-term LPs proportional to their `tenure × capital` score.

### The four tiers

| Tier | Time held | Tax on fees earned |
|---|---|---|
| **JIT** | < 1 minute | ~90% |
| **Short** | 1 min – 1 hour | 90% → 10% (curve) |
| **Medium** | 1 hour – 24 hours | 10% → ~1% |
| **Long-term** | > 24 hours | ~0% |

Long-term LPs (>24h continuous holding) become eligible to **receive** redistributions. The longer they hold and the more capital, the larger their share.

### Protocol fee

5% of all redistributed fees flow to the `Treasury` contract. This funds maintenance, audits, and future development. Configurable by governance, hard-capped at 10%.

---

## 3. User Flows

### Flow A — The honest long-term LP (Aisha)

1. Aisha deposits $50,000 into the ETH/USDC pool through the Sentry-enabled hook.
2. Sentry records: `positionId → (openedAt: block 1000, capital: $50K, ticks: 3000-4000)`
3. Over 60 days, swaps occur. Aisha's position earns fees normally.
4. Periodically, the `RedistributionPool` accumulates tax revenue from JIT bots that attacked the pool.
5. On day 30, the redistribution settles. Aisha's share = `(her capital × her tenure) / (sum of all long-term LPs' capital × tenure)`. She receives a bonus payout in addition to her regular fees.
6. On day 60, Aisha withdraws. Her position was held >24h, so **she pays 0% tax** and keeps 100% of earned fees plus all redistribution receipts.

### Flow B — The JIT bot

1. A bot watches the Unichain mempool for large pending swaps.
2. At block 50000, it sees a pending $5M USDC → ETH swap.
3. Bot deposits $50M concentrated in a single tick range right around current price, in the same block as the swap.
4. The swap executes. Bot's liquidity captures ~$2,475 of the $2,500 fee. Other LPs get $25.
5. Bot immediately withdraws at block 50000 (same block, position held 0 blocks).
6. Sentry calculates tax: time held = 0 → tax rate = 90%. Also: concentration multiplier triggers because $50M in one tick is anomalous. Effective tax: 92%.
7. Bot keeps $198 (8%) of the $2,475 fee. The other $2,277 flows to the Redistribution Pool.
8. 5% of $2,277 ($114) goes to the Treasury. The remaining $2,163 is split among eligible long-term LPs.

### Flow C — The legitimate short-term LP (a market maker)

1. A market-maker LP, Vega, deposits $200K with a narrow range during a high-volume hour.
2. After 45 minutes, Vega closes the position to rebalance.
3. Sentry calculates: time held = 45 min. On the exponential curve, this maps to ~15% tax.
4. Vega keeps 85% of fees earned. Annoying but not crushing.
5. Vega's behavior is exactly what active market making looks like. The hook discourages but doesn't prevent it.

### Flow D — Cross-chain reputation (the Reactive Network moment)

1. Aisha has been a long-term LP on Ethereum mainnet for 6 months.
2. She opens a new position on Base for the first time at block 100.
3. The Sentry hook on Base queries the cross-chain reputation oracle: `getReputation(0xAisha)`.
4. The oracle (a destination contract on Base, updated by a Reactive Contract on Reactive Network) returns: `{ globalTenureScore: 180_days, totalCapitalCommitted: $200K }`.
5. Aisha's effective tenure on Base starts at the cross-chain score, not zero.
6. If Aisha withdraws after 30 minutes on Base for an emergency, her effective tax rate is calculated using her global tenure → ~0% tax.
7. A brand-new LP (no cross-chain history) withdrawing after 30 minutes would pay ~30% tax.

---

## 4. Mathematical Model

### Tax curve

```
tax_rate(time_held_seconds) = MAX_TAX × exp(-time_held / HALF_LIFE)
```

Parameters:

| Parameter | Value | Rationale |
|---|---|---|
| `MAX_TAX` | 0.90 | Peak tax for 0-second holds |
| `HALF_LIFE` | 600 seconds (10 min) | Tax halves every 10 minutes |

Sample values:

| Time held | Tax rate |
|---|---|
| 0 sec | 90.0% |
| 60 sec | 81.6% |
| 5 min | 47.7% |
| 10 min | 45.0% |
| 30 min | 11.2% |
| 1 hour | 1.4% |
| 6 hours | <0.01% |
| 24 hours | ~0% |

Implementation note: use a precomputed lookup table or `PRBMath.exp` (fixed-point). On-chain `exp` is expensive — for gas efficiency, use a 256-entry lookup table indexed by `(time_held / 60) mod 256` with linear interpolation, or pre-compute exponents.

### Concentration multiplier

Detect abusively concentrated capital:

```
concentration_score = position_liquidity / total_in_range_liquidity_at_open

if concentration_score > 0.5:
    concentration_multiplier = 1 + (concentration_score - 0.5) × 2  // 1.0 to 2.0
else:
    concentration_multiplier = 1.0

final_tax = min(0.99, tax_rate × concentration_multiplier)
```

A bot dumping $50M into a tick where there's only $5M of other liquidity has `concentration_score ≈ 0.91` → `multiplier = 1.82` → `final_tax = min(0.99, 0.90 × 1.82) = 0.99`.

### Redistribution share

For long-term LPs (continuously held >24h):

```
lp_score = capital_committed × min(time_held_seconds, MAX_TENURE_CAP)

share_i = lp_score_i / Σ(lp_score_j for all eligible LPs)

redistribution_i = (redistribution_pool - protocol_fee) × share_i
```

Where:
- `MAX_TENURE_CAP = 90 days` — capping tenure prevents very old positions from monopolizing rewards
- `protocol_fee = redistribution_pool × 0.05`

### Partial withdrawals

Partial liquidity removal does **not** reset tenure for the remaining liquidity. The withdrawn portion is treated as a closed position with its own tax calculation. The remaining position retains its original `openedAt` timestamp.

Re-deposits to a previously-empty position do **not** restore the prior tenure — they start fresh. (Otherwise, bots could fake long-term holding by intermittent dust deposits.)

---

## 5. Financial Model

### Sustainability via protocol fee

Default 5% of redistributions flow to Treasury. Hard cap 10%, governance-configurable down to 0%.

**Year 1 illustrative model** assuming $50M TVL across 10 Sentry-enabled pools, current JIT-extraction rates of ~3% of LP fees on V3:

| Metric | Value |
|---|---|
| Average daily JIT extraction (pre-Sentry) | $4,100 / day across pools |
| JIT extraction captured by Sentry tax | ~85% (some bots adapt) = $3,485 / day |
| Annual redistribution volume | $1,272,025 |
| Annual protocol revenue (5%) | $63,601 |
| Annual LP redistribution | $1,208,424 |

### Token model (post-hackathon, optional)

Not required for the hackathon submission, but the spec should allow it. A `$SENTRY` governance token could:

- Receive a fraction of protocol fees
- Grant LP tax discounts (e.g., stake N tokens for 20% tax reduction)
- Vote on parameters (`MAX_TAX`, `HALF_LIFE`, eligible chains)

For the hackathon: **document this as future work**. Do not implement.

---

## 6. Architecture — Uniswap V4 Hook

### Hook permissions

```solidity
function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
    return Hooks.Permissions({
        beforeInitialize: false,
        afterInitialize: true,           // Register pool with Sentry registry
        beforeAddLiquidity: false,
        afterAddLiquidity: true,         // Record position tenure
        beforeRemoveLiquidity: false,
        afterRemoveLiquidity: true,      // Calculate tax, route to RedistributionPool
        beforeSwap: false,
        afterSwap: true,                 // Track fees earned per position
        beforeDonate: false,
        afterDonate: false,
        beforeSwapReturnDelta: false,
        afterSwapReturnDelta: false,
        afterAddLiquidityReturnDelta: false,
        afterRemoveLiquidityReturnDelta: true  // Returns the tax delta to PoolManager
    });
}
```

### Core contracts

**`SentryHook.sol`** — The V4 hook. Inherits from `BaseHook`. Implements callbacks.

**`PositionTenureTracker.sol`** — Library or storage contract. Per-position records of `{openedAtTimestamp, capitalAtOpen, concentrationScore, accumulatedFees}`.

**`RedistributionPool.sol`** — Per-pool accumulator of taxed fees. Settles to eligible LPs on a trigger (cron-like, called by a Reactive Contract on Reactive Network).

**`ReputationOracle.sol`** — Destination contract receiving cross-chain reputation updates from Reactive Network. Read by `SentryHook` during tax calculation.

**`Treasury.sol`** — Receives 5% protocol fee. Governance-controlled.

### State variables in SentryHook

```solidity
// Per-position state
struct Position {
    uint128 capital;          // Token amount at deposit (normalized)
    uint64 openedAt;          // block.timestamp
    uint64 lastTouched;       // For partial withdrawal tracking
    uint128 feesAccrued;      // Total fees earned to date
    uint16 concentrationBps;  // Concentration score at open (0-10000)
}
mapping(bytes32 => Position) public positions;  // positionKey = keccak256(owner, poolId, tickLower, tickUpper, salt)

// Per-pool state
struct PoolState {
    uint128 redistributionPool;     // Accumulated taxed fees in token0 equivalent
    uint128 totalLongTermScore;     // Σ(capital × min(tenure, cap)) for eligible LPs
    uint64 lastRedistributionAt;    // Timestamp of last payout
}
mapping(PoolId => PoolState) public poolStates;

// Global config
uint256 public maxTax = 9000;        // bps, 90%
uint256 public halfLife = 600;       // seconds
uint256 public maxTenureCap = 90 days;
uint256 public protocolFeeBps = 500; // 5%
address public treasury;
IReputationOracle public reputationOracle;
```

### Critical gas optimization notes

- `afterSwap` runs on every swap. Track fees per-position lazily — store a per-pool "fees accumulated per liquidity unit" accumulator (like Uniswap's own fee growth tracking). Update individual positions only on `afterAddLiquidity`/`afterRemoveLiquidity`.
- `exp()` computation: use lookup table or PRBMath. Avoid floating-point.
- Concentration score: compute once at `afterAddLiquidity` and store. Don't recompute on swap.

### Hook address mining

V4 requires hook permissions encoded in the contract address. Use CREATE2 with salt mining (HookMiner from v4-periphery) so the address matches the permissions in `getHookPermissions()`.

---

## 7. Architecture — Reactive Network Layer

### Why Reactive Network is the right primitive

Reactive Contracts are Solidity contracts that monitor event logs across multiple EVM chains and execute callback transactions automatically when conditions are met. They run in sandboxed ReactVM execution and don't require off-chain keepers.

Critical properties for Sentry:

1. **Cross-chain event subscription** — a single Reactive Contract can subscribe to events from multiple chains (Ethereum, Base, Unichain) simultaneously.
2. **Conditional callback dispatch** — the contract decides which destination chain(s) to send a callback to.
3. **No off-chain keeper** — autonomy is built into the network.

### The Reactive contracts

**`ReputationAggregator.sol`** (deployed on Reactive Kopli)

Subscribes to `PositionOpened` and `PositionClosed` events from all `SentryHook` deployments across chains. Maintains a global `address → reputation` mapping. When reputation changes meaningfully, sends a callback to all destination `ReputationOracle` contracts with the updated score.

```solidity
contract ReputationAggregator is AbstractReactive {
    struct Reputation {
        uint128 globalTenureScore;       // Σ(capital × tenure) across all chains
        uint128 totalCapitalCommitted;
        uint64 lastUpdate;
    }
    mapping(address => Reputation) public reputations;

    // Subscriptions configured per chain in constructor
    uint256 private constant ETHEREUM_CHAIN_ID = 1;
    uint256 private constant BASE_CHAIN_ID = 8453;
    uint256 private constant UNICHAIN_CHAIN_ID = 130;

    function react(LogRecord calldata log) external vmOnly {
        // Decode event: PositionOpened(address lp, uint128 capital, uint64 timestamp)
        // OR PositionClosed(address lp, uint128 capital, uint64 timeHeld, uint128 feesEarned)

        bytes32 eventSig = log.topic_0;
        address lp = address(uint160(uint256(log.topic_1)));

        if (eventSig == POSITION_OPENED_SIG) {
            _updateOnOpen(lp, log);
        } else if (eventSig == POSITION_CLOSED_SIG) {
            _updateOnClose(lp, log);
        }

        // Dispatch callback to all destination chains
        _emitReputationUpdate(lp, reputations[lp]);
    }
}
```

**`RedistributionScheduler.sol`** (on Reactive Kopli)

Subscribes to per-block events or schedules. Triggers `executeRedistribution(poolId)` on the destination chain's `SentryHook` when:
- The redistribution pool exceeds a threshold (e.g., $1,000 equivalent), OR
- 24 hours have elapsed since last redistribution

This eliminates the need for a keeper bot.

### Subscriptions setup

For each chain we deploy `SentryHook` on, the `ReputationAggregator` needs subscriptions to:

```
subscribe(
    chainId: <chain>,
    contract: <SentryHook address on chain>,
    eventSignature: keccak256("PositionOpened(address,uint128,uint64,uint16)")
)

subscribe(
    chainId: <chain>,
    contract: <SentryHook address on chain>,
    eventSignature: keccak256("PositionClosed(address,uint128,uint64,uint64,uint128)")
)
```

Funding: each Reactive Contract subscription requires REACT tokens for execution gas. Budget ~0.1 REACT per subscription for the hackathon demo.

---

## 8. Cross-Chain Integration Flow

### Reputation update flow

```
[Ethereum]                  [Reactive Kopli]                 [Base]
    │                              │                            │
SentryHook.afterRemoveLiquidity    │                            │
    │                              │                            │
    ├──emits PositionClosed────────▶                            │
    │                              │                            │
    │              ReputationAggregator.react()                  │
    │                              │                            │
    │              updates global reputation                     │
    │                              │                            │
    │                              ├──callback(setReputation)──▶│
    │                              │                            │
    │                              │              ReputationOracle.setReputation()
    │                              │                            │
    │                              │                            │
[Unichain]                          │                            │
    │                              │                            │
    │                              ├──callback(setReputation)──▶│
    │                              │                            │
ReputationOracle.setReputation()    │                            │
```

### Redistribution scheduling flow

```
[Ethereum/Base/Unichain]      [Reactive Kopli]
    │                              │
SentryHook.afterRemoveLiquidity    │
   accumulates tax                 │
    │                              │
    ├──emits TaxAccumulated────────▶
    │                              │
    │              RedistributionScheduler.react()
    │                              │
    │              checks: pool > threshold?
    │              checks: time since last > 24h?
    │                              │
    │              if yes:         │
    │◀──callback(executeRedistribution)
    │                              │
SentryHook.executeRedistribution() │
    pays out to eligible LPs       │
    forwards 5% to Treasury         │
```

---

## 9. Project Structure

```
sentry/
├── README.md
├── foundry.toml
├── remappings.txt
├── .env.example
├── .gitignore
│
├── contracts/
│   ├── hook/
│   │   ├── SentryHook.sol               # Main V4 hook
│   │   ├── libraries/
│   │   │   ├── TaxCurve.sol             # exp() lookup table
│   │   │   ├── ConcentrationOracle.sol  # Concentration scoring
│   │   │   ├── PositionKey.sol          # Position keying utilities
│   │   │   └── FeeAccounting.sol        # Per-position fee tracking
│   │   ├── interfaces/
│   │   │   ├── ISentryHook.sol
│   │   │   ├── IReputationOracle.sol
│   │   │   └── IRedistributionPool.sol
│   │   └── auxiliary/
│   │       ├── RedistributionPool.sol   # Per-pool tax accumulator
│   │       ├── ReputationOracle.sol     # Destination for Reactive callbacks
│   │       └── Treasury.sol             # Protocol fee receiver
│   │
│   └── reactive/
│       ├── ReputationAggregator.sol     # Cross-chain reputation RC
│       ├── RedistributionScheduler.sol  # Per-pool redistribution trigger RC
│       └── interfaces/
│           └── ISentryCallback.sol      # Callback signature
│
├── test/
│   ├── hook/
│   │   ├── SentryHook.t.sol             # Main hook unit tests
│   │   ├── TaxCurve.t.sol               # Math correctness
│   │   ├── JITScenario.t.sol            # Live JIT attack simulation
│   │   ├── LongTermLP.t.sol             # 30-day LP simulation
│   │   ├── ConcentrationAttack.t.sol    # Bot adaptation tests
│   │   └── RedistributionMath.t.sol     # Capital-weighted distribution
│   ├── reactive/
│   │   ├── ReputationAggregator.t.sol
│   │   └── RedistributionScheduler.t.sol
│   └── integration/
│       └── CrossChainReputation.t.sol   # Full multi-chain flow
│
├── script/
│   ├── DeployHook.s.sol                 # Deploys SentryHook with mined address
│   ├── DeployReactive.s.sol             # Deploys Reactive contracts
│   ├── ConfigureSubscriptions.s.sol     # Sets up event subscriptions
│   └── SeedDemo.s.sol                   # Sets up demo state
│
├── lib/                                  # Foundry submodules
│   ├── v4-core/
│   ├── v4-periphery/
│   ├── forge-std/
│   ├── solmate/
│   └── reactive-lib/
│
├── frontend/                             # Next.js demo dashboard
│   ├── app/
│   │   ├── page.tsx                     # Live pool dashboard
│   │   ├── pool/[id]/page.tsx           # Per-pool view
│   │   ├── lp/[address]/page.tsx        # LP reputation card
│   │   └── jit-demo/page.tsx            # Live JIT attack demo
│   ├── components/
│   │   ├── TaxCurveChart.tsx
│   │   ├── PositionList.tsx
│   │   ├── RedistributionFeed.tsx
│   │   └── ReputationBadge.tsx
│   └── lib/
│       ├── contracts.ts
│       └── reactive.ts
│
└── docs/
    ├── architecture.md
    ├── tax-math.md
    ├── reactive-integration.md
    └── security-considerations.md
```

---

## 10. Contract Specifications

### SentryHook.sol — full interface

```solidity
contract SentryHook is BaseHook {
    // Events
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
    event TaxAccumulated(PoolId indexed poolId, uint128 amount);
    event RedistributionExecuted(PoolId indexed poolId, uint128 totalPaid, uint128 protocolFee);
    event RedistributionReceived(address indexed lp, PoolId indexed poolId, uint128 amount);

    // Constructor
    constructor(
        IPoolManager _poolManager,
        address _reputationOracle,
        address _treasury
    ) BaseHook(_poolManager);

    // V4 Hook callbacks
    function _afterAddLiquidity(...) internal override returns (bytes4, BalanceDelta);
    function _afterRemoveLiquidity(...) internal override returns (bytes4, BalanceDelta);
    function _afterSwap(...) internal override returns (bytes4, int128);
    function _afterInitialize(...) internal override returns (bytes4);

    // Public view functions
    function getPosition(bytes32 positionKey) external view returns (Position memory);
    function getPoolState(PoolId poolId) external view returns (PoolState memory);
    function calculateTax(uint64 timeHeld, uint16 concentrationBps) external view returns (uint256);
    function getRedistributionShare(address lp, PoolId poolId) external view returns (uint128);

    // Called by Reactive RedistributionScheduler via callback
    function executeRedistribution(PoolId poolId) external onlyAuthorizedCallback;

    // Governance
    function setMaxTax(uint256 bps) external onlyOwner;
    function setHalfLife(uint256 seconds_) external onlyOwner;
    function setProtocolFee(uint256 bps) external onlyOwner;
    function setReputationOracle(address oracle) external onlyOwner;
}
```

### TaxCurve.sol — gas-efficient exponential

```solidity
library TaxCurve {
    // Precomputed lookup table for exp(-x) where x = seconds / HALF_LIFE
    // Table covers 0 to 10 half-lives (after which tax is effectively 0)
    // 256 entries, linearly interpolated

    uint256 internal constant HALF_LIFE = 600; // 10 minutes
    uint256 internal constant MAX_TAX_BPS = 9000;
    uint256 internal constant TABLE_SIZE = 256;

    function calculateTaxBps(uint64 timeHeldSeconds) internal pure returns (uint256) {
        if (timeHeldSeconds >= HALF_LIFE * 10) return 0; // Effectively zero after 100 min

        uint256 scaled = (timeHeldSeconds * TABLE_SIZE) / (HALF_LIFE * 10);
        uint256 expValue = _interpolateLookup(scaled);
        return (MAX_TAX_BPS * expValue) / 1e18;
    }

    function _interpolateLookup(uint256 index) private pure returns (uint256);
}
```

### ReputationAggregator.sol — Reactive Contract

```solidity
import 'reactive-lib/src/abstract-base/AbstractReactive.sol';

contract ReputationAggregator is AbstractReactive {
    struct GlobalReputation {
        uint128 totalCapitalSeconds; // Σ(capital × duration) across all chains
        uint128 currentCapital;      // Sum of currently-open positions
        uint64 lastEventTimestamp;
    }
    mapping(address => GlobalReputation) public reputations;

    uint256 private constant CALLBACK_GAS_LIMIT = 1_000_000;

    // Event signatures (keccak256 of PositionOpened/Closed)
    uint256 private constant POSITION_OPENED_SIG = uint256(keccak256(
        "PositionOpened(address,bytes32,uint128,uint64,uint16)"
    ));
    uint256 private constant POSITION_CLOSED_SIG = uint256(keccak256(
        "PositionClosed(address,bytes32,uint128,uint64,uint128,uint128)"
    ));

    address[] public destinationOracles; // ReputationOracle on each chain
    uint256[] public destinationChainIds;

    constructor(address _callbackSender) AbstractReactive(_callbackSender) {}

    function setupSubscriptions(
        uint256[] calldata chainIds,
        address[] calldata sentryHooks
    ) external onlyOwner {
        for (uint256 i = 0; i < chainIds.length; i++) {
            service.subscribe(
                chainIds[i],
                sentryHooks[i],
                POSITION_OPENED_SIG,
                0, 0, 0 // Wildcard remaining topics
            );
            service.subscribe(
                chainIds[i],
                sentryHooks[i],
                POSITION_CLOSED_SIG,
                0, 0, 0
            );
        }
    }

    function react(LogRecord calldata log) external vmOnly {
        address lp = address(uint160(uint256(log.topics[1])));

        if (log.topics[0] == bytes32(POSITION_OPENED_SIG)) {
            _handleOpen(lp, log);
        } else if (log.topics[0] == bytes32(POSITION_CLOSED_SIG)) {
            _handleClose(lp, log);
        }

        // Push reputation update to all destination oracles
        _broadcastReputationUpdate(lp);
    }

    function _broadcastReputationUpdate(address lp) private {
        bytes memory payload = abi.encodeWithSignature(
            "setReputation(address,uint128,uint128,uint64)",
            lp,
            reputations[lp].totalCapitalSeconds,
            reputations[lp].currentCapital,
            uint64(block.timestamp)
        );

        for (uint256 i = 0; i < destinationOracles.length; i++) {
            emit Callback(
                destinationChainIds[i],
                destinationOracles[i],
                CALLBACK_GAS_LIMIT,
                payload
            );
        }
    }
}
```

---

## 11. Testing Strategy

### Unit tests (Foundry)

**TaxCurve.t.sol**
- Verify tax at boundaries (0s, 10min, 1h, 24h)
- Verify monotonic decrease
- Gas benchmark (target: <5,000 gas per call)

**SentryHook.t.sol**
- `afterAddLiquidity` correctly records position
- `afterRemoveLiquidity` correctly calculates tax
- `afterSwap` correctly accumulates per-position fees
- Concentration multiplier correctly applies
- Partial withdrawal doesn't reset tenure
- Re-deposit to empty position starts fresh

**JITScenario.t.sol** (the headline test)
- Simulate a large pending swap
- Bot opens + closes position in single block
- Verify tax = ~90%
- Verify redistribution pool receives tax
- Verify long-term LPs receive payout on redistribution

**LongTermLP.t.sol**
- 30-day LP simulation with daily swaps
- Verify no tax on withdrawal
- Verify redistribution receipts accumulate
- Compare to baseline (no Sentry) — Sentry LP should have higher net yield

**ConcentrationAttack.t.sol**
- Bot holds for 100 blocks (avoids basic time tax)
- But with 95% concentration in one tick
- Verify concentration multiplier still applies significant tax

**RedistributionMath.t.sol**
- Squatter LP ($10) with 90 days tenure vs. whale LP ($1M) with 25 days — verify whale gets more
- Multiple LPs with overlapping eligibility windows — verify pro-rata math
- 5% protocol fee correctly forwarded to Treasury

### Integration tests

**CrossChainReputation.t.sol**
- Mock Reactive Network callback flow
- Open position on chain A, close on chain A → reputation updated globally
- Open position on chain B → tax calculation uses global reputation
- Verify same LP gets different treatment on chain B than a brand-new address

### Fuzz tests

- Random sequences of mints, swaps, burns
- Property: protocol invariants (sum of LP balances + treasury + redistribution pool = total fees collected)
- Property: tax never exceeds 99%
- Property: a position held forever never pays tax (within reasonable bounds)

### Gas benchmarks

| Operation | Target gas |
|---|---|
| `afterAddLiquidity` | < 80,000 |
| `afterRemoveLiquidity` (no tax case) | < 50,000 |
| `afterRemoveLiquidity` (with tax) | < 120,000 |
| `afterSwap` (per swap) | < 30,000 |
| `executeRedistribution` (per LP) | < 60,000 |

---

## 12. Three-Week Build Sequence

### Week 1: Core hook, single chain

**Days 1-2: Setup + math primitives**
- Foundry project setup, v4-core / v4-periphery submodules
- Implement `TaxCurve.sol` with lookup table
- Unit tests for tax math
- Implement `PositionKey.sol` and `FeeAccounting.sol` libraries

**Days 3-4: SentryHook callbacks**
- `afterAddLiquidity`: record position
- `afterRemoveLiquidity`: tax calculation
- `afterSwap`: fee accounting (use Uniswap's fee growth tracking pattern)
- `afterInitialize`: pool registration
- Unit tests passing

**Days 5-7: Redistribution mechanics**
- `RedistributionPool.sol` implementation
- Capital-weighted distribution math
- Treasury fee routing
- `Treasury.sol` contract
- JITScenario.t.sol passes (the headline test)
- LongTermLP.t.sol passes

### Week 2: Reactive Network integration

**Days 8-9: Reactive contracts**
- `ReputationAggregator.sol` on Reactive Kopli
- `RedistributionScheduler.sol` on Reactive Kopli
- `ReputationOracle.sol` destination contract for each target chain

**Days 10-11: Cross-chain wiring**
- Subscription configuration scripts
- Deploy to Unichain Sepolia + Base Sepolia
- Wire `ReputationAggregator` to listen to both
- Test reputation propagation manually

**Days 12-14: Integration tests + edge cases**
- CrossChainReputation.t.sol (with mocked callbacks)
- Concentration attack tests
- Squatter prevention tests
- Gas optimization pass

### Week 3: Frontend, demo, write

**Days 15-17: Frontend dashboard**
- Next.js app with live pool view
- Tax curve chart visualization
- Position list with tenure badges
- Redistribution feed (real-time)
- JIT attack demo page (live simulation against forked mainnet)

**Days 18-19: Demo recording**
- Stage three demo scenes (see [Demo Storyboard](#14-demo-storyboard))
- Record using OBS or Loom
- Edit to 4-5 minutes max
- Voiceover

**Days 20-21: Documentation + submission**
- README with citations
- Architecture docs
- Tax math doc with curve visualization
- Reactive integration doc
- Security considerations
- Submit to DoraHacks

---

## 13. Risks and Mitigations

### Technical risks

**Risk: V4 deployments are still maturing, addresses change frequently.**
Mitigation: target Unichain Sepolia and Base Sepolia — both have stable V4 deployments. Pin specific contract addresses in config.

**Risk: Reactive Network callbacks may have latency that affects UX.**
Mitigation: design the hook to work *without* fresh cross-chain reputation (use local reputation as fallback). Cross-chain is an enhancement, not a dependency.

**Risk: Gas costs of exp() and concentration scoring may make hook prohibitive.**
Mitigation: lookup table for exp, pre-compute concentration at open, lazy accounting for fees. Benchmark continuously.

**Risk: Hook address mining is non-trivial and slows iteration.**
Mitigation: HookMiner utility from v4-periphery. Cache mined salts during dev.

### Economic risks

**Risk: JIT bots adapt by holding 100 blocks instead of 1.**
Mitigation: concentration multiplier targets this directly. A bot holding 100 blocks with 95% concentration still gets taxed heavily.

**Risk: Squatter LPs farm redistribution.**
Mitigation: capital-weighted scoring + tenure cap. A whale with 25 days dominates a squatter with 90 days.

**Risk: Traders avoid Sentry pools because JIT made their execution better.**
Mitigation: acknowledge in writeup. Note that auction-based JIT (future work) preserves execution quality. For hackathon: show the trade-off honestly with numbers.

### Hackathon risks

**Risk: 3 weeks isn't enough for the cross-chain demo.**
Mitigation: prioritize. Week 1 = local hook works. Week 2 = single-chain demo works. Week 3 = cross-chain is bonus. If running behind, ship single-chain only and put cross-chain in roadmap.

**Risk: Demo doesn't land — the JIT scenario is hard to visualize.**
Mitigation: invest in the dashboard. Make tax application visible in real time. Show before/after LP balance with timestamps. Consider an animated diagram in the README.

---

## 14. Demo Storyboard

**Total length: 4-5 minutes**

### Scene 1 (0:00 - 0:45) — The problem

- Open with the academic stat: "36,671 JIT attacks. 7,500 ETH extracted. 85% LP dilution."
- Visual: animated chart of a JIT attack — bot deposits, swap happens, bot withdraws, fees taken.
- Voiceover: "Uniswap V3 LPs lose money. Half of them are unprofitable. JIT bots are a big reason why."

### Scene 2 (0:45 - 2:00) — Sentry on a single chain

- Cut to dashboard. ETH/USDC pool with Sentry hook enabled.
- Stage a JIT attack: terminal command launches the JIT bot. Pool dashboard shows position open + close in 1 block.
- Tax calculation appears: 90% of fees taken.
- Long-term LP "Aisha" (highlighted in dashboard) receives redistribution.
- Show before/after: bot expected $2,475, kept $198. Aisha gained $2,163.
- Voiceover: "Sentry doesn't ban JIT. It prices it. Bots that extract pay for the privilege. Real LPs get paid."

### Scene 3 (2:00 - 3:30) — Cross-chain reputation

- Switch to Base. New pool.
- New LP "Bob" opens position. He's a fresh address. After 30 minutes, withdraws. Pays 11% tax.
- Aisha (the 6-month LP from Ethereum) opens position on Base for the first time. Withdraws after the same 30 minutes. Pays ~0%.
- Show the Reactive Network explorer: the subscription, the cross-chain callback, the reputation update on Base.
- Voiceover: "Loyalty is portable. Your tenure on one chain is recognized on every other chain. Without keepers. Without bridges. Pure event-driven Reactive logic."

### Scene 4 (3:30 - 4:30) — Architecture + close

- Architecture diagram: V4 hooks on Ethereum/Base/Unichain → events → ReputationAggregator on Reactive Kopli → callbacks → destination oracles.
- Highlight the smooth tax curve.
- Mention protocol sustainability: 5% fee, governance-configurable.
- Close: "Sentry. The hook that makes LPing on Uniswap worth it again."

---

## Submission checklist

- [ ] All contracts deployed to Unichain Sepolia
- [ ] Reactive contracts deployed to Reactive Kopli with subscriptions funded
- [ ] At least one ReputationOracle on Base Sepolia receiving callbacks
- [ ] All tests passing (unit + integration)
- [ ] Gas benchmarks recorded in README
- [ ] Public GitHub repository with clear README
- [ ] Demo video (4-5 minutes) uploaded
- [ ] Architecture documentation
- [ ] Tax math documentation with visualizations
- [ ] Security considerations doc
- [ ] Frontend dashboard live (Vercel preview)
- [ ] DoraHacks submission updated with refined description, sponsor integration links

---

## Open questions for build

1. Should `executeRedistribution` be permissioned (only callable by Reactive callback) or permissionless (anyone can trigger, anti-DoS guarded)?
2. How do we handle pool initialization — should pool creators have to fund a minimum to enable Sentry?
3. Should there be a maximum redistribution payout per address per call (to prevent gas griefing during settlement)?
4. For partial position adjustments (V4 lets you modify range), how do we treat tenure? My recommendation: range modification = close + reopen with fresh tenure. Document this explicitly so honest LPs know not to fidget with their ranges.

Resolve these in the first few days of Week 1.
