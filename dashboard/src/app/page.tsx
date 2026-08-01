"use client";

import { useState } from 'react';

// ── Types ──
type EscrowStatus = 'Active' | 'PendingCompliance' | 'Cleared' | 'Released' | 'Blocked' | 'Cancelled';
type ComplianceStatus = 'CLEARED' | 'BLOCKED' | 'PENDING';

interface EscrowMatter {
  id: string;
  clientName: string;
  recipientName: string;
  amount: string;
  jurisdiction: string;
  status: EscrowStatus;
  complianceStatus: ComplianceStatus;
  riskScore: number;
  txHash: string | null;
  attestationHash: string | null;
  createdAt: string;
}

// ── Demo Data ──
const DEMO_MATTERS: EscrowMatter[] = [
  {
    id: 'ESC-2026-001',
    clientName: 'Kirkland & Ellis LLP',
    recipientName: 'Meridian Capital Holdings',
    amount: '$12,500,000.00',
    jurisdiction: 'US',
    status: 'Released',
    complianceStatus: 'CLEARED',
    riskScore: 0,
    txHash: '5Kj8n2vXmQp9rLs1tUw3yA4bC6dE7fG8hI9jK0lM1n',
    attestationHash: 'AtT3sT7kH4sH',
    createdAt: '2026-05-20T14:30:00Z',
  },
  {
    id: 'ESC-2026-002',
    clientName: 'Latham & Watkins LLP',
    recipientName: 'Global Infrastructure Partners III',
    amount: '$47,200,000.00',
    jurisdiction: 'UK',
    status: 'PendingCompliance',
    complianceStatus: 'PENDING',
    riskScore: 0,
    txHash: null,
    attestationHash: null,
    createdAt: '2026-07-30T09:15:00Z',
  },
  {
    id: 'ESC-2026-003',
    clientName: 'Clifford Chance LLP',
    recipientName: 'Nordic Shipping AS',
    amount: '$8,750,000.00',
    jurisdiction: 'EU',
    status: 'Blocked',
    complianceStatus: 'BLOCKED',
    riskScore: 45,
    txHash: null,
    attestationHash: null,
    createdAt: '2026-07-28T16:45:00Z',
  },
  {
    id: 'ESC-2026-004',
    clientName: 'Davis Polk & Wardwell LLP',
    recipientName: 'Apex Ventures Fund II LP',
    amount: '$23,000,000.00',
    jurisdiction: 'US',
    status: 'Active',
    complianceStatus: 'PENDING',
    riskScore: 0,
    txHash: null,
    attestationHash: null,
    createdAt: '2026-07-31T10:00:00Z',
  },
];

// ── Status Badges ──
function StatusBadge({ status }: { status: EscrowStatus }) {
  const styles: Record<EscrowStatus, string> = {
    Active: 'bg-slate-700 text-slate-300',
    PendingCompliance: 'bg-amber-900/50 text-amber-400 border-amber-700',
    Cleared: 'bg-cyan-900/50 text-cyan-400 border-cyan-700',
    Released: 'bg-emerald-900/50 text-emerald-400 border-emerald-700',
    Blocked: 'bg-red-900/50 text-red-400 border-red-700',
    Cancelled: 'bg-slate-800 text-slate-500',
  };
  return (
    <span className={`px-2.5 py-1 rounded text-xs font-medium border ${styles[status]}`}>
      {status.replace(/([A-Z])/g, ' $1').trim()}
    </span>
  );
}

// ── Compliance Icon ──
function ComplianceIcon({ status, riskScore, onClick }: { status: ComplianceStatus; riskScore: number; onClick?: () => void }) {
  if (status === 'CLEARED') {
    return (
      <button onClick={onClick} className="flex items-center gap-2 text-emerald-400 hover:text-emerald-300 transition-colors" title="View Attestation">
        <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
        <span className="text-xs font-medium">CLEARED</span>
      </button>
    );
  }
  if (status === 'BLOCKED') {
    return (
      <button onClick={onClick} className="flex items-center gap-2 text-red-400 hover:text-red-300 transition-colors" title="View Block Details">
        <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
        </svg>
        <span className="text-xs font-medium">BLOCKED ({riskScore})</span>
      </button>
    );
  }
  return (
    <div className="flex items-center gap-2 text-amber-400">
      <div className="w-5 h-5 border-2 border-amber-400 border-t-transparent rounded-full animate-spin" />
      <span className="text-xs font-medium">PENDING</span>
    </div>
  );
}

// ── Attestation Modal ──
function AttestationModal({ matter, onClose }: { matter: EscrowMatter; onClose: () => void }) {
  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 p-4" onClick={onClose}>
      <div className="bg-slate-900 border border-slate-700 rounded-xl max-w-2xl w-full p-6" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between mb-6">
          <h3 className="text-lg font-semibold">Compliance Attestation</h3>
          <button onClick={onClose} className="text-slate-400 hover:text-white">&times;</button>
        </div>

        {matter.complianceStatus === 'CLEARED' && (
          <div className="space-y-4">
            <div className="bg-emerald-900/20 border border-emerald-800 rounded-lg p-4">
              <div className="flex items-center gap-2 mb-2">
                <svg className="w-5 h-5 text-emerald-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                <span className="text-emerald-400 font-semibold">Entity Cleared</span>
              </div>
              <p className="text-slate-300 text-sm">
                AI compliance sweep confirmed no sanctions, PEP status, or adverse media
                for <strong>{matter.recipientName}</strong> in jurisdiction <strong>{matter.jurisdiction}</strong>.
              </p>
            </div>

            <div className="grid grid-cols-2 gap-4 text-sm">
              <div>
                <div className="text-slate-500 text-xs mb-1">Risk Score</div>
                <div className="text-emerald-400 font-bold">0 / 100</div>
              </div>
              <div>
                <div className="text-slate-500 text-xs mb-1">Checked At</div>
                <div className="text-white">2026-05-20 14:32:18 UTC</div>
              </div>
              <div>
                <div className="text-slate-500 text-xs mb-1">Sources Queried</div>
                <div className="text-white">5 regulatory databases</div>
              </div>
              <div>
                <div className="text-slate-500 text-xs mb-1">Tavily AI Summary</div>
                <div className="text-white">No adverse information found.</div>
              </div>
            </div>

            <div className="bg-slate-800 rounded-lg p-4 mt-4">
              <div className="text-slate-500 text-xs mb-1">On-Chain Attestation Hash</div>
              <div className="text-cyan-400 font-mono text-xs break-all">{matter.attestationHash || '0x...'}</div>
              <div className="text-slate-500 text-xs mt-2 mb-1">Transaction Hash</div>
              <div className="text-cyan-400 font-mono text-xs break-all">{matter.txHash || '0x...'}</div>
            </div>

            <p className="text-slate-500 text-xs mt-4">
              This attestation is permanently recorded on the Solana blockchain and can be
              verified by any auditor or regulator via the transaction hash above.
            </p>
          </div>
        )}

        {matter.complianceStatus === 'BLOCKED' && (
          <div className="space-y-4">
            <div className="bg-red-900/20 border border-red-800 rounded-lg p-4">
              <div className="flex items-center gap-2 mb-2">
                <svg className="w-5 h-5 text-red-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                </svg>
                <span className="text-red-400 font-semibold">Entity Blocked - Risk Score: {matter.riskScore}/100</span>
              </div>
              <p className="text-slate-300 text-sm">
                The AI compliance sweep identified potential sanctions or adverse media
                for <strong>{matter.recipientName}</strong> in jurisdiction <strong>{matter.jurisdiction}</strong>.
                Funds have been hard-blocked pending partner review.
              </p>
            </div>
            <button className="w-full bg-slate-800 hover:bg-slate-700 text-white py-2 px-4 rounded-lg text-sm">
              Escalate to Senior Partner
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

// ═══ Main Page ═══
export default function MatterManagement() {
  const [selectedMatter, setSelectedMatter] = useState<EscrowMatter | null>(null);

  return (
    <div>
      {/* Header Stats */}
      <div className="grid grid-cols-4 gap-4 mb-8">
        <StatCard label="Active Matters" value="4" color="cyan" />
        <StatCard label="Total Escrowed" value="$91.5M" color="blue" />
        <StatCard label="Compliance Clear Rate" value="98.2%" color="emerald" />
        <StatCard label="Avg. Check Time" value="4.2s" color="amber" />
      </div>

      {/* Matters Table */}
      <div className="border border-slate-800 rounded-xl overflow-hidden">
        <div className="px-6 py-4 border-b border-slate-800 flex items-center justify-between">
          <h2 className="text-base font-semibold">Active Matters / Escrows</h2>
          <button className="bg-cyan-600 hover:bg-cyan-500 text-white text-sm px-4 py-2 rounded-lg transition-colors">
            + New Escrow
          </button>
        </div>
        <table className="w-full">
          <thead>
            <tr className="text-xs text-slate-500 border-b border-slate-800">
              <th className="text-left px-6 py-3 font-medium">Escrow ID</th>
              <th className="text-left px-4 py-3 font-medium">Client / Firm</th>
              <th className="text-left px-4 py-3 font-medium">Recipient</th>
              <th className="text-right px-4 py-3 font-medium">Amount</th>
              <th className="text-center px-4 py-3 font-medium">Jurisdiction</th>
              <th className="text-center px-4 py-3 font-medium">Milestone Status</th>
              <th className="text-center px-4 py-3 font-medium">AI Compliance</th>
              <th className="text-right px-6 py-3 font-medium">Tx Hash</th>
            </tr>
          </thead>
          <tbody>
            {DEMO_MATTERS.map((matter) => (
              <tr key={matter.id} className="border-b border-slate-800/50 hover:bg-slate-900/50 transition-colors">
                <td className="px-6 py-3 text-cyan-400 font-mono text-xs">{matter.id}</td>
                <td className="px-4 py-3 text-sm text-white">{matter.clientName}</td>
                <td className="px-4 py-3 text-sm text-slate-300">{matter.recipientName}</td>
                <td className="px-4 py-3 text-sm text-white text-right font-mono">{matter.amount}</td>
                <td className="px-4 py-3 text-center">
                  <span className="px-2 py-0.5 bg-slate-800 text-slate-300 rounded text-xs">{matter.jurisdiction}</span>
                </td>
                <td className="px-4 py-3 text-center">
                  <StatusBadge status={matter.status} />
                </td>
                <td className="px-4 py-3 text-center">
                  <ComplianceIcon
                    status={matter.complianceStatus}
                    riskScore={matter.riskScore}
                    onClick={() => setSelectedMatter(matter)}
                  />
                </td>
                <td className="px-6 py-3 text-right">
                  {matter.txHash ? (
                    <span className="text-cyan-500/60 font-mono text-xs" title={matter.txHash}>
                      {matter.txHash.slice(0, 10)}...
                    </span>
                  ) : (
                    <span className="text-slate-600 text-xs">--</span>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Attestation Modal */}
      {selectedMatter && (
        <AttestationModal matter={selectedMatter} onClose={() => setSelectedMatter(null)} />
      )}
    </div>
  );
}

// ── Stat Card ──
function StatCard({ label, value, color }: { label: string; value: string; color: string }) {
  const colors: Record<string, string> = {
    cyan: 'text-cyan-400',
    blue: 'text-blue-400',
    emerald: 'text-emerald-400',
    amber: 'text-amber-400',
  };
  return (
    <div className="bg-slate-900 border border-slate-800 rounded-xl p-5">
      <div className={`text-2xl font-bold ${colors[color]}`}>{value}</div>
      <div className="text-xs text-slate-500 mt-1">{label}</div>
    </div>
  );
}
