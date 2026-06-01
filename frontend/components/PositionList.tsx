import { Position, getTier, TIER_LABELS, TIER_BG, formatUSD, formatDuration, truncateAddress } from "@/lib/data";
import { taxPercent } from "@/lib/taxCurve";

interface PositionListProps {
  positions: Position[];
  showPool?: boolean;
}

export default function PositionList({ positions, showPool = true }: PositionListProps) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="text-[#555] text-xs uppercase tracking-wider border-b border-[#1e1e30]">
            <th className="text-left pb-2 pr-4">LP</th>
            {showPool && <th className="text-left pb-2 pr-4">Pool</th>}
            <th className="text-left pb-2 pr-4">Chain</th>
            <th className="text-right pb-2 pr-4">Capital</th>
            <th className="text-right pb-2 pr-4">Held</th>
            <th className="text-left pb-2 pr-4">Tier</th>
            <th className="text-right pb-2 pr-4">Tax</th>
            <th className="text-right pb-2">Fees Earned</th>
          </tr>
        </thead>
        <tbody>
          {positions.map((pos) => {
            const tier = getTier(pos.timeHeld);
            const tax = taxPercent(pos.timeHeld, pos.concentrationBps);
            const netFees = pos.feesEarned * (1 - tax / 100);

            return (
              <tr
                key={pos.key}
                className="border-b border-[#13131f] hover:bg-[#ffffff04] transition-colors"
              >
                <td className="py-3 pr-4 font-mono text-xs text-[#aaa]">
                  {truncateAddress(pos.lp)}
                </td>
                {showPool && (
                  <td className="py-3 pr-4 text-[#ccc]">{pos.pool}</td>
                )}
                <td className="py-3 pr-4">
                  <span className="text-xs px-1.5 py-0.5 rounded bg-[#ffffff08] text-[#888] border border-[#ffffff0a]">
                    {pos.chain}
                  </span>
                </td>
                <td className="py-3 pr-4 text-right font-mono text-[#ddd]">
                  {formatUSD(pos.capital)}
                </td>
                <td className="py-3 pr-4 text-right font-mono text-[#aaa]">
                  {formatDuration(pos.timeHeld)}
                </td>
                <td className="py-3 pr-4">
                  <span className={`text-xs px-2 py-0.5 rounded border font-medium ${TIER_BG[tier]}`}>
                    {TIER_LABELS[tier]}
                  </span>
                </td>
                <td className="py-3 pr-4 text-right font-mono">
                  {tax > 0 ? (
                    <span className="text-red-400">{tax.toFixed(1)}%</span>
                  ) : (
                    <span className="text-green-400">0%</span>
                  )}
                </td>
                <td className="py-3 text-right">
                  <div className="flex flex-col items-end gap-0.5">
                    <span className="font-mono text-[#ddd]">{formatUSD(pos.feesEarned)}</span>
                    {tax > 0 && (
                      <span className="font-mono text-xs text-green-500">
                        {formatUSD(netFees)} net
                      </span>
                    )}
                  </div>
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
