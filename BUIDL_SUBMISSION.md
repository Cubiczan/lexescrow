# LexEscrow — BUIDL Submission

**Compliance-Gated Smart Contracts for Legal Escrow**

BUIDL Legal Hack 2026 | DoraHacks | BLI Track (Blockchain + Finance + Compliance)

---

## 1. Vision

AI-compliance-gated escrow on Solana: funds lock on-chain, an oracle screens recipients against OFAC/PEP/AML in real-time, and only a CLEARED attestation releases them — giving law firms an immutable audit trail at the moment of fund movement.

---

## 2. The Problem

### The $4.7 Trillion Blind Spot in Legal Finance

Every year, over $4.7 trillion in cross-border legal settlements — M&A closings, litigation payouts, regulatory fines, fund formations, and trust distributions — move through the global financial system. These transactions are managed by large law firms acting as settlement agents, holding funds in escrow until all conditions are met before releasing them to the designated recipients.

The final step before fund release is a compliance check: verifying that the receiving entity is not on any sanctions list (OFAC SDN, EU Consolidated List, UN Security Council), is not a Politically Exposed Person (PEP), and has no adverse media or AML red flags. This check is critical — failure to screen can result in severe regulatory penalties, including fines up to $1 million per violation under the International Emergency Economic Powers Act (IEEPA), criminal prosecution of responsible officers, and reputational destruction.

### Why Current Solutions Fail

**Manual, static checks.** Most law firms perform compliance screening using static databases that are updated daily or weekly. Between the time the check is completed and the wire transfer executes — a window that can span hours or even days — a sanctions list may update. A new designation, a PEP change, or an adverse media report can appear in that gap, and the firm would have no way to know. The compliance check becomes stale the instant it is completed.

**No immutable audit trail.** When a law firm performs a manual KYC/AML check, the result exists as a PDF report in a file system or an email attachment. There is no cryptographic proof that the check was performed, what parameters were used, what the result was, or when exactly it occurred. If a regulator asks for evidence three years later, the firm must rely on its own record-keeping — which may be incomplete, tampered with, or lost.

**Fragmented workflows.** The escrow release process typically involves multiple parties: the settling parties, their counsel, the escrow agent, compliance officers, and operations teams. Each uses different systems — email, spreadsheets, banking portals, case management software. There is no unified system that connects the multi-party approval workflow with the compliance check and the actual fund movement. This fragmentation creates opportunities for errors, unauthorized releases, and compliance gaps.

**No real-time risk intelligence.** Traditional compliance checks rely on databases of known bad actors. They do not incorporate real-time signals — breaking news about a recipient's involvement in money laundering, regulatory actions in foreign jurisdictions, or emerging patterns of financial crime. By the time a traditional database catches up, the funds may have already moved.

### The Consequence

In 2024 alone, global financial regulators imposed over $6.6 billion in AML/KYC-related penalties. Large law firms are increasingly in the crosshairs because they sit at the critical junction where compliance verification meets fund movement. Without an automated, immutable, real-time compliance checkpoint, every escrow release is a liability.

---

## 3. The Solution

LexEscrow bridges legal operations with Web3 infrastructure to create a compliance-gated escrow system that eliminates the blind spot between compliance verification and fund release.

### How It Works

**1. On-Chain Fund Custody.** When a legal matter requires an escrow (e.g., an M&A closing with a $50 million purchase price), the funds are locked in a Solana smart contract using a PDA (Program Derived Address) vault. This vault is cryptographically derived from the escrow account, meaning no single party controls it. The funds cannot move without the smart contract's explicit instruction.

**2. Multi-Sig Approval.** Release requires approval from designated parties — typically the legal counsel for each side plus the escrow agent. The smart contract enforces a multi-signature requirement: at least two approvals are needed before the release process can proceed. Each approval is an on-chain transaction, permanently recorded and timestamped.

**3. The Compliance Gate.** Here is where LexEscrow fundamentally differs from every other escrow solution. When the multi-sig threshold is met, the contract does NOT release the funds. Instead, it transitions to a `PendingCompliance` state and emits an `EscrowApproved` event. This event is the trigger for the compliance check — it is the moment of maximum regulatory risk, and LexEscrow ensures it is also the moment of maximum regulatory protection.

**4. AI-Powered Compliance Oracle.** A Solana WebSocket event listener picks up the `EscrowApproved` event and immediately calls the LexEscrow Compliance Oracle — a FastAPI service powered by Tavily AI's OSINT (Open-Source Intelligence) capabilities. The oracle performs a comprehensive real-time screening of the receiving entity:

- **OFAC SDN Screening (40% weight):** Checks the US Treasury's Specially Designated Nationals list, including any updates published in the last 24 hours.
- **PEP Database Check (25% weight):** Screens against international Politically Exposed Person databases, including relatives and close associates.
- **AML Keyword Analysis (20% weight):** Analyzes the entity's public web presence for AML red flags using keyword pattern matching against a curated list of financial crime indicators.
- **AI OSINT Sweep (15% weight):** Uses Tavily AI to perform real-time web search, analyzing news articles, regulatory filings, and public records for adverse information about the entity.

Each check produces a risk score. The scores are combined using a weighted algorithm to produce a composite risk score on a 0-100 scale. Entities scoring below 50 receive a `CLEARED` status; those scoring 50 or above receive a `BLOCKED` status.

**5. On-Chain Attestation.** The oracle's result — `CLEARED` or `BLOCKED`, along with the composite risk score — is SHA-256 hashed and submitted back to the Solana blockchain as a compliance attestation. This attestation is immutable, timestamped, and publicly verifiable. It serves as cryptographic proof that compliance screening was performed at the exact moment of fund release.

**6. Automated Fund Release.** If the attestation is `CLEARED`, the smart contract allows the `release_funds` instruction to execute. The SOL is transferred from the PDA vault to the recipient's wallet using Solana's `invoke_signed` mechanism, which allows the program to sign on behalf of the PDA. If the attestation is `BLOCKED`, the release is permanently hard-blocked. The funds remain in the vault, and the parties must investigate and resolve the compliance concern before any further action can be taken.

### Why This Matters

- **No stale checks.** Compliance screening happens at the exact moment of release, not hours or days before.
- **Immutable proof.** The on-chain attestation is cryptographic evidence that cannot be altered, backdated, or forged.
- **Real-time intelligence.** AI-powered OSINT provides current risk signals that static databases miss.
- **Zero trust architecture.** No single party controls the funds. The PDA vault requires program-level authorization.
- **Regulatory alignment.** The system produces the exact evidence that regulators demand: who was checked, when, against what sources, and what the result was.

---

## 4. Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         LEXESCROW SYSTEM                                │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌────────────────┐         ┌─────────────────────────────────────┐      │
│  │  Matter Mgmt   │         │       SOLANA BLOCKCHAIN             │      │
│  │  Dashboard     │         │                                     │      │
│  │  (Next.js)     │<───────>│  ┌──────────────────────────────┐  │      │
│  │                │         │  │  LexEscrow Smart Contract     │  │      │
│  │  - Active      │         │  │  (Anchor 0.30.0 / Rust)       │  │      │
│  │    Escrows     │         │  │                              │  │      │
│  │  - Attestation │         │  │  - create_escrow()           │  │      │
│  │    Modal       │         │  │  - approve_release()          │  │      │
│  │  - Status      │         │  │  - submit_attestation()       │  │      │
│  │    Pipeline    │         │  │  - release_funds()            │  │      │
│  │  - Wallet      │         │  │  - cancel_escrow()            │  │      │
│  │    Connect     │         │  │                              │  │      │
│  └────────────────┘         │  │  PDA Vault: Escrow Funds     │  │      │
│                              │  └──────────────┬───────────────┘  │      │
│                              │                 │                    │      │
│                              │        ┌────────┴────────┐          │      │
│                              │        │  Events          │          │      │
│                              │        │  EscrowApproved  │          │      │
│                              │        └────────┬────────┘          │      │
│                              └─────────────────┼──────────────────┘      │
│                                                │                          │
│                                                │ WebSocket                │
│                                                │                          │
│                              ┌─────────────────┼──────────────────┐      │
│                              │  Event Listener │                   │      │
│                              │  (Node.js)      │                   │      │
│                              │                 │                   │      │
│                              │  Watches logs ──┘                   │      │
│                              │  Calls oracle                       │      │
│                              │  Submits attestation                │      │
│                              └────────┬────────────────────────────┘      │
│                                       │                                   │
│                                       │ HTTP POST                         │
│                                       │                                   │
│                              ┌────────┴────────────────────────────┐      │
│                              │  Compliance Oracle                  │      │
│                              │  (FastAPI / Python)                 │      │
│                              │                                      │      │
│                              │  ┌─────────────────────────────┐   │      │
│                              │  │  OFAC SDN Screen    [40%]   │   │      │
│                              │  │  PEP Database Check  [25%]   │   │      │
│                              │  │  AML Keywords        [20%]   │   │      │
│                              │  │  AI OSINT (Tavily)   [15%]   │   │      │
│                              │  └─────────────────────────────┘   │      │
│                              │                                      │      │
│                              │  Weighted Risk Score → CLEARED/     │      │
│                              │  BLOCKED → SHA-256 Hashed Result   │      │
│                              └──────────────────────────────────────┘      │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

### Fund Release State Machine

```
                         create_escrow()
                              │
                              ▼
                       ┌──────────────┐
                       │   Created    │  Funds locked in PDA vault
                       └──────┬───────┘
                              │
                    approve_release() [1st sig]
                              │
                              ▼
                     ┌──────────────────┐
                     │  PendingApproval  │  Waiting for 2nd approval
                     └──────┬───────────┘
                            │
                 approve_release() [2nd sig]
                            │
                            ▼
                  ┌───────────────────┐
                  │ PendingCompliance │  ⚡ Event emitted → Oracle triggered
                  └──────┬────────────┘
                         │
              submit_attestation(CLEARED)
                         │
                         ▼
                 ┌───────────────┐
                 │ ReadyToRelease │  Compliance proven on-chain
                 └──────┬────────┘
                        │
               release_funds()
                        │
                        ▼
                 ┌───────────────┐
                 │   Released    │  SOL transferred to recipient
                 └───────────────┘

              OR (if BLOCKED):

                  ┌───────────────┐
                  │   Blocked     │  Hard-blocked, funds remain locked
                  └───────────────┘
```

---

## 5. Smart Contract Deep Dive

### PDA Vault Architecture

The escrow vault is a Program Derived Address derived from the seeds `[b"vault", escrow.key().as_ref()]`. This means:

- The vault is owned by the LexEscrow program, not by any individual wallet.
- No external party can sign transactions on behalf of the vault.
- The program uses `invoke_signed` with the vault's PDA seeds to authorize SOL transfers.
- Even the program deployer cannot directly access the vault funds.

### Account Structure

```rust
#[account]
pub struct Escrow {
    pub depositor: Pubkey,        // Who funded the escrow
    pub recipient: Pubkey,        // Who receives the funds
    pub approver1: Pubkey,        // First required approver
    pub approver2: Pubkey,        // Second required approver
    pub amount: u64,               // SOL amount in lamports
    pub status: EscrowStatus,      // Current state in the FSM
    pub compliance_hash: [u8; 32], // SHA-256 of compliance result
    pub compliance_status: Option<ComplianceStatus>, // CLEARED or BLOCKED
    pub vault_bump: u8,            // PDA bump for vault derivation
    pub created_at: i64,           // Unix timestamp
}
```

### Security Properties

- **Multi-sig enforcement:** The `approve_release` instruction verifies that the signer is one of the two designated approvers and that each approver can only approve once.
- **Compliance gate:** `release_funds` checks that `compliance_status == CLEARED` before executing the transfer. There is no bypass.
- **PDA signing:** Fund transfer uses `invoke_signed` with the vault PDA, ensuring the program itself authorizes the movement.
- **Cancel protection:** Only the original depositor can cancel, and only when the escrow is in `Created` or `PendingApproval` state — preventing cancellation after compliance screening has begun.
- **Attestation integrity:** The compliance hash is stored on-chain, allowing anyone to verify the oracle's result against the original screening data.

### Test Coverage

The 5-test integration suite covers the complete escrow lifecycle:

1. **Create Escrow** — Verifies PDA vault derivation, SOL deposit, and initial `Created` state.
2. **First Approval** — Verifies transition to `PendingApproval`, approver cannot approve twice.
3. **Second Approval** — Verifies transition to `PendingCompliance` and `EscrowApproved` event emission.
4. **Submit CLEARED Attestation** — Verifies on-chain attestation storage, transition to `ReadyToRelease`.
5. **Release Funds** — Verifies SOL transfer from PDA vault to recipient, final `Released` state.

---

## 6. Compliance Oracle Deep Dive

### Weighted Risk Scoring Algorithm

The oracle combines four independent screening checks into a single composite risk score:

```
Composite Score = (OFAC × 0.40) + (PEP × 0.25) + (AML × 0.20) + (OSINT × 0.15)
```

Each component returns a score from 0 (no risk) to 100 (maximum risk):

| Check | Score 0 (Clean) | Score 100 (High Risk) | Weight |
|-------|-----------------|----------------------|--------|
| **OFAC SDN** | Entity not found on any sanctions list | Entity is on OFAC SDN list with active blocking | 40% |
| **PEP** | No political exposure found | Current head of state or central bank governor | 25% |
| **AML Keywords** | No financial crime keywords in public records | Multiple AML red flags including "money laundering", "sanctions evasion" | 20% |
| **AI OSINT** | No adverse media, clean news profile | Active investigations, regulatory actions, or criminal proceedings | 15% |

### Thresholds

- **Score < 50:** `CLEARED` — Attestation submitted on-chain, fund release authorized.
- **Score >= 50:** `BLOCKED` — Attestation submitted on-chain, fund release permanently blocked.

### SHA-256 Attestation Hash

The compliance result is hashed using SHA-256 before submission:

```python
attestation_data = f"{entity}|{composite_score}|{ofac_score}|{pep_score}|{aml_score}|{osint_score}|{timestamp}"
hash = hashlib.sha256(attestation_data.encode()).hexdigest()
```

This hash is stored on-chain in the escrow account's `compliance_hash` field, creating a tamper-proof link between the off-chain screening and the on-chain record.

### Offline Testing

The oracle includes offline mock tests that validate:
- Clean entity ("Acme Corporation") receives `CLEARED` with low score.
- Blocked entity ("Test Sanctions Target") receives `BLOCKED` with high score.
- On-chain attestation data format validation (correct SHA-256 hash structure).

---

## 7. Event Listener

### Real-Time Event Processing

The event listener maintains a persistent WebSocket connection to the Solana blockchain, subscribing to logs from the LexEscrow program. When an `EscrowApproved` event is detected (indicating the escrow has entered `PendingCompliance` state), the listener:

1. **Extracts the escrow public key** from the event's account data.
2. **Calls the compliance oracle** via HTTP POST to `/check/{entity}`, passing the recipient's address.
3. **Submits the attestation** back on-chain by invoking the `submit_attestation` instruction with the oracle's CLEARED/BLOCKED result.

This creates a fully autonomous compliance loop: approval → screening → attestation → (release or block) — with zero human intervention.

---

## 8. Matter Management Dashboard

### Design Philosophy

The dashboard is built for legal operations professionals, not crypto natives. It uses the language and workflows that large law firm teams understand:

- **Matters** instead of "transactions" or "smart contracts"
- **Attestations** instead of "oracle responses"
- **Compliance Status** instead of "risk scores"
- **Parties** instead of "wallet addresses"

### Features

- **Active Escrows Table:** Real-time view of all open escrows with status badges (Created → PendingApproval → PendingCompliance → ReadyToRelease → Released).
- **Attestation Modal:** One-click compliance attestation submission for manual override or re-screening.
- **Matter Details:** Complete view of escrow parameters — parties, SOL amount, approval status, compliance result.
- **Wallet Connection:** Solana wallet-adapter integration for authorized users.
- **Responsive Design:** Tailwind CSS ensures the dashboard works on desktop and tablet.

---

## 9. Tech Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **Smart Contract** | Solana, Anchor 0.30.0, Rust | On-chain escrow with PDA vaults and compliance gate |
| **Compliance** | FastAPI, Python 3.11+, Tavily AI | Real-time OFAC/PEP/AML/OSINT screening with weighted scoring |
| **Event Processing** | Node.js, Solana WebSocket | Autonomous event-driven compliance loop |
| **Frontend** | Next.js, React, Tailwind CSS | Legal-ops-friendly Matter Management UI |
| **Security** | PDA-derived vaults, Multi-sig, SHA-256 | Cryptographic fund custody and attestation integrity |
| **Testing** | Anchor Test, Pytest | 5-test on-chain suite + 3 oracle mock tests |
| **Deployment** | Solana Devnet, cargo build-sbf | BPF compilation and on-chain deployment |

---

## 10. Innovation Highlights

### What Makes LexEscrow Unique

1. **Compliance as an On-Chain Gate.** Most blockchain escrow solutions focus on multi-sig or time-locked releases. LexEscrow introduces compliance as a mandatory, non-bypassable state transition. The funds literally cannot move without a compliance attestation. This is not a feature bolted onto an existing escrow — it is the fundamental architectural decision.

2. **AI-Powered Real-Time Screening.** Traditional compliance relies on static databases updated on batch schedules. LexEscrow uses Tavily AI to perform real-time OSINT sweeps at the exact moment of fund release, capturing risk signals that are hours or days more current than any database.

3. **Immutable Audit Trail.** Every compliance attestation is permanently recorded on Solana with a SHA-256 hash. Regulators can verify not just that a check was performed, but exactly what was checked, when, and what the result was — without relying on the law firm's own records.

4. **Zero-Trust Fund Custody.** PDA-derived vaults mean no human being controls the escrowed funds. The smart contract is the sole authority. Even the program deployer cannot access the vault without following the complete protocol: multi-sig approval → compliance check → attestation → release.

5. **Legal-Ops-Native UX.** The dashboard speaks the language of large law firms. No crypto jargon, no wallet seed phrases for end users, no Metamask popups. A paralegal can monitor escrow statuses and compliance results without understanding blockchain.

---

## 11. Hackathon Criteria Alignment

| Criterion | How LexEscrow Addresses It |
|-----------|--------------------------|
| **Blockchain** | Immutable on-chain escrow with PDA-derived vaults on Solana; compliance attestations are permanent, verifiable proof stored on a public ledger; every state transition is a blockchain transaction |
| **Finance** | Real SOL custody with multi-sig milestone gates; actual fund movement using `invoke_signed` for PDA-controlled transfers; the escrow holds and releases real value, not just tokenized representations |
| **Compliance** | AI-powered real-time OFAC/PEP/AML screening via Tavily AI OSINT — not a static database lookup, but a live intelligence sweep at the exact moment of release; weighted risk scoring with configurable thresholds |
| **Large Law Firms** | Dashboard uses legal ops terminology ("Matters," "Attestations," "Parties"); no crypto-native requirements for end users; designed for the compliance workflows that Am Law 100 firms already follow |

---

## 12. Future Roadmap

### Phase 1: Core Protocol (Current BUIDL)
- Solana devnet deployment with full smart contract, oracle, listener, and dashboard
- OFAC/PEP/AML screening with Tavily AI integration
- Multi-sig approval with on-chain attestation

### Phase 2: Production Readiness
- Mainnet deployment with comprehensive security audit
- US Treasury OFAC API direct integration (replacing screen-scraping)
- Dun & Bradstreet and Refinitiv World-Check API integration
- Multi-currency support (USDC, USDT) via SPL Token program

### Phase 3: Enterprise Features
- Organization-level identity management (law firm onboarding)
- Template-based escrow creation for common matter types
- Automated reporting for SOC 2 and regulatory examinations
- Slack and Microsoft Teams integration for compliance alerts

### Phase 4: Ecosystem Expansion
- Cross-chain deployment to Ethereum (via Wormhole) and Polygon
- Marketplace for third-party compliance oracle providers
- Open attestation protocol allowing any compliance provider to submit results
- Integration with legal practice management systems (Clio, PracticePanther)

---

## 13. Team & Competitive Advantage

LexEscrow is positioned at the intersection of three massive markets — legal tech ($30B+), regulatory compliance ($45B+), and blockchain infrastructure ($70B+) — yet has no direct competitor that combines all three.

Existing solutions address fragments:
- **Traditional escrow** (trust accounts, IOLTA): No blockchain, no real-time compliance, no immutable audit trail.
- **Crypto escrow** (Escrow.com, Propy): No compliance gating, no legal-ops workflow, no AI screening.
- **Compliance tools** (Chainalysis, Elliptic): Transaction monitoring, not pre-release screening; no on-chain attestation.
- **Legal tech** (Clio, iManage): Practice management, no fund custody or blockchain integration.

LexEscrow is the first to combine on-chain fund custody with AI-powered compliance gating and immutable attestation — purpose-built for the legal industry's most critical transaction workflow.

---

## 14. Repository & Links

| Resource | Link |
|----------|------|
| **GitHub** | https://github.com/icohangar-ops/lexescrow |
| **Codeberg** | https://codeberg.org/cubiczan/lexescrow |
| **Demo Video** | assets/lexescrow_demo.mp4 (3.4 min, 1920x1080) |
| **Logo** | assets/logo.png (480x480) |
| **Thumbnail** | assets/thumbnail.png (1280x720) |