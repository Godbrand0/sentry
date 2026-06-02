import Link from "next/link";
import TaxCurveChart from "@/components/TaxCurveChart";
import PositionList from "@/components/PositionList";
import RedistributionFeed from "@/components/RedistributionFeed";
import {
  MOCK_POOLS,
  MOCK_POSITIONS,
  MOCK_REDISTRIBUTIONS,
  formatUSD,
  timeAgo,
} from "@/lib/data";

function StatCard({ label, value, sub, accent }: { label: string; value: string; sub?: string; accent?: string }) {
  return (
    <div className="bg-[#14141e] border border-[#1e1e2e] rounded-xl p-4">
      <p className="text-xs text-[#555] uppercase tracking-wider mb-1">{label}</p>
      <p className={`text-2xl font-mono font-bold ${accent ?? "text-white"}`}>{value}</p>
      {sub && <p className="text-xs text-[#555] mt-1">{sub}</p>}
    </div>
  );
}

function PoolRow({ pool }: { pool: (typeof MOCK_POOLS)[0] }) {
  const utilizationPct = ((pool.redistributionPool / pool.fees24h) * 100).toFixed(1);
  return (
    <Link
      href={`/pool/${pool.id}`}
      className="flex items-center gap-4 p-4 border-b border-[#13131f] hover:bg-[#ffffff03] transition-colors group"
    >
      <div className="flex-1 min-w-0">
        <p className="font-medium text-[#ddd] group-hover:text-white transition-colors">
          {pool.name}
        </p>
        <p className="text-xs text-[#555] mt-0.5">{pool.activePositions} active positions</p>
      </div>
      <div className="text-right hidden sm:block">
        <p className="text-sm font-mono text-[#aaa]">{formatUSD(pool.tvl)}</p>
        <p className="text-xs text-[#555]">TVL</p>
      </div>
      <div className="text-right hidden md:block">
        <p className="text-sm font-mono text-[#aaa]">{formatUSD(pool.fees24h)}</p>
        <p className="text-xs text-[#555]">24h fees</p>
      </div>
      <div className="text-right">
        <p className="text-sm font-mono text-green-400">{formatUSD(pool.redistributionPool)}</p>
        <p className="text-xs text-[#555]">redistribution pool</p>
      </div>
      <div className="text-right hidden lg:block">
        <p className="text-sm font-mono text-red-400">{pool.jitAttacks24h}</p>
        <p className="text-xs text-[#555]">JIT attacks 24h</p>
      </div>
      <div className="text-right hidden lg:block w-20">
        <p className="text-xs text-[#555] mb-1">last payout</p>
        <p className="text-xs text-[#888]">{timeAgo(pool.lastRedistribution)}</p>
      </div>
      <span className="text-[#444] group-hover:text-[#888] transition-colors">→</span>
    </Link>
  );
}

export default function DashboardPage() {
  const totalTVL = MOCK_POOLS.reduce((s, p) => s + p.tvl, 0);
  const totalRedist = MOCK_POOLS.reduce((s, p) => s + p.redistributionPool, 0);
  const totalJIT = MOCK_POOLS.reduce((s, p) => s + p.jitAttacks24h, 0);
  const totalRedistPaid = MOCK_REDISTRIBUTIONS.reduce((s, r) => s + r.totalPaid, 0);

  return (
    <div className="space-y-8">
      {/* Hero */}
      <div className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-[#12102a] to-[#0a0a0e] border border-[#2a2040] p-6 md:p-8">
        <div className="absolute inset-0 bg-gradient-to-r from-violet-900/20 to-transparent pointer-events-none" />
        <div className="relative">
          <div className="flex items-start justify-between gap-4 mb-4">
            <div>
              <h1 className="text-2xl md:text-3xl font-bold text-white mb-2">
                JIT-proof liquidity.
              </h1>
              <p className="text-[#888] text-sm md:text-base max-w-xl">
                Sentry taxes short-lived positions and redistributes captured fees to long-term LPs.
                <span className="text-violet-400"> 36,671 JIT attacks</span> documented. 85% fee dilution. Fixed.
              </p>
            </div>
            <Link
              href="/jit-demo"
              className="shrink-0 bg-violet-600 hover:bg-violet-500 text-white text-sm font-medium px-4 py-2 rounded-lg transition-colors"
            >
              See live demo →
            </Link>
          </div>

          {/* Tier legend */}
          <div className="flex flex-wrap gap-3 mt-4">
            {[
              { label: "JIT  < 1min", color: "text-red-400", dot: "bg-red-400" },
              { label: "Short  1–60min", color: "text-orange-400", dot: "bg-orange-400" },
              { label: "Medium  1–24h", color: "text-yellow-400", dot: "bg-yellow-400" },
              { label: "Long-term  > 24h", color: "text-green-400", dot: "bg-green-400" },
            ].map((t) => (
              <div key={t.label} className="flex items-center gap-1.5 text-xs">
                <span className={`w-2 h-2 rounded-full ${t.dot}`} />
                <span className={t.color}>{t.label}</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <StatCard label="Total TVL" value={formatUSD(totalTVL)} sub="across 3 pools" />
        <StatCard
          label="Redistribution pool"
          value={formatUSD(totalRedist)}
          sub="pending payout"
          accent="text-green-400"
        />
        <StatCard
          label="JIT attacks (24h)"
          value={String(totalJIT)}
          sub="captured by Sentry"
          accent="text-red-400"
        />
        <StatCard
          label="Total redistributed"
          value={formatUSD(totalRedistPaid)}
          sub="to long-term LPs"
          accent="text-violet-400"
        />
      </div>

      {/* Tax curve + feed */}
      <div className="grid md:grid-cols-3 gap-6">
        <div className="md:col-span-2 bg-[#14141e] border border-[#1e1e2e] rounded-xl p-5">
          <div className="flex items-center justify-between mb-4">
            <h2 className="font-semibold text-[#ddd]">Tax Curve</h2>
            <p className="text-xs text-[#555]">tax_rate = 65% × exp(−t / 10min)</p>
          </div>
          <TaxCurveChart height={220} />
          <div className="grid grid-cols-4 gap-2 mt-4">
            {[
              { t: "0s", tax: "65%", label: "Same block" },
              { t: "5m", tax: "~34%", label: "5 minutes" },
              { t: "30m", tax: "~8%", label: "30 minutes" },
              { t: "24h", tax: "0%", label: "Long-term" },
            ].map((item) => (
              <div key={item.t} className="text-center bg-[#ffffff04] rounded-lg p-2">
                <p className="text-xs text-[#555]">{item.t}</p>
                <p className="font-mono font-bold text-sm text-[#ddd]">{item.tax}</p>
                <p className="text-xs text-[#444]">{item.label}</p>
              </div>
            ))}
          </div>
        </div>

        <div className="bg-[#14141e] border border-[#1e1e2e] rounded-xl p-5">
          <h2 className="font-semibold text-[#ddd] mb-4">Redistribution Feed</h2>
          <RedistributionFeed events={MOCK_REDISTRIBUTIONS} />
        </div>
      </div>

      {/* Pools */}
      <div className="bg-[#14141e] border border-[#1e1e2e] rounded-xl overflow-hidden">
        <div className="px-5 py-4 border-b border-[#1e1e2e]">
          <h2 className="font-semibold text-[#ddd]">Protected Pools</h2>
        </div>
        <div>
          {MOCK_POOLS.map((pool) => (
            <PoolRow key={pool.id} pool={pool} />
          ))}
        </div>
      </div>

      {/* Recent positions */}
      <div className="bg-[#14141e] border border-[#1e1e2e] rounded-xl overflow-hidden">
        <div className="px-5 py-4 border-b border-[#1e1e2e] flex items-center justify-between">
          <h2 className="font-semibold text-[#ddd]">Active Positions</h2>
          <span className="text-xs text-[#555]">Sorted by capital</span>
        </div>
        <div className="px-5 py-4">
          <PositionList positions={MOCK_POSITIONS} />
        </div>
      </div>
    </div>
  );
}
