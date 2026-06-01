import { notFound } from "next/navigation";
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

export function generateStaticParams() {
  return MOCK_POOLS.map((p) => ({ id: p.id }));
}

export default async function PoolPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const pool = MOCK_POOLS.find((p) => p.id === id);
  if (!pool) notFound();

  const positions = MOCK_POSITIONS.filter((pos) => pos.pool === pool.name);
  const redistributions = MOCK_REDISTRIBUTIONS.filter((r) => r.pool === pool.name);

  const jitCaptures = positions.filter((p) => p.timeHeld < 60);
  const capturedFees = jitCaptures.reduce((s, p) => s + p.feesEarned * 0.9, 0);

  return (
    <div className="space-y-6">
      {/* Breadcrumb */}
      <div className="flex items-center gap-2 text-sm text-[#555]">
        <Link href="/" className="hover:text-[#888] transition-colors">Dashboard</Link>
        <span>/</span>
        <span className="text-[#aaa]">{pool.name}</span>
      </div>

      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-white">{pool.name}</h1>
          <p className="text-sm text-[#555] mt-1">Unichain Sepolia · Sentry hook enabled</p>
        </div>
        <div className="flex gap-2 text-xs">
          <span className="px-2.5 py-1.5 bg-[#14141e] border border-[#1e1e2e] rounded-lg text-[#888]">
            {pool.token0} / {pool.token1}
          </span>
          <span className="px-2.5 py-1.5 bg-green-500/10 border border-green-500/20 rounded-lg text-green-400">
            {pool.activePositions} positions
          </span>
        </div>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        {[
          { label: "TVL", value: formatUSD(pool.tvl) },
          { label: "24h Fees", value: formatUSD(pool.fees24h) },
          { label: "Redistribution Pool", value: formatUSD(pool.redistributionPool), accent: "text-green-400" },
          { label: "JIT Attacks 24h", value: String(pool.jitAttacks24h), accent: "text-red-400" },
        ].map((s) => (
          <div key={s.label} className="bg-[#14141e] border border-[#1e1e2e] rounded-xl p-4">
            <p className="text-xs text-[#555] uppercase tracking-wider mb-1">{s.label}</p>
            <p className={`text-xl font-mono font-bold ${s.accent ?? "text-white"}`}>{s.value}</p>
          </div>
        ))}
      </div>

      {/* JIT capture banner */}
      {jitCaptures.length > 0 && (
        <div className="bg-red-500/5 border border-red-500/20 rounded-xl p-4">
          <div className="flex items-start gap-3">
            <span className="text-red-400 text-lg mt-0.5">⚡</span>
            <div>
              <p className="text-sm font-semibold text-red-300">
                {jitCaptures.length} JIT attack{jitCaptures.length > 1 ? "s" : ""} detected
              </p>
              <p className="text-xs text-[#888] mt-1">
                Sentry captured <span className="text-green-400 font-mono">{formatUSD(capturedFees)}</span> in fees
                that would have been extracted. Redistributing to long-term LPs.
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Chart + feed */}
      <div className="grid md:grid-cols-3 gap-6">
        <div className="md:col-span-2 bg-[#14141e] border border-[#1e1e2e] rounded-xl p-5">
          <h2 className="font-semibold text-[#ddd] mb-4">Tax Curve</h2>
          <TaxCurveChart height={200} />
        </div>

        <div className="bg-[#14141e] border border-[#1e1e2e] rounded-xl p-5">
          <h2 className="font-semibold text-[#ddd] mb-1">Redistributions</h2>
          <p className="text-xs text-[#555] mb-4">
            Last payout {timeAgo(pool.lastRedistribution)}
          </p>
          {redistributions.length > 0 ? (
            <RedistributionFeed events={redistributions} />
          ) : (
            <p className="text-sm text-[#555]">No redistributions yet for this pool.</p>
          )}
        </div>
      </div>

      {/* Positions */}
      <div className="bg-[#14141e] border border-[#1e1e2e] rounded-xl overflow-hidden">
        <div className="px-5 py-4 border-b border-[#1e1e2e]">
          <h2 className="font-semibold text-[#ddd]">Positions</h2>
        </div>
        <div className="px-5 py-4">
          {positions.length > 0 ? (
            <PositionList positions={positions} showPool={false} />
          ) : (
            <p className="text-sm text-[#555] py-4 text-center">No positions in this pool yet.</p>
          )}
        </div>
      </div>
    </div>
  );
}
