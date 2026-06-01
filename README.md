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
│   │   ├── hook/JITScenario.t.sol        # Headline integration test
│   │   └── hook/RedistributionMath.t.sol
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

| Test File | Coverage |
|---|---|
| `TaxCurve.t.sol` | Tax at boundaries (0s, 10m, 1h, 24h), monotonic decrease, gas benchmark |
| `SentryHook.t.sol` | Position recording, tax calculation, fee accumulation, concentration multiplier, partial withdrawal |
| `JITScenario.t.sol` | End-to-end: simulate JIT bot, verify ~90% tax applied, verify redistribution pool funded |
| `RedistributionMath.t.sol` | Capital-weighted pro-rata math, protocol fee forwarding |

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
