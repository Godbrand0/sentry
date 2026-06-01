"use client";

import { useState, useEffect, useCallback } from "react";
import TaxCurveChart from "@/components/TaxCurveChart";
import { taxPercent } from "@/lib/taxCurve";
import { formatUSD, TIER_BG, getTier, TIER_LABELS } from "@/lib/data";

type Step = "idle" | "mempool" | "deposit" | "swap" | "withdraw" | "tax" | "done";

interface LogEntry {
  id: number;
  type: "info" | "bot" | "tax" | "lp" | "warning";
  text: string;
  value?: string;
}

const BOT_DEPOSIT = 50_000_000;
const BOT_FEES = 2_475;
const POOL_FEE = 2_500;
const BOT_CONCENTRATION_BPS = 9100;
const EXISTING_LP_FEES_PRE = 25;

const STEPS: { id: Step; label: string; description: string }[] = [
  { id: "idle", label: "Ready", description: "Click Start to run the simulation" },
  { id: "mempool", label: "Mempool watch", description: "Bot detects large pending swap" },
  { id: "deposit", label: "Bot deposits", description: "Bot front-runs with $50M in 1 tick" },
  { id: "swap", label: "Swap executes", description: "$5M USDC→ETH swap executes" },
  { id: "withdraw", label: "Bot withdraws", description: "Bot exits same block" },
  { id: "tax", label: "Sentry taxes", description: "90%+ tax applied, fees routed" },
  { id: "done", label: "LPs paid", description: "Long-term LPs receive redistribution" },
];

function LogLine({ entry }: { entry: LogEntry }) {
  const colors = {
    info: "text-[#888]",
    bot: "text-red-400",
    tax: "text-violet-400",
    lp: "text-green-400",
    warning: "text-yellow-400",
  };
  const prefixes = { info: "  ", bot: "⚡", tax: "⚖", lp: "✓", warning: "!" };

  return (
    <div className={`flex items-start gap-2 font-mono text-xs leading-5 ${colors[entry.type]}`}>
      <span className="shrink-0 w-4">{prefixes[entry.type]}</span>
      <span className="flex-1">{entry.text}</span>
      {entry.value && <span className="shrink-0 font-bold">{entry.value}</span>}
    </div>
  );
}

function TaxGauge({ taxPct }: { taxPct: number }) {
  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between text-sm">
        <span className="text-[#888]">Tax rate</span>
        <span className={`font-mono font-bold ${taxPct > 50 ? "text-red-400" : taxPct > 10 ? "text-orange-400" : "text-green-400"}`}>
          {taxPct.toFixed(1)}%
        </span>
      </div>
      <div className="h-2 bg-[#1a1a2e] rounded-full overflow-hidden">
        <div
          className="h-full rounded-full transition-all duration-700"
          style={{
            width: `${Math.min(100, taxPct)}%`,
            background: taxPct > 50 ? "#ef4444" : taxPct > 10 ? "#f97316" : "#22c55e",
          }}
        />
      </div>
    </div>
  );
}

export default function JITDemoPage() {
  const [step, setStep] = useState<Step>("idle");
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [isRunning, setIsRunning] = useState(false);
  const [logId, setLogId] = useState(0);

  const [botFees, setBotFees] = useState(0);
  const [botKept, setBotKept] = useState(0);
  const [taxAmount, setTaxAmount] = useState(0);
  const [lpGain, setLpGain] = useState(0);
  const [protocolFee, setProtocolFee] = useState(0);
  const [holdSeconds, setHoldSeconds] = useState(0);

  const addLog = useCallback((entry: Omit<LogEntry, "id">) => {
    setLogId((prev) => {
      const id = prev + 1;
      setLogs((logs) => [...logs.slice(-40), { ...entry, id }]);
      return id;
    });
  }, []);

  const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

  const runSimulation = useCallback(async () => {
    setIsRunning(true);
    setLogs([]);
    setBotFees(0); setBotKept(0); setTaxAmount(0);
    setLpGain(0); setProtocolFee(0); setHoldSeconds(0);

    // Mempool
    setStep("mempool");
    addLog({ type: "info", text: "Unichain Sepolia · block #50000" });
    addLog({ type: "info", text: "PoolManager watching ETH/USDC..." });
    await sleep(800);
    addLog({ type: "warning", text: "Pending tx detected: swap $5M USDC → ETH" });
    await sleep(600);
    addLog({ type: "bot", text: "Bot: large swap in mempool. Preparing JIT..." });

    // Deposit
    await sleep(700);
    setStep("deposit");
    addLog({ type: "bot", text: "Bot: depositing $50M in single tick range [2999, 3001]" });
    await sleep(500);
    addLog({ type: "info", text: "afterAddLiquidity → position recorded" });
    addLog({ type: "info", text: "concentrationBps: 9100 (91% of in-range liquidity)" });
    addLog({ type: "info", text: "openedAt: block.timestamp" });

    // Swap
    await sleep(800);
    setStep("swap");
    addLog({ type: "info", text: "Swap executes: $5,000,000 USDC → ETH" });
    await sleep(400);
    addLog({ type: "info", text: "Total fee generated: $2,500 (0.05%)" });
    setBotFees(BOT_FEES);
    addLog({ type: "bot", text: "Bot captures $2,475 of fees (99% of pool)  ", value: "$2,475" });
    addLog({ type: "warning", text: "Existing LPs diluted to $25 (1%)         ", value: "$25" });

    // Withdraw
    await sleep(900);
    setStep("withdraw");
    const held = 4; // seconds (same block)
    setHoldSeconds(held);
    addLog({ type: "bot", text: `Bot: withdrawing (time held: ${held}s)` });
    await sleep(400);
    addLog({ type: "info", text: "afterRemoveLiquidity → Sentry executes" });

    // Tax
    await sleep(600);
    setStep("tax");
    const tier = getTier(held);
    const baseTax = taxPercent(held, 0);
    const finalTax = taxPercent(held, BOT_CONCENTRATION_BPS);
    addLog({ type: "tax", text: `base tax: ${baseTax.toFixed(1)}% (exp(-4/600) ≈ 90%)` });
    await sleep(400);
    addLog({ type: "tax", text: `concentration score: 91% → multiplier 1.82×` });
    await sleep(400);
    addLog({ type: "tax", text: `final tax: min(90% × 1.82, 99%) = 99%      `, value: "99%" });

    const tax = Math.floor(BOT_FEES * finalTax / 100);
    const kept = BOT_FEES - tax;
    const pFee = Math.floor(tax * 0.05);
    const lpShare = tax - pFee;

    setTaxAmount(tax);
    setBotKept(kept);
    setProtocolFee(pFee);
    setLpGain(lpShare);

    await sleep(500);
    addLog({ type: "bot", text: `Bot keeps: $${kept}  (8% of original $${BOT_FEES})`, value: `$${kept}` });
    addLog({ type: "tax", text: `TaxAccumulated event emitted → $${tax}`, value: `$${tax}` });

    // Done
    await sleep(700);
    setStep("done");
    addLog({ type: "info", text: `Protocol fee (5%): $${pFee}  → Treasury` });
    await sleep(300);
    addLog({ type: "lp", text: `Redistribution to long-term LPs: $${lpShare}` });
    await sleep(400);
    addLog({ type: "lp", text: "Aisha (30-day LP): receives $180 bonus      ", value: "+$180" });
    addLog({ type: "lp", text: "Mike (7-day LP):   receives $53 bonus       ", value: "+$53" });
    addLog({ type: "info", text: "" });
    addLog({ type: "info", text: "RedistributionScheduler (Reactive Kopli):" });
    addLog({ type: "info", text: "  pool balance $2,163 > $1,000 threshold" });
    addLog({ type: "info", text: "  callback → executeRedistribution(poolId)" });
    addLog({ type: "lp", text: "Redistribution complete ✓" });

    setIsRunning(false);
  }, [addLog]);

  const reset = () => {
    setStep("idle");
    setLogs([]);
    setBotFees(0); setBotKept(0); setTaxAmount(0);
    setLpGain(0); setProtocolFee(0); setHoldSeconds(0);
  };

  const currentStepIndex = STEPS.findIndex((s) => s.id === step);
  const finalTax = holdSeconds > 0 ? taxPercent(holdSeconds, BOT_CONCENTRATION_BPS) : 0;
  const tier = getTier(holdSeconds);

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-white mb-1">JIT Attack Simulation</h1>
        <p className="text-sm text-[#555]">
          Watch Sentry neutralise a just-in-time MEV attack in real time.
        </p>
      </div>

      {/* Progress */}
      <div className="flex items-center gap-0 overflow-x-auto pb-2">
        {STEPS.map((s, i) => (
          <div key={s.id} className="flex items-center shrink-0">
            <div className={`flex flex-col items-center gap-1 ${i <= currentStepIndex ? "opacity-100" : "opacity-30"}`}>
              <div className={`w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold transition-all ${
                i < currentStepIndex ? "bg-violet-600 text-white" :
                i === currentStepIndex ? "bg-violet-500 text-white ring-2 ring-violet-500/30" :
                "bg-[#1e1e2e] text-[#555]"
              }`}>
                {i < currentStepIndex ? "✓" : i + 1}
              </div>
              <span className="text-xs text-[#666] whitespace-nowrap">{s.label}</span>
            </div>
            {i < STEPS.length - 1 && (
              <div className={`h-px w-8 mb-4 mx-1 transition-all ${i < currentStepIndex ? "bg-violet-600" : "bg-[#1e1e2e]"}`} />
            )}
          </div>
        ))}
      </div>

      <div className="grid lg:grid-cols-2 gap-6">
        {/* Left: terminal */}
        <div className="bg-[#0d0d14] border border-[#1e1e2e] rounded-xl overflow-hidden">
          <div className="flex items-center justify-between px-4 py-2.5 bg-[#111118] border-b border-[#1e1e2e]">
            <div className="flex items-center gap-2">
              <span className="w-3 h-3 rounded-full bg-red-500/70" />
              <span className="w-3 h-3 rounded-full bg-yellow-500/70" />
              <span className="w-3 h-3 rounded-full bg-green-500/70" />
              <span className="text-xs text-[#555] ml-2 font-mono">sentry-hook · unichain-sepolia</span>
            </div>
            <div className="flex gap-2">
              <button
                onClick={runSimulation}
                disabled={isRunning}
                className="px-3 py-1 bg-violet-600 hover:bg-violet-500 disabled:opacity-40 disabled:cursor-not-allowed text-white text-xs font-medium rounded transition-colors"
              >
                {isRunning ? "Running…" : step === "idle" ? "Start" : "Replay"}
              </button>
              {step !== "idle" && !isRunning && (
                <button
                  onClick={reset}
                  className="px-3 py-1 bg-[#1e1e2e] hover:bg-[#2a2a3a] text-[#888] text-xs font-medium rounded transition-colors"
                >
                  Reset
                </button>
              )}
            </div>
          </div>

          <div className="p-4 h-80 overflow-y-auto space-y-0.5 font-mono">
            {logs.length === 0 && (
              <p className="text-xs text-[#444] font-mono">
                Press Start to simulate a JIT attack on ETH/USDC pool…
              </p>
            )}
            {logs.map((log) => (
              <LogLine key={log.id} entry={log} />
            ))}
            {isRunning && (
              <span className="inline-block w-2 h-3.5 bg-[#888] animate-pulse ml-1" />
            )}
          </div>
        </div>

        {/* Right: results */}
        <div className="space-y-4">
          {/* Tax gauge */}
          <div className="bg-[#14141e] border border-[#1e1e2e] rounded-xl p-5">
            <div className="flex items-center justify-between mb-3">
              <h3 className="font-semibold text-[#ddd]">Applied Tax</h3>
              {holdSeconds > 0 && (
                <span className={`text-xs px-2 py-0.5 rounded border font-medium ${TIER_BG[tier]}`}>
                  {TIER_LABELS[tier]} · {holdSeconds}s hold
                </span>
              )}
            </div>
            <TaxGauge taxPct={finalTax} />
            <p className="text-xs text-[#555] mt-2">
              {holdSeconds === 0
                ? "Waiting for position to close…"
                : `exp(-${holdSeconds}/600) × concentration_multiplier`}
            </p>
          </div>

          {/* Scoreboard */}
          <div className="bg-[#14141e] border border-[#1e1e2e] rounded-xl p-5">
            <h3 className="font-semibold text-[#ddd] mb-4">Outcome</h3>
            <div className="space-y-3">
              <div className="flex items-center justify-between p-3 bg-[#ffffff03] rounded-lg border border-[#1a1a28]">
                <div>
                  <p className="text-sm text-[#aaa]">Bot earned</p>
                  <p className="text-xs text-[#555]">Captured 99% of swap fees</p>
                </div>
                <p className="font-mono text-sm text-[#888]">{botFees > 0 ? formatUSD(botFees) : "—"}</p>
              </div>

              <div className="flex items-center justify-between p-3 bg-red-500/5 rounded-lg border border-red-500/15">
                <div>
                  <p className="text-sm text-red-300">Bot kept (after tax)</p>
                  <p className="text-xs text-[#555]">Just {botKept > 0 ? ((botKept / botFees) * 100).toFixed(0) : "—"}% of captured fees</p>
                </div>
                <p className="font-mono font-bold text-red-400">{botKept > 0 ? formatUSD(botKept) : "—"}</p>
              </div>

              <div className="flex items-center justify-between p-3 bg-green-500/5 rounded-lg border border-green-500/15">
                <div>
                  <p className="text-sm text-green-300">Long-term LPs received</p>
                  <p className="text-xs text-[#555]">Redistribution from tax capture</p>
                </div>
                <p className="font-mono font-bold text-green-400">{lpGain > 0 ? formatUSD(lpGain) : "—"}</p>
              </div>

              <div className="flex items-center justify-between p-3 bg-[#ffffff03] rounded-lg border border-[#1a1a28]">
                <div>
                  <p className="text-sm text-violet-300">Protocol fee (5%)</p>
                  <p className="text-xs text-[#555]">To Treasury</p>
                </div>
                <p className="font-mono text-sm text-violet-400">{protocolFee > 0 ? formatUSD(protocolFee) : "—"}</p>
              </div>
            </div>
          </div>

          {step === "done" && (
            <div className="bg-green-500/5 border border-green-500/20 rounded-xl p-4 text-sm">
              <p className="font-semibold text-green-400 mb-1">Attack neutralised ✓</p>
              <p className="text-[#888]">
                Bot expected <span className="font-mono text-white">{formatUSD(BOT_FEES)}</span>.
                Got <span className="font-mono text-red-400">{formatUSD(botKept)}</span>.
                Long-term LPs gained <span className="font-mono text-green-400">{formatUSD(lpGain)}</span>{" "}
                they would have lost.
              </p>
            </div>
          )}
        </div>
      </div>

      {/* Tax curve context */}
      <div className="bg-[#14141e] border border-[#1e1e2e] rounded-xl p-5">
        <h3 className="font-semibold text-[#ddd] mb-1">Tax Curve — where this attack falls</h3>
        <p className="text-xs text-[#555] mb-4">
          A 4-second position is at the very left. Even a 30-minute hold would pay ~11%.
        </p>
        <TaxCurveChart height={160} showTiers />
      </div>
    </div>
  );
}
