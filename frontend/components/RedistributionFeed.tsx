import { RedistributionEvent, formatUSD, timeAgo } from "@/lib/data";

interface RedistributionFeedProps {
  events: RedistributionEvent[];
}

export default function RedistributionFeed({ events }: RedistributionFeedProps) {
  return (
    <div className="space-y-2">
      {events.map((ev) => (
        <div
          key={ev.id}
          className="flex items-center justify-between p-3 rounded-lg bg-[#ffffff03] border border-[#1e1e30] hover:border-[#2a2a40] transition-colors"
        >
          <div className="flex items-center gap-3">
            <div className="w-7 h-7 rounded-full bg-green-500/15 flex items-center justify-center text-green-400 text-xs font-bold shrink-0">
              ↑
            </div>
            <div>
              <p className="text-sm text-[#ccc] font-medium">{ev.pool}</p>
              <p className="text-xs text-[#555]">
                {ev.lpCount} LPs · {timeAgo(ev.timestamp)}
              </p>
            </div>
          </div>
          <div className="text-right">
            <p className="text-sm font-mono font-semibold text-green-400">
              +{formatUSD(ev.totalPaid)}
            </p>
            <p className="text-xs text-[#555] font-mono">
              {formatUSD(ev.protocolFee)} fee
            </p>
          </div>
        </div>
      ))}
    </div>
  );
}
