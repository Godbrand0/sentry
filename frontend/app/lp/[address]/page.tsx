import { notFound } from "next/navigation";
import Link from "next/link";
import ReputationBadge from "@/components/ReputationBadge";
import PositionList from "@/components/PositionList";
import {
  MOCK_LP_REPUTATION,
  MOCK_POSITIONS,
  formatUSD,
  timeAgo,
} from "@/lib/data";
import { taxPercent as calcTax } from "@/lib/taxCurve";

export function generateStaticParams() {
  return Object.keys(MOCK_LP_REPUTATION).map((addr) => ({ address: addr }));
}

export default async function LPPage({ params }: { params: Promise<{ address: string }> }) {
  const { address } = await params;
  const rep = MOCK_LP_REPUTATION[address];
  if (!rep) notFound();

  const positions = MOCK_POSITIONS.filter((p) => p.lp.startsWith(address.slice(0, 6)));
  const totalFees = positions.reduce((s, p) => s + p.feesEarned, 0);
  const totalTax = positions.reduce((s, p) => s + p.feesEarned * (calcTax(p.timeHeld, p.concentrationBps) / 100), 0);
  const netFees = totalFees - totalTax;

  const crossChainBoost = rep.globalTenureDays >= 1;

  return (
    <div className="space-y-6">
      {/* Breadcrumb */}
      <div className="flex items-center gap-2 text-sm text-[#555]">
        <Link href="/" className="hover:text-[#888] transition-colors">Dashboard</Link>
        <span>/</span>
        <span className="text-[#aaa] font-mono">{rep.address}</span>
      </div>

      <div className="grid md:grid-cols-3 gap-6">
        {/* Left: identity */}
        <div className="space-y-4">
          <div className="bg-[#14141e] border border-[#1e1e2e] rounded-xl p-5">
            <div className="flex items-center gap-3 mb-4">
              <div className="w-10 h-10 rounded-full bg-linear-to-br from-violet-500 to-indigo-600 flex items-center justify-center text-white font-bold">
                {address.slice(2, 4).toUpperCase()}
              </div>
              <div>
                <p className="font-mono text-sm text-[#ddd]">{rep.address}</p>
                <p className="text-xs text-[#555]">
                  {rep.lastUpdate > 0 ? `Updated ${timeAgo(rep.lastUpdate)}` : "No history yet"}
                </p>
              </div>
            </div>
            <ReputationBadge reputation={rep} />
          </div>

          {/* Cross-chain boost indicator */}
          {crossChainBoost && (
            <div className="bg-violet-500/5 border border-violet-500/20 rounded-xl p-4">
              <p className="text-xs font-semibold text-violet-400 mb-1">
                ◆ Cross-chain reputation active
              </p>
              <p className="text-xs text-[#888]">
                {rep.globalTenureDays} days of global tenure recognized via Reactive Network.
                Tax rate on new chains starts lower.
              </p>
              <div className="mt-3 grid grid-cols-2 gap-2 text-xs">
                <div className="bg-[#ffffff04] rounded-lg p-2">
                  <p className="text-[#555]">Without history</p>
                  <p className="font-mono text-red-400 font-semibold mt-0.5">~30% tax</p>
                  <p className="text-[#555]">at 30min</p>
                </div>
                <div className="bg-[#ffffff04] rounded-lg p-2">
                  <p className="text-[#555]">With your history</p>
                  <p className="font-mono text-green-400 font-semibold mt-0.5">~0% tax</p>
                  <p className="text-[#555]">at 30min</p>
                </div>
              </div>
            </div>
          )}

          {/* Chain presence */}
          <div className="bg-[#14141e] border border-[#1e1e2e] rounded-xl p-4">
            <p className="text-xs text-[#555] uppercase tracking-wider mb-3">Active on</p>
            <div className="flex flex-wrap gap-2">
              {rep.chains.length > 0 ? (
                rep.chains.map((chain) => (
                  <span key={chain} className="px-2 py-1 bg-[#ffffff06] border border-[#1e1e2e] rounded text-xs text-[#aaa]">
                    {chain}
                  </span>
                ))
              ) : (
                <span className="text-xs text-[#555]">No chain activity yet</span>
              )}
            </div>
            <p className="text-xs text-[#555] mt-3">
              Reputation powered by Reactive Network — no bridges, no keepers.
            </p>
          </div>
        </div>

        {/* Right: earnings */}
        <div className="md:col-span-2 space-y-4">
          {/* Earnings summary */}
          <div className="grid grid-cols-3 gap-3">
            <div className="bg-[#14141e] border border-[#1e1e2e] rounded-xl p-4">
              <p className="text-xs text-[#555] mb-1">Gross Fees</p>
              <p className="text-xl font-mono font-bold text-white">{formatUSD(totalFees)}</p>
            </div>
            <div className="bg-[#14141e] border border-[#1e1e2e] rounded-xl p-4">
              <p className="text-xs text-[#555] mb-1">Tax Paid</p>
              <p className="text-xl font-mono font-bold text-red-400">{formatUSD(totalTax)}</p>
            </div>
            <div className="bg-[#14141e] border border-[#1e1e2e] rounded-xl p-4">
              <p className="text-xs text-[#555] mb-1">Net Fees</p>
              <p className="text-xl font-mono font-bold text-green-400">{formatUSD(netFees)}</p>
            </div>
          </div>

          {/* Redistribution receipts */}
          <div className="bg-[#14141e] border border-[#1e1e2e] rounded-xl p-5">
            <h2 className="font-semibold text-[#ddd] mb-3">Redistribution Receipts</h2>
            {rep.globalTenureDays >= 1 ? (
              <div className="space-y-3">
                {[
                  { pool: "ETH / USDC", amount: 180, date: Date.now() / 1000 - 3600 * 6 },
                  { pool: "ETH / USDC", amount: 412, date: Date.now() / 1000 - 3600 * 30 },
                ].map((r, i) => (
                  <div key={i} className="flex items-center justify-between p-3 bg-[#ffffff03] border border-[#1a1a28] rounded-lg">
                    <div>
                      <p className="text-sm text-[#ccc]">{r.pool}</p>
                      <p className="text-xs text-[#555] mt-0.5">{timeAgo(r.date)}</p>
                    </div>
                    <p className="font-mono font-semibold text-green-400">+{formatUSD(r.amount)}</p>
                  </div>
                ))}
              </div>
            ) : (
              <p className="text-sm text-[#555]">
                Hold a position for 24h+ to become eligible for redistribution payouts.
              </p>
            )}
          </div>

          {/* Positions */}
          <div className="bg-[#14141e] border border-[#1e1e2e] rounded-xl overflow-hidden">
            <div className="px-5 py-4 border-b border-[#1e1e2e]">
              <h2 className="font-semibold text-[#ddd]">Positions</h2>
            </div>
            <div className="px-5 py-4">
              {positions.length > 0 ? (
                <PositionList positions={positions} />
              ) : (
                <p className="text-sm text-[#555] py-4 text-center">No open positions.</p>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
