import { LPReputation } from "@/lib/data";

interface ReputationBadgeProps {
  reputation: LPReputation;
  compact?: boolean;
}

export default function ReputationBadge({ reputation, compact = false }: ReputationBadgeProps) {
  const { globalTenureDays, chains, currentCapital } = reputation;

  const level =
    globalTenureDays >= 90 ? "Diamond" :
    globalTenureDays >= 30 ? "Gold" :
    globalTenureDays >= 7  ? "Silver" :
    globalTenureDays >= 1  ? "Bronze" : "New";

  const levelColors: Record<string, string> = {
    Diamond: "text-cyan-300 border-cyan-500/40 bg-cyan-500/10",
    Gold:    "text-yellow-300 border-yellow-500/40 bg-yellow-500/10",
    Silver:  "text-slate-300 border-slate-400/40 bg-slate-400/10",
    Bronze:  "text-orange-300 border-orange-500/40 bg-orange-500/10",
    New:     "text-gray-400 border-gray-600/40 bg-gray-600/10",
  };

  const levelIcons: Record<string, string> = {
    Diamond: "◆",
    Gold: "●",
    Silver: "●",
    Bronze: "●",
    New: "○",
  };

  if (compact) {
    return (
      <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded border text-xs font-medium ${levelColors[level]}`}>
        {levelIcons[level]} {level}
      </span>
    );
  }

  return (
    <div className={`rounded-xl border p-4 ${levelColors[level]}`}>
      <div className="flex items-center justify-between mb-3">
        <span className="text-2xl">{levelIcons[level]}</span>
        <span className="text-lg font-bold">{level}</span>
      </div>
      <div className="space-y-1.5 text-sm">
        <div className="flex justify-between">
          <span className="opacity-60">Global tenure</span>
          <span className="font-mono font-semibold">{globalTenureDays}d</span>
        </div>
        <div className="flex justify-between">
          <span className="opacity-60">Open capital</span>
          <span className="font-mono font-semibold">
            ${currentCapital.toLocaleString()}
          </span>
        </div>
        <div className="flex justify-between">
          <span className="opacity-60">Active chains</span>
          <span className="font-mono text-xs">{chains.join(", ") || "—"}</span>
        </div>
      </div>
    </div>
  );
}
