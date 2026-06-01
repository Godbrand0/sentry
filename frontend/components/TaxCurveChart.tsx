"use client";

import dynamic from "next/dynamic";
import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ReferenceLine,
  ResponsiveContainer,
} from "recharts";
import { generateCurvePoints } from "@/lib/taxCurve";

const data = generateCurvePoints(200);

interface CustomTooltipProps {
  active?: boolean;
  payload?: Array<{ value: number }>;
  label?: string;
}

function CustomTooltip({ active, payload, label }: CustomTooltipProps) {
  if (!active || !payload?.length) return null;
  return (
    <div className="bg-[#1a1a2e] border border-[#2a2a40] rounded-lg px-3 py-2 text-sm shadow-xl">
      <p className="text-[#888] mb-1">{label}</p>
      <p className="text-white font-mono font-semibold">{payload[0].value.toFixed(1)}% tax</p>
    </div>
  );
}

interface TaxCurveChartProps {
  height?: number;
  showTiers?: boolean;
}

function TaxCurveChartInner({ height = 240, showTiers = true }: TaxCurveChartProps) {
  return (
    <div style={{ height }} className="w-full">
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={data} margin={{ top: 8, right: 16, left: 0, bottom: 0 }}>
          <defs>
            <linearGradient id="taxGrad" x1="0" y1="0" x2="1" y2="0">
              <stop offset="0%" stopColor="#ef4444" />
              <stop offset="15%" stopColor="#f97316" />
              <stop offset="35%" stopColor="#eab308" />
              <stop offset="60%" stopColor="#22c55e" />
              <stop offset="100%" stopColor="#16a34a" />
            </linearGradient>
            <linearGradient id="taxFill" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#6366f1" stopOpacity={0.3} />
              <stop offset="100%" stopColor="#6366f1" stopOpacity={0.02} />
            </linearGradient>
          </defs>

          <CartesianGrid strokeDasharray="3 3" stroke="#1e1e30" vertical={false} />

          <XAxis
            dataKey="label"
            ticks={["0s", "1m", "5m", "10m", "30m", "1h", "1.7h"]}
            tick={{ fill: "#555", fontSize: 11 }}
            axisLine={false}
            tickLine={false}
          />

          <YAxis
            domain={[0, 90]}
            tickFormatter={(v) => `${v}%`}
            tick={{ fill: "#555", fontSize: 11 }}
            axisLine={false}
            tickLine={false}
            width={36}
          />

          <Tooltip content={<CustomTooltip />} />

          {showTiers && (
            <>
              <ReferenceLine
                x="1m"
                stroke="#ef4444"
                strokeDasharray="4 4"
                strokeOpacity={0.5}
                label={{ value: "JIT", fill: "#ef4444", fontSize: 10, position: "insideTopLeft" }}
              />
              <ReferenceLine
                x="1h"
                stroke="#eab308"
                strokeDasharray="4 4"
                strokeOpacity={0.5}
                label={{ value: "Short", fill: "#eab308", fontSize: 10, position: "insideTopLeft" }}
              />
            </>
          )}

          <Area
            type="monotone"
            dataKey="tax"
            stroke="url(#taxGrad)"
            strokeWidth={2.5}
            fill="url(#taxFill)"
            dot={false}
            activeDot={{ r: 4, fill: "#6366f1", strokeWidth: 0 }}
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}

// Lazy-load so ResponsiveContainer skips SSR measurement
const TaxCurveChart = dynamic(() => Promise.resolve(TaxCurveChartInner), { ssr: false });
export default TaxCurveChart;
