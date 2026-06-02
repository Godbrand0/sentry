"use client";

import Link from "next/link";
import TaxCurveChart from "@/components/TaxCurveChart";

// ── Reusable primitives ──────────────────────────────────────────────────────

function Badge({ children, color = "violet" }: { children: React.ReactNode; color?: "violet" | "red" | "green" | "blue" | "orange" }) {
  const styles = {
    violet: "bg-violet-500/10 text-violet-400 border-violet-500/20",
    red:    "bg-red-500/10 text-red-400 border-red-500/20",
    green:  "bg-green-500/10 text-green-400 border-green-500/20",
    blue:   "bg-blue-500/10 text-blue-400 border-blue-500/20",
    orange: "bg-orange-500/10 text-orange-400 border-orange-500/20",
  };
  return (
    <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium border ${styles[color]}`}>
      {children}
    </span>
  );
}

function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <p className="text-xs font-mono text-violet-400 uppercase tracking-widest mb-3">{children}</p>
  );
}

function Card({ children, className = "" }: { children: React.ReactNode; className?: string }) {
  return (
    <div className={`bg-[#14141e] border border-[#1e1e2e] rounded-2xl p-6 ${className}`}>
      {children}
    </div>
  );
}

function StatCard({ value, label, sub, color = "white" }: { value: string; label: string; sub?: string; color?: string }) {
  return (
    <div className="bg-[#0d0d14] border border-[#1e1e2e] rounded-xl p-5 text-center">
      <p className={`text-3xl font-mono font-bold mb-1 ${color}`}>{value}</p>
      <p className="text-sm text-[#aaa]">{label}</p>
      {sub && <p className="text-xs text-[#555] mt-1">{sub}</p>}
    </div>
  );
}

// ── Code block ───────────────────────────────────────────────────────────────

function CodeBlock({ title, language = "solidity", children }: { title?: string; language?: string; children: string }) {
  const lines = children.trim().split("\n");
  return (
    <div className="rounded-xl overflow-hidden border border-[#1e1e2e]">
      {title && (
        <div className="flex items-center justify-between px-4 py-2.5 bg-[#111118] border-b border-[#1e1e2e]">
          <div className="flex items-center gap-2">
            <span className="w-3 h-3 rounded-full bg-red-500/70" />
            <span className="w-3 h-3 rounded-full bg-yellow-500/70" />
            <span className="w-3 h-3 rounded-full bg-green-500/70" />
            <span className="ml-2 text-xs text-[#555] font-mono">{title}</span>
          </div>
          <span className="text-xs text-[#444] font-mono">{language}</span>
        </div>
      )}
      <pre className="bg-[#0a0a10] overflow-x-auto p-5 text-sm leading-6">
        <code className="font-mono">
          {lines.map((line, i) => (
            <SyntaxLine key={i} line={line} />
          ))}
        </code>
      </pre>
    </div>
  );
}

function SyntaxLine({ line }: { line: string }) {
  // Minimal syntax colouring without a library
  if (line.trimStart().startsWith("//") || line.trimStart().startsWith("*") || line.trimStart().startsWith("/*")) {
    return <div className="text-[#4b5563]">{line}{"\n"}</div>;
  }
  const keywords = /\b(function|returns|external|internal|view|pure|public|uint256|uint128|uint64|uint16|int128|address|bool|bytes|bytes32|mapping|struct|event|emit|if|else|return|override|memory|storage|calldata|require|revert|contract|import|pragma|interface|modifier|constructor|immutable|constant|delete|unchecked|for|new)\b/g;
  const parts = line.split(keywords);
  return (
    <div>
      {parts.map((part, i) => {
        if (keywords.test(part)) {
          return <span key={i} className="text-violet-400">{part}</span>;
        }
        // numbers
        const numParts = part.split(/(\b\d[\d_]*(?:e\d+)?\b)/g);
        return (
          <span key={i}>
            {numParts.map((np, j) =>
              /^\d/.test(np)
                ? <span key={j} className="text-orange-300">{np}</span>
                : <span key={j} className="text-[#e2e8f0]">{np}</span>
            )}
          </span>
        );
      })}
      {"\n"}
    </div>
  );
}

// ── Flow diagram ─────────────────────────────────────────────────────────────

function FlowStep({ n, label, sub, color = "#8b5cf6" }: { n: string; label: string; sub: string; color?: string }) {
  return (
    <div className="flex items-start gap-3">
      <div className="shrink-0 w-8 h-8 rounded-full flex items-center justify-center text-sm font-bold text-white" style={{ background: color }}>
        {n}
      </div>
      <div>
        <p className="text-sm font-semibold text-white">{label}</p>
        <p className="text-xs text-[#666] mt-0.5 leading-relaxed">{sub}</p>
      </div>
    </div>
  );
}

function Arrow() {
  return <div className="ml-4 w-px h-4 bg-[#2a2a3a]" />;
}

// ── Main page ────────────────────────────────────────────────────────────────

export default function LandingPage() {
  return (
    <div className="space-y-32 pb-32">

      {/* ── HERO ─────────────────────────────────────────────────────────── */}
      <section className="pt-8">
        <div className="relative overflow-hidden rounded-3xl bg-gradient-to-br from-[#12102a] via-[#0d0b1f] to-[#0a0a0e] border border-[#2a2040] px-8 py-20 md:px-16 md:py-28 text-center">
          <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_50%_0%,rgba(139,92,246,0.15),transparent_70%)] pointer-events-none" />
          <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_80%_80%,rgba(99,102,241,0.08),transparent_60%)] pointer-events-none" />

          <div className="relative max-w-3xl mx-auto">
            <div className="flex items-center justify-center gap-2 mb-8">
              <Badge color="violet">Uniswap V4 Hook</Badge>
              <Badge color="blue">Reactive Network</Badge>
              <Badge color="green">Unichain Sepolia</Badge>
            </div>

            <h1 className="text-4xl md:text-6xl font-bold text-white mb-6 leading-tight tracking-tight">
              Stop JIT bots from<br />
              <span className="text-transparent bg-clip-text bg-gradient-to-r from-violet-400 to-indigo-400">
                stealing your fees
              </span>
            </h1>

            <p className="text-lg text-[#888] max-w-xl mx-auto mb-10 leading-relaxed">
              Sentry is a Uniswap V4 hook that taxes short-lived liquidity positions and
              redistributes the captured fees back to loyal long-term LPs.
              No binary locks. No keeper bots. Fully automated via Reactive Network.
            </p>

            <div className="flex flex-wrap items-center justify-center gap-4">
              <Link href="/jit-demo" className="bg-violet-600 hover:bg-violet-500 text-white font-medium px-6 py-3 rounded-xl transition-colors text-sm">
                See live demo
              </Link>
              <Link href="/dashboard" className="bg-[#ffffff08] hover:bg-[#ffffff12] border border-[#2a2a3a] text-[#ccc] font-medium px-6 py-3 rounded-xl transition-colors text-sm">
                Open dashboard
              </Link>
            </div>
          </div>
        </div>

        {/* Stats strip */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mt-4">
          <StatCard value="36,671" label="JIT attacks documented" sub="on Uniswap ETH/USDC" color="text-red-400" />
          <StatCard value="85%" label="Average fee dilution" sub="per swap without Sentry" color="text-orange-400" />
          <StatCard value="7,500 ETH" label="Estimated LP losses" sub="to JIT extraction" color="text-yellow-400" />
          <StatCard value="65%" label="Tax on same-block exits" sub="redistributed to LPs" color="text-green-400" />
        </div>
      </section>

      {/* ── THE PROBLEM ──────────────────────────────────────────────────── */}
      <section>
        <div className="text-center mb-12">
          <SectionLabel>The Problem</SectionLabel>
          <h2 className="text-3xl md:text-4xl font-bold text-white mb-4">
            The MEV attack nobody talks about
          </h2>
          <p className="text-[#888] max-w-2xl mx-auto">
            Just-in-time liquidity bots watch the mempool for large pending swaps,
            front-run the block by depositing massive concentrated liquidity,
            capture the fee, and immediately withdraw — all in a single block.
            Legitimate LPs earn almost nothing.
          </p>
        </div>

        {/* Before / After comparison */}
        <div className="grid md:grid-cols-2 gap-4">
          <Card className="border-red-500/20">
            <div className="flex items-center gap-2 mb-5">
              <div className="w-2 h-2 rounded-full bg-red-400" />
              <p className="text-sm font-semibold text-red-400">Without Sentry — what happens today</p>
            </div>

            <div className="space-y-3 text-sm">
              {[
                ["Swapper sends", "$5,000,000 USDC → ETH", "text-[#aaa]"],
                ["Fee generated (0.05%)", "$2,500 total", "text-[#aaa]"],
                ["JIT bot captures", "$2,475 (99% of fees)", "text-red-400 font-semibold"],
                ["Real LPs receive", "$25 (1% of fees)", "text-[#666]"],
                ["Bot holds position for", "4 seconds", "text-red-400"],
                ["Bot walks away with", "$2,475 profit", "text-red-400 font-bold"],
              ].map(([k, v, cls]) => (
                <div key={k} className="flex justify-between border-b border-[#1a1a28] pb-2">
                  <span className="text-[#555]">{k}</span>
                  <span className={cls}>{v}</span>
                </div>
              ))}
            </div>

            <div className="mt-5 bg-red-500/5 border border-red-500/20 rounded-xl p-4 text-xs text-[#888] leading-relaxed">
              The bot earns <span className="text-red-300 font-semibold">$2,475 in 4 seconds</span> — an annualised return of
              billions of percent. Long-term LPs who built the pool&apos;s depth are left with near-zero compensation.
            </div>
          </Card>

          <Card className="border-green-500/20">
            <div className="flex items-center gap-2 mb-5">
              <div className="w-2 h-2 rounded-full bg-green-400" />
              <p className="text-sm font-semibold text-green-400">With Sentry — attack neutralised</p>
            </div>

            <div className="space-y-3 text-sm">
              {[
                ["Swapper sends", "$5,000,000 USDC → ETH", "text-[#aaa]"],
                ["Fee generated (0.05%)", "$2,500 total", "text-[#aaa]"],
                ["JIT bot earns", "$2,475 (before tax)", "text-[#aaa]"],
                ["Sentry tax applied", "65% (0s hold, 91% conc.)", "text-violet-400 font-semibold"],
                ["Bot keeps", "$866 (35%)", "text-orange-400"],
                ["Long-term LPs receive", "$1,517 (60%)", "text-green-400 font-bold"],
                ["Protocol treasury", "$123 (5%)", "text-[#888]"],
              ].map(([k, v, cls]) => (
                <div key={k} className="flex justify-between border-b border-[#1a1a28] pb-2">
                  <span className="text-[#555]">{k}</span>
                  <span className={cls}>{v}</span>
                </div>
              ))}
            </div>

            <div className="mt-5 bg-green-500/5 border border-green-500/20 rounded-xl p-4 text-xs text-[#888] leading-relaxed">
              JIT remains <span className="text-orange-300 font-semibold">unprofitable after gas costs</span>. The attack still runs,
              but Sentry intercepts 65% of captured fees and routes them back to people who actually provide liquidity.
            </div>
          </Card>
        </div>
      </section>

      {/* ── WHO IT'S FOR / AGAINST ───────────────────────────────────────── */}
      <section>
        <div className="text-center mb-12">
          <SectionLabel>Participants</SectionLabel>
          <h2 className="text-3xl md:text-4xl font-bold text-white mb-4">
            Who Sentry protects. Who it fights.
          </h2>
        </div>

        <div className="grid md:grid-cols-2 gap-6">
          {/* Protected */}
          <Card className="border-green-500/20">
            <div className="flex items-center gap-3 mb-6">
              <div className="w-10 h-10 rounded-xl bg-green-500/10 border border-green-500/20 flex items-center justify-center text-green-400 text-lg">
                LP
              </div>
              <div>
                <p className="font-semibold text-white">Long-term Liquidity Providers</p>
                <p className="text-xs text-green-400">Protected by Sentry</p>
              </div>
            </div>
            <p className="text-sm text-[#888] leading-relaxed mb-5">
              Retail and institutional LPs who deposit liquidity for days, weeks, or months.
              They provide the price discovery and depth that makes a pool useful — and
              historically they were the ones subsidising bots without knowing it.
            </p>
            <div className="space-y-2">
              {[
                "Earn redistribution payouts from every JIT attack on their pool",
                "Cross-chain reputation means history on Base counts on Unichain",
                "Tax discount for LPs with proven long-term track record",
                "Eligible for redistribution after holding for more than 24 hours",
              ].map(b => (
                <div key={b} className="flex items-start gap-2 text-xs text-[#888]">
                  <span className="text-green-400 mt-0.5 shrink-0">+</span>
                  {b}
                </div>
              ))}
            </div>
          </Card>

          {/* Fought */}
          <Card className="border-red-500/20">
            <div className="flex items-center gap-3 mb-6">
              <div className="w-10 h-10 rounded-xl bg-red-500/10 border border-red-500/20 flex items-center justify-center text-red-400 text-sm font-mono">
                BOT
              </div>
              <div>
                <p className="font-semibold text-white">JIT MEV Bots</p>
                <p className="text-xs text-red-400">Repriced by Sentry</p>
              </div>
            </div>
            <p className="text-sm text-[#888] leading-relaxed mb-5">
              Automated searchers that monitor pending transactions, calculate the optimal
              liquidity deposit for an incoming large swap, execute a deposit + withdrawal
              in the same block, and collect fees without bearing any sustained risk.
            </p>
            <div className="space-y-2">
              {[
                "Pay 65% tax on same-block exits — above gas cost in most cases",
                "Concentration multiplier adds up to 2x penalty for tight tick ranges",
                "Tax scales continuously — no incentive to hold just slightly longer",
                "Cross-chain reputation is zero for fresh bot addresses — no discount",
              ].map(b => (
                <div key={b} className="flex items-start gap-2 text-xs text-[#888]">
                  <span className="text-red-400 mt-0.5 shrink-0">−</span>
                  {b}
                </div>
              ))}
            </div>
          </Card>
        </div>
      </section>

      {/* ── HOW IT WORKS ─────────────────────────────────────────────────── */}
      <section>
        <div className="text-center mb-12">
          <SectionLabel>Mechanism</SectionLabel>
          <h2 className="text-3xl md:text-4xl font-bold text-white mb-4">
            How Sentry works
          </h2>
          <p className="text-[#888] max-w-2xl mx-auto">
            Three interlocking pieces: an exponential tax curve, a redistribution pool, and
            cross-chain reputation — all wired together without a single centralised keeper.
          </p>
        </div>

        <div className="grid md:grid-cols-3 gap-4 mb-12">
          {[
            {
              n: "1",
              title: "Exponential tax curve",
              color: "#ef4444",
              body: "When a position is closed, fees are taxed based on how long it was held. The decay is exponential — 65% at t=0, dropping to near-zero by 24 hours. Bots that exit in the same block always pay maximum.",
              note: "tax = 65% × exp(−t / 10min)",
            },
            {
              n: "2",
              title: "Concentration multiplier",
              color: "#f97316",
              body: "Positions covering less than 50% of the active range get an additional 1×–2× multiplier on top of the base tax. This prices in the bot strategy of depositing massive one-tick positions.",
              note: "multiplier = 1 + (concentration − 0.5) × 2",
            },
            {
              n: "3",
              title: "Redistribution pool",
              color: "#22c55e",
              body: "Taxed fees accumulate in a per-pool contract. LPs who have held for more than 24 hours are eligible for payouts, weighted by capital × min(tenure, 90 days). 5% goes to the protocol treasury.",
              note: "score = capital × min(tenure, 90 days)",
            },
          ].map(item => (
            <Card key={item.n}>
              <div className="w-8 h-8 rounded-lg flex items-center justify-center font-bold text-white text-sm mb-4" style={{ background: item.color }}>
                {item.n}
              </div>
              <h3 className="font-semibold text-white mb-2">{item.title}</h3>
              <p className="text-xs text-[#888] leading-relaxed mb-4">{item.body}</p>
              <p className="font-mono text-xs text-[#555] bg-[#0a0a10] rounded-lg px-3 py-2">{item.note}</p>
            </Card>
          ))}
        </div>

        {/* Tax curve chart */}
        <Card>
          <div className="flex items-center justify-between mb-6">
            <div>
              <h3 className="font-semibold text-white mb-1">Tax decay curve</h3>
              <p className="text-xs text-[#555]">tax_rate = 65% × exp(−t / 10min) — hover to inspect</p>
            </div>
            <div className="flex gap-3 text-xs">
              {[["JIT", "#ef4444"], ["Short", "#f97316"], ["Medium", "#eab308"], ["Long-term", "#22c55e"]].map(([l, c]) => (
                <div key={l} className="flex items-center gap-1">
                  <span className="w-2 h-2 rounded-full" style={{ background: c }} />
                  <span className="text-[#666]">{l}</span>
                </div>
              ))}
            </div>
          </div>
          <TaxCurveChart height={220} showTiers />
          <div className="grid grid-cols-4 gap-2 mt-4">
            {[
              ["0s", "65%", "Same block"],
              ["5m", "~34%", "5 minutes"],
              ["30m", "~8%", "30 minutes"],
              ["24h", "0%", "Long-term"],
            ].map(([t, tax, label]) => (
              <div key={t} className="text-center bg-[#0a0a10] rounded-lg p-2">
                <p className="text-xs text-[#555]">{t}</p>
                <p className="font-mono font-bold text-sm text-[#ddd]">{tax}</p>
                <p className="text-xs text-[#444]">{label}</p>
              </div>
            ))}
          </div>
        </Card>
      </section>

      {/* ── FINANCIAL MODEL ──────────────────────────────────────────────── */}
      <section>
        <div className="text-center mb-12">
          <SectionLabel>Financial Model</SectionLabel>
          <h2 className="text-3xl md:text-4xl font-bold text-white mb-4">
            Where every dollar of captured fees goes
          </h2>
          <p className="text-[#888] max-w-2xl mx-auto">
            Sentry does not confiscate fees — it reprices time. The JIT bot still keeps 35%.
            But the majority of what it extracted from long-term LPs gets returned.
          </p>
        </div>

        <Card>
          <div className="grid md:grid-cols-3 gap-8 items-center">
            {/* Visual bar */}
            <div className="md:col-span-2 space-y-4">
              <div>
                <div className="flex items-center justify-between text-xs mb-1.5">
                  <span className="text-[#888]">Long-term LPs</span>
                  <span className="text-green-400 font-mono font-bold">60%</span>
                </div>
                <div className="h-6 bg-[#0a0a10] rounded-lg overflow-hidden">
                  <div className="h-full bg-gradient-to-r from-green-500 to-green-400 rounded-lg" style={{ width: "60%" }} />
                </div>
                <p className="text-xs text-[#555] mt-1">Distributed pro-rata by capital × tenure score</p>
              </div>
              <div>
                <div className="flex items-center justify-between text-xs mb-1.5">
                  <span className="text-[#888]">JIT bot keeps</span>
                  <span className="text-orange-400 font-mono font-bold">35%</span>
                </div>
                <div className="h-6 bg-[#0a0a10] rounded-lg overflow-hidden">
                  <div className="h-full bg-gradient-to-r from-orange-500 to-orange-400 rounded-lg" style={{ width: "35%" }} />
                </div>
                <p className="text-xs text-[#555] mt-1">After gas costs, JIT rarely remains profitable</p>
              </div>
              <div>
                <div className="flex items-center justify-between text-xs mb-1.5">
                  <span className="text-[#888]">Protocol treasury</span>
                  <span className="text-violet-400 font-mono font-bold">5%</span>
                </div>
                <div className="h-6 bg-[#0a0a10] rounded-lg overflow-hidden">
                  <div className="h-full bg-gradient-to-r from-violet-500 to-violet-400 rounded-lg" style={{ width: "5%" }} />
                </div>
                <p className="text-xs text-[#555] mt-1">Funds ongoing development and security audits</p>
              </div>
            </div>

            {/* Key insight */}
            <div className="bg-[#0a0a10] rounded-2xl p-5 text-center border border-[#1e1e2e]">
              <p className="text-4xl font-mono font-bold text-green-400 mb-1">+$1,517</p>
              <p className="text-xs text-[#888] mb-5">extra per $5M swap<br />returned to loyal LPs</p>
              <div className="space-y-2 text-xs">
                <div className="flex justify-between">
                  <span className="text-[#555]">Without Sentry</span>
                  <span className="text-red-400">LP gets $25</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-[#555]">With Sentry</span>
                  <span className="text-green-400">LP gets $1,542</span>
                </div>
                <div className="h-px bg-[#1e1e2e]" />
                <div className="flex justify-between font-semibold">
                  <span className="text-[#888]">Improvement</span>
                  <span className="text-green-400">61×</span>
                </div>
              </div>
            </div>
          </div>
        </Card>
      </section>

      {/* ── UNISWAP V4 INTEGRATION ───────────────────────────────────────── */}
      <section>
        <div className="text-center mb-12">
          <SectionLabel>Uniswap V4 Integration</SectionLabel>
          <h2 className="text-3xl md:text-4xl font-bold text-white mb-4">
            Built on V4 hook callbacks
          </h2>
          <p className="text-[#888] max-w-2xl mx-auto">
            Sentry uses four hook callbacks to track every position lifecycle without adding overhead to swaps.
            The tax is enforced at withdrawal time via the <code className="text-violet-400 bg-[#1a1a2e] px-1.5 py-0.5 rounded text-sm">afterRemoveLiquidityReturnDelta</code> permission flag.
          </p>
        </div>

        <div className="grid md:grid-cols-2 gap-4 mb-6">
          {[
            { cb: "afterInitialize", gas: "~30k", color: "text-blue-400", desc: "Deploys a per-pool RedistributionPool and registers the pool's token." },
            { cb: "afterAddLiquidity", gas: "< 80k", color: "text-violet-400", desc: "Records position capital, timestamp, and concentration score against in-range liquidity." },
            { cb: "afterRemoveLiquidity", gas: "< 120k", color: "text-orange-400", desc: "Calculates tax based on hold time and concentration. Routes taxed amount to RedistributionPool via poolManager.take()." },
            { cb: "afterSwap", gas: "< 30k", color: "text-green-400", desc: "Lazily updates the global fee-growth accumulator so per-position fee balances can be computed on demand." },
          ].map(item => (
            <div key={item.cb} className="bg-[#0d0d14] border border-[#1e1e2e] rounded-xl p-4 flex items-start gap-4">
              <div className="shrink-0 w-1.5 h-16 rounded-full bg-[#1e1e2e]">
                <div className="w-full rounded-full" style={{ height: "100%", background: item.color.replace("text-", "").includes("violet") ? "#8b5cf6" : item.color.includes("orange") ? "#f97316" : item.color.includes("green") ? "#22c55e" : "#60a5fa" }} />
              </div>
              <div>
                <div className="flex items-center gap-2 mb-1">
                  <code className={`text-sm font-mono font-semibold ${item.color}`}>{item.cb}</code>
                  <span className="text-xs text-[#444] font-mono">{item.gas} gas</span>
                </div>
                <p className="text-xs text-[#888] leading-relaxed">{item.desc}</p>
              </div>
            </div>
          ))}
        </div>

        <CodeBlock title="SentryHook.sol — afterRemoveLiquidity (core tax logic)" language="solidity">
{`// When an LP removes liquidity, Sentry intercepts via afterRemoveLiquidityReturnDelta
function afterRemoveLiquidity(
    address sender,
    PoolKey calldata key,
    IPoolManager.ModifyLiquidityParams calldata params,
    BalanceDelta delta,
    BalanceDelta feesAccrued,
    bytes calldata
) external override onlyPoolManager returns (bytes4, BalanceDelta) {
    uint64 timeHeld = uint64(block.timestamp) - pos.openedAt;

    // Exponential decay: 65% at t=0, approaches 0 at 24h
    // Concentration multiplier applied for tight tick ranges (up to 2x)
    uint256 taxBps = TaxCurve.calculateFinalTaxBps(timeHeld, pos.concentrationBps);

    // Apply cross-chain reputation discount (via Reactive Network oracle)
    taxBps = _applyReputationDiscount(sender, taxBps);

    uint128 taxAmount = uint128((uint256(fees0) * taxBps) / 10000);

    // Positive hookDelta: callerDelta = callerDelta - hookDelta
    // LP receives less; PM credits hook the taxAmount
    hookDelta = toBalanceDelta(int128(taxAmount), 0);

    // Settle hook credit: pull tokens from PoolManager into the redistribution pool
    poolManager.take(key.currency0, address(rPool), taxAmount);
    rPool.deposit(PoolId.unwrap(poolId), taxAmount);

    emit TaxAccumulated(PoolId.unwrap(poolId), taxAmount);
    return (IHooks.afterRemoveLiquidity.selector, hookDelta);
}`}
        </CodeBlock>
      </section>

      {/* ── REACTIVE NETWORK ─────────────────────────────────────────────── */}
      <section>
        <div className="text-center mb-12">
          <SectionLabel>Reactive Network</SectionLabel>
          <h2 className="text-3xl md:text-4xl font-bold text-white mb-4">
            Fully automated. No keepers.
          </h2>
          <p className="text-[#888] max-w-2xl mx-auto">
            Reactive Network watches on-chain events and executes callbacks automatically.
            Sentry uses it for two critical automations — both without any off-chain
            infrastructure.
          </p>
        </div>

        {/* Role 1 — Redistribution */}
        <div className="mb-8">
          <div className="flex items-center gap-3 mb-4">
            <Badge color="violet">Role 1</Badge>
            <h3 className="font-semibold text-white">Automatic redistribution trigger</h3>
          </div>

          <div className="grid md:grid-cols-2 gap-4">
            <Card>
              <p className="text-sm text-[#888] leading-relaxed mb-5">
                Every time SentryHook taxes a JIT bot, it emits <code className="text-violet-300 text-xs bg-[#1a1a2e] px-1 rounded">TaxAccumulated(poolId, amount)</code>.
                The <strong className="text-white">RedistributionScheduler</strong> on Reactive Kopli subscribes to this
                event. When pool balance exceeds $1,000 or 24 hours have elapsed, it emits a
                Callback that Reactive Network submits back to <code className="text-violet-300 text-xs bg-[#1a1a2e] px-1 rounded">executeRedistribution()</code> on the source chain.
              </p>
              <div className="space-y-2">
                <FlowStep n="1" color="#ef4444" label="Bot exits → TaxAccumulated emitted on Unichain" sub="SentryHook deducts tax and deposits to RedistributionPool" />
                <Arrow />
                <FlowStep n="2" color="#8b5cf6" label="Reactive delivers event to Kopli" sub="RedistributionScheduler.react() checks threshold ($1k) and cooldown (24h)" />
                <Arrow />
                <FlowStep n="3" color="#8b5cf6" label="Scheduler emits Callback event" sub="Payload encodes executeRedistribution(poolId)" />
                <Arrow />
                <FlowStep n="4" color="#22c55e" label="Reactive submits the call back to Unichain" sub="Long-term LPs receive their payout automatically" />
              </div>
            </Card>

            <CodeBlock title="RedistributionScheduler.sol (Reactive Kopli)" language="solidity">
{`// Called by Reactive Network VM for each TaxAccumulated event
function react(
    uint256 chainId,
    address origin,
    bytes32 topic0,
    bytes32 topic1, // indexed poolId
    bytes32,
    bytes memory data
) external vmOnly {
    if (topic0 != TAX_ACCUMULATED_SIG) return;

    bytes32 poolId = topic1;
    (uint128 amount) = abi.decode(data, (uint128));

    PoolSchedule storage sched = _schedules[chainId][origin][poolId];
    sched.accumulated += amount;

    bool thresholdMet   = sched.accumulated >= THRESHOLD_AMOUNT; // $1,000
    bool cooldownExpired = block.timestamp >= sched.lastRedistributionAt + 24 hours;

    if (thresholdMet || cooldownExpired) {
        sched.accumulated = 0;
        sched.lastRedistributionAt = uint64(block.timestamp);

        bytes memory payload = abi.encodeWithSignature(
            "executeRedistribution(bytes32)", poolId
        );
        // Reactive Network picks up this event and submits the call
        emit Callback(chainId, origin, CALLBACK_GAS_LIMIT, payload);
    }
}`}
            </CodeBlock>
          </div>
        </div>

        {/* Role 2 — Reputation */}
        <div>
          <div className="flex items-center gap-3 mb-4">
            <Badge color="blue">Role 2</Badge>
            <h3 className="font-semibold text-white">Cross-chain LP reputation</h3>
          </div>

          <div className="grid md:grid-cols-2 gap-4">
            <Card>
              <p className="text-sm text-[#888] leading-relaxed mb-5">
                An LP with 6 months of history on Base shouldn&apos;t be taxed at full rate when they move to Unichain.
                The <strong className="text-white">ReputationAggregator</strong> on Reactive Kopli subscribes to
                <code className="text-violet-300 text-xs bg-[#1a1a2e] px-1 mx-1 rounded">PositionOpened</code> and
                <code className="text-violet-300 text-xs bg-[#1a1a2e] px-1 rounded">PositionClosed</code> events
                from all chains. It maintains a global <code className="text-green-300 text-xs bg-[#0d1f14] px-1 rounded">totalCapitalSeconds</code> record and
                broadcasts updates to every chain&apos;s ReputationOracle.
              </p>
              <div className="space-y-2">
                <FlowStep n="1" color="#60a5fa" label="Alice closes position on Base Sepolia" sub="PositionClosed event emitted with capital and timeHeld" />
                <Arrow />
                <FlowStep n="2" color="#8b5cf6" label="ReputationAggregator on Kopli updates record" sub="totalCapitalSeconds += capital * timeHeld" />
                <Arrow />
                <FlowStep n="3" color="#8b5cf6" label="Broadcasts to every destination oracle" sub="Emits Callback for Unichain and Base Sepolia oracles" />
                <Arrow />
                <FlowStep n="4" color="#22c55e" label="SentryHook reads Alice's reputation on Unichain" sub="_applyReputationDiscount() reduces her tax rate" />
              </div>
            </Card>

            <CodeBlock title="ReputationAggregator.sol (Reactive Kopli)" language="solidity">
{`// Called by Reactive Network VM for each PositionOpened/Closed event
function react(
    uint256, /* chainId */
    address, /* origin */
    bytes32 topic0,
    bytes32 topic1, // indexed lp address
    bytes32 topic2, // indexed positionKey
    bytes memory data
) external vmOnly {
    address lp     = address(uint160(uint256(topic1)));
    bytes32 posKey = topic2;

    if (topic0 == POSITION_OPENED_SIG) {
        _handleOpen(lp, posKey, data);
    } else if (topic0 == POSITION_CLOSED_SIG) {
        _handleClose(lp, posKey, data);
    }

    // Push updated reputation to all destination chains
    _broadcastUpdate(lp);
}

function _broadcastUpdate(address lp) private {
    GlobalReputation storage rep = reputations[lp];
    bytes memory payload = abi.encodeWithSignature(
        "setReputation(address,uint128,uint128,uint64)",
        lp,
        rep.totalCapitalSeconds, // Σ(capital × time) across all chains
        rep.currentCapital,
        rep.lastEventTimestamp
    );
    for (uint256 i = 0; i < destinationOracles.length; i++) {
        emit Callback(destinationChainIds[i], destinationOracles[i],
            CALLBACK_GAS_LIMIT, payload);
    }
}`}
            </CodeBlock>
          </div>
        </div>
      </section>

      {/* ── ARCHITECTURE ─────────────────────────────────────────────────── */}
      <section>
        <div className="text-center mb-12">
          <SectionLabel>Architecture</SectionLabel>
          <h2 className="text-3xl md:text-4xl font-bold text-white mb-4">
            System overview
          </h2>
        </div>

        <Card>
          <div className="overflow-x-auto">
            <div className="min-w-[600px] space-y-2 font-mono text-sm">
              {/* Chain labels */}
              <div className="grid grid-cols-3 gap-4 mb-4 text-xs text-center">
                <div className="bg-blue-500/10 border border-blue-500/20 rounded-lg py-2 text-blue-400">Unichain Sepolia</div>
                <div className="bg-violet-500/10 border border-violet-500/20 rounded-lg py-2 text-violet-400">Reactive Kopli</div>
                <div className="bg-indigo-500/10 border border-indigo-500/20 rounded-lg py-2 text-indigo-400">Base Sepolia</div>
              </div>

              {/* Contracts */}
              <div className="grid grid-cols-3 gap-4 text-xs text-center">
                <div className="space-y-2">
                  <div className="bg-[#0d0d14] border border-[#2a2040] rounded-lg py-3 px-2 text-violet-300">SentryHook</div>
                  <div className="bg-[#0d0d14] border border-[#1e1e2e] rounded-lg py-2 px-2 text-[#888]">RedistributionPool</div>
                  <div className="bg-[#0d0d14] border border-[#1e1e2e] rounded-lg py-2 px-2 text-[#888]">ReputationOracle</div>
                </div>
                <div className="space-y-2">
                  <div className="bg-[#0d0d14] border border-[#2a1040] rounded-lg py-3 px-2 text-purple-300">ReputationAggregator</div>
                  <div className="bg-[#0d0d14] border border-[#2a1040] rounded-lg py-3 px-2 text-purple-300">RedistributionScheduler</div>
                </div>
                <div className="space-y-2">
                  <div className="bg-[#0d0d14] border border-[#1a1a30] rounded-lg py-3 px-2 text-indigo-300">SentryHook</div>
                  <div className="bg-[#0d0d14] border border-[#1e1e2e] rounded-lg py-2 px-2 text-[#888]">RedistributionPool</div>
                  <div className="bg-[#0d0d14] border border-[#1e1e2e] rounded-lg py-2 px-2 text-[#888]">ReputationOracle</div>
                </div>
              </div>

              {/* Event flows */}
              <div className="mt-6 space-y-2 text-xs text-[#555]">
                <div className="flex items-center gap-2">
                  <span className="text-blue-400 w-32 shrink-0">PositionOpened/Closed</span>
                  <span className="text-[#333]">──────────────────────→</span>
                  <span className="text-violet-400">ReputationAggregator.react()</span>
                  <span className="text-[#333]">──→</span>
                  <span className="text-indigo-400">setReputation() on both chains</span>
                </div>
                <div className="flex items-center gap-2">
                  <span className="text-blue-400 w-32 shrink-0">TaxAccumulated</span>
                  <span className="text-[#333]">──────────────────────→</span>
                  <span className="text-violet-400">RedistributionScheduler.react()</span>
                  <span className="text-[#333]">──→</span>
                  <span className="text-blue-400">executeRedistribution(poolId)</span>
                </div>
              </div>
            </div>
          </div>
        </Card>
      </section>

      {/* ── NEXT STEPS ───────────────────────────────────────────────────── */}
      <section>
        <div className="text-center mb-12">
          <SectionLabel>Roadmap</SectionLabel>
          <h2 className="text-3xl md:text-4xl font-bold text-white mb-4">
            What comes next
          </h2>
        </div>

        <div className="grid md:grid-cols-2 gap-4">
          {[
            {
              status: "done",
              phase: "Phase 1 — Core",
              items: [
                "SentryHook with full V4 callback implementation",
                "Exponential tax curve with concentration multiplier",
                "RedistributionPool with capital × tenure scoring",
                "48 passing tests (unit, integration, reactive)",
                "Next.js dashboard with JIT attack simulator",
              ],
            },
            {
              status: "done",
              phase: "Phase 2 — Reactive",
              items: [
                "ReputationAggregator on Reactive Kopli",
                "RedistributionScheduler with threshold + cooldown logic",
                "Cross-chain setReputation() callback to ReputationOracle",
                "Reputation discount in hook tax calculation",
                "Reactive Network tests with MockSubscriptionService",
              ],
            },
            {
              status: "next",
              phase: "Phase 3 — Testnet",
              items: [
                "Deploy SentryHook to Unichain Sepolia + Base Sepolia",
                "Deploy Reactive contracts to Kopli testnet",
                "Wire subscription service and authorize callbacks",
                "Replace mock frontend data with live contract reads",
                "End-to-end demo with real testnet transactions",
              ],
            },
            {
              status: "next",
              phase: "Phase 4 — Production",
              items: [
                "Security audit of hook and redistribution logic",
                "Governance controls for tax parameters (halfLife, maxTax)",
                "Multi-pool dashboard with live redistribution feeds",
                "LP reputation leaderboard with cross-chain history",
                "Mainnet deployment on Unichain and Base",
              ],
            },
          ].map(item => (
            <Card key={item.phase}>
              <div className="flex items-center gap-2 mb-4">
                <div className={`w-2 h-2 rounded-full ${item.status === "done" ? "bg-green-400" : "bg-[#444]"}`} />
                <span className={`text-xs font-mono ${item.status === "done" ? "text-green-400" : "text-[#555]"}`}>
                  {item.status === "done" ? "Complete" : "Upcoming"}
                </span>
                <span className="text-sm font-semibold text-white ml-auto">{item.phase}</span>
              </div>
              <ul className="space-y-2">
                {item.items.map(i => (
                  <li key={i} className="flex items-start gap-2 text-xs text-[#888]">
                    <span className={`mt-0.5 shrink-0 ${item.status === "done" ? "text-green-500" : "text-[#444]"}`}>
                      {item.status === "done" ? "✓" : "○"}
                    </span>
                    {i}
                  </li>
                ))}
              </ul>
            </Card>
          ))}
        </div>
      </section>

      {/* ── FINAL CTA ────────────────────────────────────────────────────── */}
      <section>
        <div className="relative overflow-hidden rounded-3xl bg-gradient-to-br from-[#12102a] to-[#0a0a0e] border border-[#2a2040] px-8 py-16 text-center">
          <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_50%_100%,rgba(139,92,246,0.12),transparent_70%)] pointer-events-none" />
          <div className="relative">
            <p className="text-xs font-mono text-violet-400 uppercase tracking-widest mb-4">Built for the Uniswap Hook Incubator</p>
            <h2 className="text-3xl md:text-4xl font-bold text-white mb-4">
              Liquidity should reward patience,<br />not speed.
            </h2>
            <p className="text-[#888] max-w-lg mx-auto mb-8">
              Try the JIT attack simulator, explore the live dashboard, or read the
              contracts. Everything is open source.
            </p>
            <div className="flex flex-wrap items-center justify-center gap-4">
              <Link href="/jit-demo" className="bg-violet-600 hover:bg-violet-500 text-white font-medium px-6 py-3 rounded-xl transition-colors text-sm">
                Run JIT simulation
              </Link>
              <Link href="/dashboard" className="bg-[#ffffff08] hover:bg-[#ffffff12] border border-[#2a2a3a] text-[#ccc] font-medium px-6 py-3 rounded-xl transition-colors text-sm">
                Open dashboard
              </Link>
              <a
                href="https://github.com"
                target="_blank"
                rel="noopener noreferrer"
                className="bg-[#ffffff08] hover:bg-[#ffffff12] border border-[#2a2a3a] text-[#ccc] font-medium px-6 py-3 rounded-xl transition-colors text-sm"
              >
                View on GitHub
              </a>
            </div>
            <div className="flex items-center justify-center gap-6 mt-10 text-xs text-[#444]">
              <span>Powered by Reactive Network</span>
              <span>·</span>
              <span>Built on Uniswap V4</span>
              <span>·</span>
              <span>48 passing tests</span>
            </div>
          </div>
        </div>
      </section>

    </div>
  );
}
