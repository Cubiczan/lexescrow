# LexEscrow — Lean verification notes

**Model:** `Escrow.lean` (same directory). Core Lean 4.34.1 only;
`~/.elan/bin/lean Escrow.lean` exits 0 with no errors or warnings.
Axiom audit (`#print axioms` on `inv_of_reach`, `release_preconditions`,
`cancelled_terminal`, `settlement_mutually_exclusive`): only `propext`
and `Quot.sound` — no `sorry`, no custom axioms. No source files were
modified; this directory is the only addition.

**Scope.** The escrow itself is a Solana/Anchor program in Rust
(`programs/lexescrow/src/lib.rs`), not TypeScript — the TS in the repo is
the Anchor test suite and dashboard. The model covers all five program
instructions plus the off-chain oracle/listener behaviour where it
affects the on-chain state machine.

## Model ↔ source mapping

All line numbers are `programs/lexescrow/src/lib.rs` unless noted.

| Model | Source |
|---|---|
| `Status` (active / pendingCompliance / cleared / released / blocked / cancelled) | `EscrowStatus` enum, ll. 107–114. **These are all the states there are** — no Created/Funded, no Disputed, no Refunded variant |
| `AttStatus` (cleared / blocked) | `AttestationStatus` enum, ll. 117–120 |
| `Escrow` structure | `EscrowAccount`, ll. 45–78 (status l. 63, required_signatures l. 65, compliance_attestation l. 71). `paidRecipient`/`paidDepositor` are model-only counters for funds that left the vault (the program tracks only `amount` and the vault balance) |
| `Reach.create` | `create_escrow`, ll. 151–207: input checks ll. 159–161, status := Active l. 172, vault funded with `amount` via transfer ll. 181–196 |
| `Step.approve` | `approve_release`, ll. 210–241: Active-only ll. 212–215, duplicate-signer check l. 218, signer recorded l. 220, count incremented l. 221, threshold flip to PendingCompliance ll. 230–239 |
| `Step.attest` | `submit_attestation`, ll. 244–290: PendingCompliance-only ll. 256–259, attestation recorded on the escrow l. 274, Blocked → status Blocked l. 277, Cleared → status Cleared l. 279; attestation account is `init` (once only), `SubmitAttestation` ctx ll. 391–406 (init ll. 396–400) |
| `Step.release` (`passed` = the caller-supplied attestation's verdict, deliberately unbound) | `release_funds`, ll. 293–327: Cleared-only ll. 295–298, `compliance_attestation.is_some()` ll. 299–302, passed attestation's status checked ll. 306–309, full-amount transfer ll. 313–314, status := Released l. 316; `ReleaseFunds` ctx ll. 409–426 |
| `Step.cancel` (`hVault` = the Solana runtime's no-negative-lamports rule; the program itself never checks the balance) | `cancel_escrow`, ll. 330–348: depositor-only ll. 332–335, only guard `status != Released` ll. 336–339, full refund ll. 342–343, status := Cancelled l. 345; `CancelEscrow` ctx ll. 429–443 |

## Theorems ↔ what they establish about the code

| Theorem | Claim |
|---|---|
| `inv_of_reach` (+ `inv_step`) | Every reachable state satisfies the `Inv` bundle: approvals are duplicate-free and ≤ required_signatures; an Active escrow is always below threshold (this is what keeps the write `approved_signers[approval_count]`, l. 220, inside the 5-slot array); post-approval states hold exactly `required` approvals; attestation/status coherence; funds conservation; all-or-nothing payments |
| `release_requires_cleared` | `release_funds` can only ever fire from Cleared — never from Active, PendingCompliance, Blocked, or Cancelled |
| `release_preconditions` | A release on a reachable state implies: status was Cleared, the *recorded* attestation is Cleared, approval threshold was met in full, vault covered the amount |
| `compliance_gate` | From any non-Cleared status (incl. Blocked), no call sequence of length 1 releases funds; combined with `attestation_frozen`, a Blocked verdict can never be laundered into a release |
| `no_step_from_released` / `released_terminal` | Released is absorbing: recipient paid in full, depositor paid nothing, no further instruction can fire — settlement is exactly-once on the release side |
| `cancelled_terminal` | For amount > 0, Cancelled is absorbing too — even though the code re-allows `cancel_escrow` from Cancelled, the drained vault (conservation ⇒ vault = 0) blocks any second effective settlement |
| `settlement_mutually_exclusive` | Recipient and depositor are never both paid |
| `funds_conserved` | vault + paidRecipient + paidDepositor = amount at all times |
| `no_partial_settlement` | Each side receives 0 or the full amount — no partial-release path exists in the program |
| `blocked_only_exit_is_cancel` | From Blocked, cancel (depositor refund) is the *only* instruction that can fire at all |
| `attestation_frozen` / `attestation_changes_only_at_pending` | The attestation is written exactly once, exactly when leaving PendingCompliance |
| `depositor_paid_only_via_cancel` | Funds reach the depositor only through `cancel_escrow`, in full |
| (example) | Happy path is inhabitable: create + one approval reaches PendingCompliance for a 1-of-1 escrow |

## Findings (discrepancies & risks)

1. **Approvals are unauthenticated — there is no approver list.**
   `ApproveRelease` accepts any signer (`approver: Signer`, l. 387);
   `EscrowAccount` stores no designated approvers and `create_escrow`
   takes none. Any `required_signatures` *distinct wallets* satisfy the
   "multi-sig" — including the recipient's own Sybil wallets, or with
   `required_signatures = 1`, a single arbitrary wallet. The test suite
   itself approves with a freshly generated random `Keypair`. The
   README's "legal counsel approves release" / "multi-sig approval
   workflows" (README ll. 5, 21, 69) is not enforced on-chain.
2. **Attestation submission is unauthenticated — the compliance gate is
   bypassable end-to-end.** `SubmitAttestation.authority` is any signer
   (l. 404); no oracle pubkey is stored in the escrow or the program.
   Anyone can submit a `Cleared` attestation for any escrow in
   PendingCompliance, with any `risk_score` (the score is recorded but
   never read on-chain; `release_funds` checks only the status enum,
   ll. 306–309). Combined with finding 1, one unauthenticated actor with
   ≤ 5 fresh wallets can drive an escrow from creation to release
   without any approver or oracle involvement. This is the critical
   issue: the on-chain gate is only as strong as an access check that
   does not exist.
3. **`release_funds` has no signer at all.** `ReleaseFunds` (ll. 409–426)
   contains no `Signer`; anyone can trigger the release of a Cleared
   escrow. The destination is constrained to `escrow.recipient`
   (l. 416), so the impact is limited to timing — but it is permissionless
   by construction and undocumented.
4. **The attestation checked at release is not bound to the escrow.**
   `ReleaseFunds.attestation` (l. 413) carries no seeds or constraint
   tying it to `escrow.compliance_attestation` (recorded at l. 274) or
   to `attestation.escrow`. The proof of `release_preconditions` shows
   the practical impact is low *today* — a reachable Cleared escrow's
   recorded attestation is necessarily Cleared, and attestations are
   immutable — but the code does not perform the "valid attestation"
   check the docs describe; it checks *an* attestation, supplied by the
   caller.
5. **Vault PDA bump bug in `release_funds` and `cancel_escrow`.** Both
   contexts constrain the vault with `bump = escrow.bump` (ll. 423 and
   440), but `escrow.bump` is the *escrow* PDA's bump (stored l. 177);
   the vault was created with its own bump (l. 185). Anchor derives the
   expected vault address from the given bump, so release/cancel fail
   unless the two PDAs' canonical bumps happen to coincide (as they do
   for the test fixture's depositor/escrow-id). For other
   depositor/escrow-id combinations the only two fund-moving
   instructions can be permanently unusable.
6. **No dispute path exists.** There is no Disputed state (ll. 107–114)
   and no dispute/appeal instruction. `blocked_only_exit_is_cancel`
   proves a Blocked escrow's only exit is depositor cancel: if the
   depositor refuses, the recipient has no on-chain recourse and funds
   are locked indefinitely. Symmetrically, the depositor can cancel a
   *Cleared* escrow unilaterally at any moment before release — Cleared
   gives the recipient no protection. The README flow (l. 44) ends at
   "Released/Blocked" without noting either fact.
7. **No timeout or expiry.** `created_at` is written (l. 178) and never
   read; no instruction references time except stamping `released_at`
   (l. 317). If approvers never act or no attestation is ever submitted,
   funds sit locked forever; depositor cancel is the only rescue.
8. **Cancel's guard is only `!= Released`** (ll. 336–339): callable from
   Active, PendingCompliance, Cleared, Blocked — and again from
   Cancelled. The repeat call passes every program check and is stopped
   solely by the Solana runtime rejecting a negative lamport balance.
   Relatedly, neither fund-moving instruction checks the vault balance
   in program code; `release_funds` even reads `vault.lamports()` into
   a variable that is never used (l. 312, dead code). Exactly-once
   settlement therefore rests partly on runtime semantics, which is why
   the model makes `amount ≤ vault` an explicit hypothesis.
9. **The shipped listener never submits a BLOCKED attestation** — and
   never submits anything. `event-listener/index.js` ll. 93–100: on a
   BLOCKED oracle result it only posts a Slack alert, leaving the escrow
   in PendingCompliance forever (until a manual attestation or depositor
   cancel — see findings 2 and 6). `submitAttestation` (ll. 108–127) is
   an unimplemented TODO that only logs, and the entity actually
   screened is hardcoded to `'Acme Corp Holdings'` / `'US'` (ll. 71–73)
   regardless of the escrow. The README's "fully autonomous, zero human
   intervention" pipeline (ll. 111–112) does not exist as shipped.
10. **Oracle verdict is brittle and off-chain only.**
    `compliance-oracle/main.py` l. 108: BLOCKED iff `risk_score > 0`,
    and the score is a raw substring-keyword sum over the Tavily AI
    answer text (ll. 44–55) — a summary saying "no evidence of fraud"
    still contains "fraud" (+15) and blocks the escrow. The check
    endpoint itself is unauthenticated. None of this is visible
    on-chain, where only the final enum is consumed (finding 2).
11. **SPL tokens are not actually supported.** `EscrowAccount.mint` is
    documented as "SPL mint address (null = native SOL)" and `amount`
    as "lamports (or SPL token amount)", but `create_escrow` accepts no
    mint and hardcodes `escrow.mint = None` (l. 170); release/cancel move
    raw lamports (ll. 313–314, 342–343). Native SOL only.
12. **No fees, and no account cleanup.** Release and cancel move the
    full `amount` (see `no_partial_settlement`); there is no fee account
    or platform cut anywhere. Conversely, any extra lamports sent to the
    vault PDA are stranded, and the escrow/attestation/vault accounts
    are never closed — rent is never reclaimed.
13. **Zero-amount escrows are allowed.** `create_escrow` validates name,
    jurisdiction, and signer count (ll. 159–161) but not `amount > 0`.
    Harmless but degenerate; it is also exactly the case where the
    model's cancel-side exactly-once theorem needs its `0 < amount`
    hypothesis (a 0-amount re-cancel is a genuine no-op, on-chain too).
14. **Approval-array safety is emergent.** The write
    `approved_signers[approval_count]` (l. 220) is in-bounds only
    because of the proved invariant (Active ⇒ count < required ≤ 5).
    Nothing at the write site checks it; any future instruction that
    records approvals outside Active, or mutates `required_signatures`,
    would silently break it.
15. **Minor docs drift.** README l. 69 ("second approval transitions to
    PendingCompliance") describes only the test configuration
    (required = 2); the code transitions at the depositor-chosen
    threshold (1–5). README l. 21's "hard-blocked — permanently" is
    accurate for the release path but omits that depositor cancel
    remains available from Blocked (finding 6).
