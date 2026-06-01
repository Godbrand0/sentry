import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import Link from "next/link";
import "./globals.css";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

export const metadata: Metadata = {
  title: "Sentry — Anti-JIT LP Protection",
  description: "Uniswap V4 hook that defends long-term LPs from JIT MEV extraction",
};

function NavLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <Link
      href={href}
      className="px-3 py-1.5 text-sm text-[#888] hover:text-white hover:bg-[#ffffff08] rounded-md transition-colors"
    >
      {children}
    </Link>
  );
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${geistSans.variable} ${geistMono.variable}`}>
      <body className="min-h-screen flex flex-col">
        <nav className="border-b border-[#1e1e2e] bg-[#0a0a0e]/80 backdrop-blur-sm sticky top-0 z-50">
          <div className="max-w-7xl mx-auto px-4 h-14 flex items-center justify-between">
            <Link href="/" className="flex items-center gap-2.5">
              <div className="w-7 h-7 rounded-lg bg-gradient-to-br from-violet-500 to-indigo-600 flex items-center justify-center text-white text-xs font-bold">
                S
              </div>
              <span className="font-semibold text-white tracking-tight">Sentry</span>
              <span className="text-xs text-[#555] border border-[#1e1e2e] rounded px-1.5 py-0.5 ml-1">
                Unichain Sepolia
              </span>
            </Link>

            <div className="flex items-center gap-1">
              <NavLink href="/">Dashboard</NavLink>
              <NavLink href="/jit-demo">JIT Demo</NavLink>
              <NavLink href="/lp/0xAisha">My LP</NavLink>
            </div>

            <div className="flex items-center gap-2">
              <div className="flex items-center gap-1.5 text-xs text-[#555]">
                <span className="w-1.5 h-1.5 rounded-full bg-green-400 animate-pulse inline-block" />
                Live
              </div>
            </div>
          </div>
        </nav>

        <main className="flex-1 max-w-7xl mx-auto w-full px-4 py-8">
          {children}
        </main>

        <footer className="border-t border-[#1e1e2e] py-4 text-center text-xs text-[#444]">
          Sentry · Uniswap Hook Incubator · Powered by{" "}
          <span className="text-[#666]">Reactive Network</span>
        </footer>
      </body>
    </html>
  );
}
