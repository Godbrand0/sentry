// Mock data — replace with live contract reads via viem/wagmi post-deployment

export type Tier = "jit" | "short" | "medium" | "long";

export function getTier(timeHeldSeconds: number): Tier {
  if (timeHeldSeconds < 60) return "jit";
  if (timeHeldSeconds < 3600) return "short";
  if (timeHeldSeconds < 86400) return "medium";
  return "long";
}

export const TIER_LABELS: Record<Tier, string> = {
  jit: "JIT",
  short: "Short",
  medium: "Medium",
  long: "Long-term",
};

export const TIER_COLORS: Record<Tier, string> = {
  jit: "#ef4444",
  short: "#f97316",
  medium: "#eab308",
  long: "#22c55e",
};

export const TIER_BG: Record<Tier, string> = {
  jit: "bg-red-500/10 text-red-400 border-red-500/20",
  short: "bg-orange-500/10 text-orange-400 border-orange-500/20",
  medium: "bg-yellow-500/10 text-yellow-400 border-yellow-500/20",
  long: "bg-green-500/10 text-green-400 border-green-500/20",
};

export interface Pool {
  id: string;
  name: string;
  token0: string;
  token1: string;
  tvl: number;
  fees24h: number;
  redistributionPool: number;
  lastRedistribution: number; // timestamp
  activePositions: number;
  jitAttacks24h: number;
}

export interface Position {
  key: string;
  lp: string;
  pool: string;
  capital: number;
  openedAt: number; // timestamp
  timeHeld: number; // seconds
  feesEarned: number;
  concentrationBps: number;
  chain: string;
}

export interface RedistributionEvent {
  id: string;
  pool: string;
  totalPaid: number;
  protocolFee: number;
  lpCount: number;
  timestamp: number;
  txHash: string;
}

export interface LPReputation {
  address: string;
  totalCapitalSeconds: bigint;
  currentCapital: number;
  lastUpdate: number;
  chains: string[];
  globalTenureDays: number;
}

// ── Mock pools ──────────────────────────────────────────────────────────────

export const MOCK_POOLS: Pool[] = [
  {
    id: "0xeth-usdc",
    name: "ETH / USDC",
    token0: "ETH",
    token1: "USDC",
    tvl: 12_400_000,
    fees24h: 18_600,
    redistributionPool: 4_231,
    lastRedistribution: Date.now() / 1000 - 3600 * 6,
    activePositions: 47,
    jitAttacks24h: 12,
  },
  {
    id: "0xbtc-eth",
    name: "WBTC / ETH",
    token0: "WBTC",
    token1: "ETH",
    tvl: 8_100_000,
    fees24h: 9_300,
    redistributionPool: 2_108,
    lastRedistribution: Date.now() / 1000 - 3600 * 14,
    activePositions: 31,
    jitAttacks24h: 7,
  },
  {
    id: "0xusdc-usdt",
    name: "USDC / USDT",
    token0: "USDC",
    token1: "USDT",
    tvl: 34_000_000,
    fees24h: 6_800,
    redistributionPool: 890,
    lastRedistribution: Date.now() / 1000 - 3600 * 2,
    activePositions: 89,
    jitAttacks24h: 3,
  },
];

// ── Mock positions ──────────────────────────────────────────────────────────

const now = Date.now() / 1000;

export const MOCK_POSITIONS: Position[] = [
  {
    key: "0xpos1",
    lp: "0xAisha...3f4a",
    pool: "ETH / USDC",
    capital: 50_000,
    openedAt: now - 86400 * 30,
    timeHeld: 86400 * 30,
    feesEarned: 1_240,
    concentrationBps: 820,
    chain: "Unichain",
  },
  {
    key: "0xpos2",
    lp: "0xVega...91cc",
    pool: "ETH / USDC",
    capital: 200_000,
    openedAt: now - 2700,
    timeHeld: 2700,
    feesEarned: 480,
    concentrationBps: 2100,
    chain: "Unichain",
  },
  {
    key: "0xpos3",
    lp: "0xBot...dead",
    pool: "ETH / USDC",
    capital: 5_000_000,
    openedAt: now - 4,
    timeHeld: 4,
    feesEarned: 2_475,
    concentrationBps: 9100,
    chain: "Unichain",
  },
  {
    key: "0xpos4",
    lp: "0xMike...7b3e",
    pool: "WBTC / ETH",
    capital: 120_000,
    openedAt: now - 86400 * 7,
    timeHeld: 86400 * 7,
    feesEarned: 640,
    concentrationBps: 1500,
    chain: "Base",
  },
  {
    key: "0xpos5",
    lp: "0xSara...4d12",
    pool: "USDC / USDT",
    capital: 800_000,
    openedAt: now - 86400 * 45,
    timeHeld: 86400 * 45,
    feesEarned: 3_100,
    concentrationBps: 450,
    chain: "Unichain",
  },
  {
    key: "0xpos6",
    lp: "0xBot2...feed",
    pool: "WBTC / ETH",
    capital: 2_000_000,
    openedAt: now - 12,
    timeHeld: 12,
    feesEarned: 1_830,
    concentrationBps: 8800,
    chain: "Base",
  },
];

// ── Mock redistribution events ───────────────────────────────────────────────

export const MOCK_REDISTRIBUTIONS: RedistributionEvent[] = [
  {
    id: "r1",
    pool: "ETH / USDC",
    totalPaid: 2_163,
    protocolFee: 114,
    lpCount: 12,
    timestamp: now - 3600 * 6,
    txHash: "0xabc...def",
  },
  {
    id: "r2",
    pool: "WBTC / ETH",
    totalPaid: 1_045,
    protocolFee: 55,
    lpCount: 8,
    timestamp: now - 3600 * 14,
    txHash: "0x123...456",
  },
  {
    id: "r3",
    pool: "USDC / USDT",
    totalPaid: 320,
    protocolFee: 17,
    lpCount: 22,
    timestamp: now - 3600 * 2,
    txHash: "0x789...abc",
  },
  {
    id: "r4",
    pool: "ETH / USDC",
    totalPaid: 4_800,
    protocolFee: 253,
    lpCount: 15,
    timestamp: now - 3600 * 30,
    txHash: "0xfed...cba",
  },
];

// ── Mock LP reputation ────────────────────────────────────────────────────────

export const MOCK_LP_REPUTATION: Record<string, LPReputation> = {
  "0xAisha": {
    address: "0xAisha...3f4a",
    totalCapitalSeconds: BigInt(50_000) * BigInt(86400 * 180),
    currentCapital: 50_000,
    lastUpdate: now - 600,
    chains: ["Ethereum", "Unichain", "Base"],
    globalTenureDays: 180,
  },
  "0xVega": {
    address: "0xVega...91cc",
    totalCapitalSeconds: BigInt(200_000) * BigInt(86400 * 14),
    currentCapital: 200_000,
    lastUpdate: now - 2700,
    chains: ["Unichain"],
    globalTenureDays: 14,
  },
  "0xNew": {
    address: "0xNew...0000",
    totalCapitalSeconds: BigInt(0),
    currentCapital: 0,
    lastUpdate: 0,
    chains: [],
    globalTenureDays: 0,
  },
};

// ── Helper formatters ─────────────────────────────────────────────────────────

export function formatUSD(n: number): string {
  if (n >= 1_000_000) return `$${(n / 1_000_000).toFixed(2)}M`;
  if (n >= 1_000) return `$${(n / 1_000).toFixed(1)}K`;
  return `$${n.toFixed(0)}`;
}

export function formatDuration(seconds: number): string {
  if (seconds < 60) return `${Math.floor(seconds)}s`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m`;
  if (seconds < 86400) return `${(seconds / 3600).toFixed(1)}h`;
  return `${(seconds / 86400).toFixed(1)}d`;
}

export function timeAgo(timestamp: number): string {
  const diff = Date.now() / 1000 - timestamp;
  if (diff < 60) return `${Math.floor(diff)}s ago`;
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
  return `${Math.floor(diff / 86400)}d ago`;
}

export function truncateAddress(addr: string): string {
  if (addr.length <= 13) return addr;
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}
