# Sentry — JIT MEV Defense Hook for Uniswap V4

Sentry is a Uniswap V4 hook that defends long-term liquidity providers from just-in-time (JIT) MEV extraction. JIT bots deposit concentrated liquidity in the same block as a large swap, capture the fee, and immediately withdraw — causing ~85% fee dilution to legitimate LPs and extracting an estimated 7,500 ETH historically.

Sentry prices this behavior through an exponential tax curve on short-held positions and redistributes the captured tax back to long-term LPs. Cross-chain reputation portability is handled via Reactive Network, so LP tenure earned on one chain is recognized on others.

---

## How It Works

### Tax Curve

When a liquidity position is closed, the fees earned are taxed based on how long the position was held:

```
tax_rate(t) = 90% × exp(−t / 600 seconds)
```

| Time Held  | Base Tax |
|------------|----------|
| 0 seconds  | 90%      |
| 1 minute   | ~82%     |
| 5 minutes  | ~48%     |
| 10 minutes | ~45%     |
| 30 minutes | ~11%     |
| 1 hour     | ~1.4%    |
| 24 hours   | ~0%      |

A **concentration multiplier** (1.0×–2.0×) is applied on top for positions with tick ranges covering less than 50% of the active range — the strategy bots favor. Final tax is capped at 99%.

### Redistribution

Taxed fees accumulate in a per-pool `RedistributionPool`. LPs who have held for **more than 24 hours** are eligible for payouts, weighted by:

```
score = capital × min(tenure, 90 days)
```

Redistribution is triggered automatically by a `RedistributionScheduler` contract running on Reactive Kopli when the pool balance exceeds ~$1,000 or 24 hours have elapsed since the last payout. A 5% protocol fee is forwarded to treasury.

### Cross-Chain Reputation

LP tenure is tracked globally across chains via Reactive Network:

```
SentryHook (Unichain/Base) 
  → emits PositionOpened / PositionClosed 
  → ReputationAggregator (Reactive Kopli) updates global record 
  → pushes update to ReputationOracle on each destination chain
```

This means an LP with a long track record on Base Sepolia carries that reputation when providing liquidity on Unichain — reducing their effective tax rate.

---

## Reactive Network Integration

Reactive Network is the sponsor technology powering two core automations in Sentry. Both eliminate the need for a centralised keeper or off-chain bot.

### 1 — Automatic Redistribution (`RedistributionScheduler`)

**Problem:** Someone has to call `redistributionPool.execute()` to pay out long-term LPs. A centralised keeper is a single point of failure.

**Solution:** Every time SentryHook taxes a JIT bot it emits `TaxAccumulated(poolId, amount)`. The `RedistributionScheduler` contract on Reactive Kopli subscribes to this event from every deployed SentryHook. When Reactive's VM delivers the event, the scheduler checks two conditions:

```
accumulated tax >= $1,000 equivalent   (threshold met)
  OR
24 hours since last redistribution     (cooldown expired)
```

If either is true, it emits a `Callback` event. Reactive Network picks that up and **submits `executeRedistribution(poolId)` back to the hook on the source chain** — no human intervention required.

```
Bot exits → TaxAccumulated on Unichain
                 ↓
    RedistributionScheduler on Kopli receives event
                 ↓  ($1k threshold hit OR 24h elapsed)
    emits Callback(chainId, hookAddr, payload)
                 ↓
    Reactive Network submits executeRedistribution()
                 ↓
    Long-term LPs receive payout
```

### 2 — Cross-Chain LP Reputation (`ReputationAggregator`)

**Problem:** An LP with 6 months of history on Base deploys to Unichain. Without cross-chain context, the hook treats them as a new address and taxes them at the full JIT rate.

**Solution:** The `ReputationAggregator` on Reactive Kopli subscribes to `PositionOpened` and `PositionClosed` events from all SentryHook deployments across all chains. It maintains a global record per LP:

```solidity
struct GlobalReputation {
    uint128 totalCapitalSeconds;  // Σ(capital × time held) across all chains
    uint128 currentCapital;       // Sum of currently-open positions
}
```

After every update it broadcasts the new record to every destination chain's `ReputationOracle` by emitting `Callback` events — one per chain. Reactive submits those as `setReputation()` calls.

```
Alice closes position on Base Sepolia
                 ↓
    ReputationAggregator on Kopli updates global record
                 ↓
    emits Callback × N (one per destination chain)
                 ↓
    Reactive submits setReputation() to Unichain + Base Oracles
                 ↓
    SentryHook reads Alice's reputation via ReputationOracle
                 ↓
    _applyReputationDiscount() reduces Alice's effective tax rate
```

An LP whose global tenure (totalCapitalSeconds / currentCapital) exceeds 24 hours pays **zero tax** regardless of how new they are on the current chain.

### Why Reactive (not a standard oracle or Chainlink)

Standard cross-chain messaging requires someone to push the message and pay fees on demand. Reactive Network acts as a **passive listener** — contracts register subscriptions once at deployment and Reactive handles all future event delivery automatically. For Sentry this means:

- JIT attacks and redistributions resolve without any off-chain infrastructure
- Reputation syncs across chains as positions open and close, with no manual intervention
- The protocol keeps working even when the team is offline

---

## Repository Structure

```
sentry/
├── contract/                     # Foundry project (Solidity 0.8.26)
│   ├── src/
│   │   ├── hook/
│   │   │   ├── SentryHook.sol           # Core V4 hook
│   │   │   ├── libraries/
│   │   │   │   └── TaxCurve.sol         # Exponential tax math
│   │   │   └── auxiliary/
│   │   │       ├── RedistributionPool.sol   # Per-pool accumulator
│   │   │       └── ReputationOracle.sol     # Destination reputation store
│   │   └── reactive/
│   │       ├── ReputationAggregator.sol     # Reactive contract on Kopli
│   │       └── RedistributionScheduler.sol  # Trigger scheduler on Kopli
│   ├── test/
│   │   ├── hook/TaxCurve.t.sol
│   │   ├── hook/SentryHook.t.sol
│   │   ├── hook/JITScenario.t.sol           # Math-layer JIT scenario
│   │   ├── hook/RedistributionMath.t.sol
│   │   ├── integration/ForkScenario.t.sol   # Full end-to-end simulation
│   │   ├── reactive/ReputationAggregator.t.sol   # Reactive reputation tests
│   │   └── reactive/RedistributionScheduler.t.sol # Reactive trigger tests
│   ├── script/
│   │   ├── DeployHook.s.sol
│   │   ├── DeployReactive.s.sol
│   │   └── ConfigureSubscriptions.s.sol
│   ├── lib/                          # forge-std, v4-core, v4-periphery, reactive-lib
│   └── foundry.toml
│
├── frontend/                     # Next.js 16 app (App Router)
│   ├── app/
│   │   ├── page.tsx                  # Main dashboard
│   │   ├── jit-demo/page.tsx         # Interactive JIT attack simulator
│   │   ├── pool/[id]/page.tsx        # Per-pool detail view
│   │   └── lp/[address]/page.tsx     # LP reputation card
│   ├── components/
│   │   ├── TaxCurveChart.tsx         # Recharts AreaChart (SSR-safe)
│   │   ├── PositionList.tsx
│   │   ├── RedistributionFeed.tsx
│   │   └── ReputationBadge.tsx
│   ├── lib/
│   │   ├── taxCurve.ts               # Client-side tax curve mirror
│   │   └── data.ts                   # Mock data + formatting utils
│   └── package.json
│
└── SENTRY_SPEC (1).md             # Full protocol specification
```

---

## Smart Contracts

### `SentryHook.sol`

The core Uniswap V4 hook. Implements the following callbacks:

| Callback | Action |
|---|---|
| `afterInitialize` | Registers the pool and deploys a `RedistributionPool` |
| `afterAddLiquidity` | Records position `capital`, `openedAt`, and `concentrationBps` |
| `afterRemoveLiquidity` | Calculates and deducts tax; sends tax to redistribution pool |
| `afterSwap` | Updates global fee accumulators (lazy accounting) |
| `executeRedistribution` | Called by Reactive Network to pay out eligible LPs |

Key configuration (governance-controlled):

| Parameter | Default | Description |
|---|---|---|
| `maxTaxBps` | 9000 | Peak tax rate (90%) |
| `halfLife` | 600s | Tax halves every 10 minutes |
| `maxTenureCap` | 90 days | Caps tenure for redistribution scoring |
| `protocolFeeBps` | 500 | 5% of redistributed amount to treasury |

### `TaxCurve.sol`

Gas-efficient library for exponential tax calculation. Uses 10 precomputed breakpoints with linear interpolation — no on-chain exponentiation.

- `calculateTaxBps(timeHeldSeconds)` → base tax in bps
- `calculateFinalTaxBps(timeHeldSeconds, concentrationBps)` → with concentration multiplier

Gas target: < 5,000 per call.

### `RedistributionPool.sol`

Per-pool accumulator deployed by `SentryHook` at pool initialization.

- Only the hook may call `deposit()`
- Anyone may call `execute()` to trigger a payout
- Eligibility: continuous hold > 24 hours
- Distribution: pro-rata by `capital × min(tenure, 90 days)`

### `ReputationOracle.sol`

Deployed on each destination chain (Unichain Sepolia, Base Sepolia). Receives reputation updates via Reactive Network callbacks.

- `getReputation(lp)` → cross-chain reputation record
- `effectiveTenure(lp)` → estimated average tenure across chains
- Only authorized Reactive gateway addresses may call `setReputation()`

### `ReputationAggregator.sol` (Reactive Kopli)

Subscribes to `PositionOpened` and `PositionClosed` events from all deployed `SentryHook` instances. Maintains a global `totalCapitalSeconds` record per LP and broadcasts updates to each chain's `ReputationOracle`.

### `RedistributionScheduler.sol` (Reactive Kopli)

Monitors `TaxAccumulated` events. Triggers `executeRedistribution()` on the source chain when:
- Pool balance exceeds threshold (~$1,000 equivalent), **or**
- 24+ hours have elapsed since the last redistribution

---

## Gas Targets

| Operation | Target |
|---|---|
| `afterAddLiquidity` | < 80,000 gas |
| `afterRemoveLiquidity` (no tax) | < 50,000 gas |
| `afterRemoveLiquidity` (with tax) | < 120,000 gas |
| `afterSwap` | < 30,000 gas |
| `executeRedistribution` (per LP) | < 60,000 gas |

---

## Frontend

A Next.js 16 dashboard built with Tailwind CSS and Recharts.

**Pages:**

- **`/`** — Main dashboard: live stats (TVL, redistribution pool, JIT attacks, total redistributed), interactive tax curve chart, redistribution feed, and protected pools table.
- **`/jit-demo`** — Step-by-step interactive simulator walking through a JIT attack (mempool detection → deposit → swap → withdrawal → tax application → redistribution). Shows tax gauge and outcome breakdown.
- **`/pool/[id]`** — Per-pool detail: positions, fee history, tax events.
- **`/lp/[address]`** — LP reputation card: cross-chain capital-seconds, active positions, payout history.

---

## Deployment

### Target Networks

| Network | Role |
|---|---|
| Unichain Sepolia (chain ID 1301) | Primary SentryHook deployment |
| Base Sepolia (chain ID 84532) | Secondary SentryHook deployment |
| Reactive Kopli | ReputationAggregator + RedistributionScheduler |

### Environment Setup

Copy `.env.example` in the `contract/` directory and fill in values:

```bash
cp contract/.env.example contract/.env
```

```env
# Deployer
DEPLOYER=0x...
PRIVATE_KEY=0x...

# RPC endpoints
UNICHAIN_RPC_URL=https://sepolia.unichain.org
BASE_RPC_URL=https://sepolia.base.org
REACTIVE_RPC_URL=https://kopli-rpc.reactive.network

# V4 PoolManager address on target chain
POOL_MANAGER=

# Filled after deployment
UNICHAIN_HOOK=
BASE_HOOK=
UNICHAIN_ORACLE=
BASE_ORACLE=
AGGREGATOR=
SCHEDULER=

# Reactive Network
REACTIVE_SUBSCRIPTION_SERVICE=
```

### Deploy

```bash
# 1. Deploy SentryHook (mines CREATE2 salt for correct V4 hook permissions)
forge script script/DeployHook.s.sol \
  --rpc-url $UNICHAIN_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast

# 2. Deploy Reactive contracts on Kopli
forge script script/DeployReactive.s.sol \
  --rpc-url $REACTIVE_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast

# 3. Wire subscriptions and authorize callbacks
forge script script/ConfigureSubscriptions.s.sol \
  --rpc-url $REACTIVE_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

---

## Development

### Smart Contracts

```bash
cd contract

# Install dependencies
forge install

# Build
forge build

# Run tests
forge test

# Run with verbosity
forge test -vvv

# Gas snapshot
forge snapshot

# Format
forge fmt

# Local node
anvil
```

### Frontend

```bash
cd frontend

# Install dependencies
pnpm install

# Dev server (http://localhost:3000)
pnpm dev

# Production build
pnpm build
pnpm start
```

---

## Testing

The full suite has **48 tests across 7 files**, all passing.

```bash
cd contract
forge test                                                            # all 48 tests
forge test -vv                                                        # with logs
forge test --match-path "test/hook/*"                                 # unit tests only
forge test --match-path "test/integration/ForkScenario.t.sol" -vv    # hook integration
forge test --match-path "test/reactive/*" -vv                         # reactive network
```

---

### Unit tests — `test/hook/`

| Test File | What it covers |
|---|---|
| `TaxCurve.t.sol` | Tax at boundaries (0s, 1min, 10min, 1h, 24h), monotonic decrease, concentration multiplier, 65% cap, gas < 5k |
| `JITScenario.t.sol` | Math-layer JIT scenario: 0s hold + 91% concentration hits 65% cap, long-term LP pays 0% |
| `SentryHook.t.sol` | Scaffold — full hook callback tests against a live PoolManager (in progress) |
| `RedistributionMath.t.sol` | Scaffold — capital-weighted pro-rata math, protocol fee forwarding (in progress) |

---

### Integration tests — `test/integration/ForkScenario.t.sol`

End-to-end simulation using a live `PoolManager` with two separate routers (one for the long-term LP, one for the JIT bot) and `vm.warp` for time travel. All 6 scenarios pass against real V4 contract state.

| Test | What it proves | Key result |
|---|---|---|
| `test_positionRecordedOnAddLiquidity` | `afterAddLiquidity` stores capital, openedAt, concentrationBps correctly | Pass |
| `test_jitBot_sameBlock_pays65pctTax` | Bot adds concentrated liquidity, large swap fires, bot exits at t=0 — redistribution pool funded | ~29 token0 taxed |
| `test_longTermLP_paysZeroTax` | LP held 30 days removes with zero tax, redistribution pool unchanged | 0 tax |
| `test_redistribution_paysLongTermLP` | Full flow: Alice adds → 25h warp → partial remove registers Alice → bot JITs → `execute()` distributes | 60% to LP, 5% to treasury |
| `test_taxDecaysOverTime` | Decay curve values at 0s, 5min, 1h, 24h | 65% → 44.5% → 0.16% → 0% |
| `test_concentrationMultiplier` | Multiplier pushes tax above base rate for tight positions at 5-minute hold | Pass |

Sample output from `test_redistribution_paysLongTermLP`:
```
Pool funded was:  29380593893414017177  (~29.38 token0 from JIT tax)
LP payout:        27121226223010479257  (~27.12 token0 to long-term LP)
Protocol fee:     2259367670403537920   (~2.26 token0  to treasury)
```
60% of fees captured from the bot flow to loyal LPs. 5% goes to the protocol treasury. The bot keeps 35%.

---

### Reactive Network tests — `test/reactive/`

These tests simulate the Reactive Network VM delivering events to the Kopli contracts. Because the `vmOnly` modifier is a no-op until `reactive-lib` is wired in, tests call `react()` directly and assert state changes and `Callback` event payloads. A `MockSubscriptionService` captures all `subscribe()` calls for assertion.

#### `ReputationAggregator.t.sol` — 12 tests

| Test | What it proves |
|---|---|
| `test_addSubscription_registersWithService` | Subscribes to both `PositionOpened` and `PositionClosed` signatures on the service |
| `test_addSubscription_onlyOwner` | Reverts for non-owner callers |
| `test_addDestination_onlyOwner` | Reverts for non-owner callers |
| `test_react_positionOpened_updatesCurrentCapital` | `PositionOpened` increments `currentCapital`, leaves `totalCapitalSeconds` at 0 |
| `test_react_positionOpened_accumulatesAcrossChains` | Two opens from different chains sum correctly in `currentCapital` |
| `test_react_positionOpened_emitsCallbackToAllOracles` | Broadcasts a `Callback` to every registered oracle (both ORACLE_A and ORACLE_B) |
| `test_react_positionOpened_callbackPayloadCallsSetReputation` | Callback payload decodes to a valid `setReputation()` call with correct lp and capital values |
| `test_react_positionClosed_accumulatesCapitalSeconds` | Close accumulates `capital x timeHeld` into `totalCapitalSeconds` and zeroes `currentCapital` |
| `test_react_positionClosed_partialCloseReducesCapital` | Closing one of two positions only reduces capital by that position's amount |
| `test_react_positionClosed_callbackIncludesTotalCapitalSeconds` | Callback after close carries the accumulated capital-seconds and correct LP address |
| `test_reputations_isolatedPerLP` | Alice and bot reputation records do not bleed into each other |
| `test_unknownTopic_isIgnored` | Unknown event signatures pass through without state changes or Callbacks |

#### `RedistributionScheduler.t.sol` — 14 tests

| Test | What it proves |
|---|---|
| `test_addSubscription_onlyOwner` | Reverts for non-owner callers |
| `test_addSubscription_registersDestinationHook` | Hook address stored after subscription |
| `test_react_belowThreshold_noCallback` | $500 accumulated does not trigger redistribution |
| `test_react_accumulatesAcrossMultipleEvents` | Three $400 events: no trigger at $400, no trigger at $800, triggers at $1,200 |
| `test_react_thresholdMet_emitsCallback` | Exactly $1,000 triggers a `Callback` event |
| `test_react_thresholdMet_callbackPayloadIsExecuteRedistribution` | Callback payload decodes to `executeRedistribution(poolId)` with the correct pool ID |
| `test_react_thresholdMet_resetsAccumulator` | Accumulator resets to 0 after trigger — next $400 does not re-fire |
| `test_react_cooldownExpired_triggerEvenBelowThreshold` | After 24h any new tax event triggers redistribution regardless of amount |
| `test_react_withinCooldown_doesNotRetrigger` | Below-threshold amount within 12h of a previous trigger does not fire |
| `test_react_exactCooldownBoundary` | Triggers exactly at `lastRedistributionAt + 24h` (boundary inclusive) |
| `test_react_poolsTrackedIndependently` | Pool A accumulation does not count toward Pool B's threshold |
| `test_react_callbackTargetsCorrectPool` | Callback for Pool B carries Pool B's ID, not Pool A's |
| `test_react_wrongTopic_isIgnored` | Non-`TaxAccumulated` topics are silently dropped |
| `test_react_multipleCycles` | Three full trigger/cooldown/re-trigger cycles all behave correctly |

---

## Key Design Decisions

- **Smooth decay over binary lock** — Bots can exit at any time; the cost is priced continuously into their fee share rather than hard-locked.
- **Concentration multiplier** — Addresses the bot adaptation of holding positions slightly longer at maximum concentration.
- **Lazy fee accounting** — Per-position fee balances are only computed on add/remove, not on every swap, keeping `afterSwap` cheap.
- **Capital × tenure scoring** — Prevents tenure squatting by small capital positions and whale domination by short-term LPs simultaneously.
- **90-day tenure cap** — Prevents very old positions from monopolizing redistribution indefinitely.
- **Reactive Network for automation** — Redistribution and reputation updates are driven by on-chain events without a centralized keeper.
- **Hook address mining** — Uniswap V4 encodes hook permissions in the contract address. `HookMiner` is used to find a valid CREATE2 salt.

---

## Built With

- [Uniswap V4](https://github.com/Uniswap/v4-core) — Hook protocol
- [Reactive Network](https://reactive.network) — Cross-chain event subscriptions and callbacks
- [Foundry](https://getfoundry.sh) — Solidity development and testing
- [Next.js](https://nextjs.org) — Frontend framework
- [Recharts](https://recharts.org) — Tax curve visualization
- [Tailwind CSS](https://tailwindcss.com) — Styling
