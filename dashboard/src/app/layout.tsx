import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'LexEscrow - Matter Management Dashboard',
  description: 'Compliance-Gated Smart Contracts for Legal Escrow',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="bg-slate-950 text-slate-100 min-h-screen">
        <nav className="border-b border-slate-800 px-6 py-4">
          <div className="max-w-7xl mx-auto flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className="w-8 h-8 bg-cyan-500/20 rounded-lg flex items-center justify-center">
                <span className="text-cyan-400 font-bold text-sm">LE</span>
              </div>
              <h1 className="text-lg font-semibold text-white">LexEscrow</h1>
              <span className="text-xs text-slate-500 border border-slate-700 rounded px-2 py-0.5 ml-2">v0.1.0</span>
            </div>
            <div className="flex items-center gap-4 text-sm text-slate-400">
              <a href="/" className="hover:text-white transition-colors">Active Matters</a>
              <a href="/audit" className="hover:text-white transition-colors">Audit Trail</a>
              <div className="w-8 h-8 bg-slate-800 rounded-full flex items-center justify-center text-cyan-400 text-xs font-bold">JP</div>
            </div>
          </div>
        </nav>
        <main className="max-w-7xl mx-auto px-6 py-8">{children}</main>
      </body>
    </html>
  );
}
