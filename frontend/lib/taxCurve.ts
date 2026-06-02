// Mirror of the Solidity TaxCurve logic for client-side rendering

const HALF_LIFE = 600; // 10 minutes
const MAX_TAX_BPS = 6500;
const TABLE_DOMAIN = HALF_LIFE * 10; // 6000 seconds

// exp(-k) for k = 0..10
const EXP_TABLE = [
  1.0,
  0.36787944117144232,
  0.13533528323661270,
  0.04978706836786395,
  0.01831563888873418,
  0.00673794699908547,
  0.00247875217666602,
  0.00091188214932116,
  0.00033546262790251,
  0.00012340980408652,
  0.0,
];

function expApprox(t: number): number {
  if (t >= TABLE_DOMAIN) return 0;
  const k = Math.floor(t / HALF_LIFE);
  const remainder = t % HALF_LIFE;
  const lo = EXP_TABLE[k];
  const hi = EXP_TABLE[k + 1] ?? 0;
  return lo - ((lo - hi) * remainder) / HALF_LIFE;
}

export function calculateTaxBps(timeHeldSeconds: number): number {
  return Math.floor(MAX_TAX_BPS * expApprox(timeHeldSeconds));
}

export function calculateFinalTaxBps(timeHeldSeconds: number, concentrationBps: number): number {
  const base = calculateTaxBps(timeHeldSeconds);
  if (base === 0) return 0;

  let multiplierBps = 10000;
  if (concentrationBps > 5000) {
    multiplierBps = 10000 + (concentrationBps - 5000) * 2;
  }

  const final = Math.floor((base * multiplierBps) / 10000);
  return Math.min(6500, final);
}

export function taxPercent(timeHeldSeconds: number, concentrationBps = 0): number {
  return calculateFinalTaxBps(timeHeldSeconds, concentrationBps) / 100;
}

// Generate points for the tax curve chart
export function generateCurvePoints(points = 120): Array<{ t: number; tax: number; label: string }> {
  const result = [];
  for (let i = 0; i <= points; i++) {
    const t = (i / points) * TABLE_DOMAIN;
    const tax = calculateTaxBps(t) / 100;
    let label: string;
    if (t < 60) label = `${Math.round(t)}s`;
    else if (t < 3600) label = `${Math.round(t / 60)}m`;
    else label = `${(t / 3600).toFixed(1)}h`;
    result.push({ t, tax, label });
  }
  return result;
}
