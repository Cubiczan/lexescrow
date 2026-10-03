/-!
# LexEscrow — formal model of the escrow lifecycle and its compliance gate

Source modelled: `programs/lexescrow/src/lib.rs` (Solana / Anchor program),
plus the off-chain compliance path in `compliance-oracle/main.py` and
`event-listener/index.js` where noted in `NOTES.md`.

Compile with plain Lean 4.34.1 (core library only, no Mathlib):

    ~/.elan/bin/lean Escrow.lean

No `sorry` / `admit` / custom axioms (audit: only `propext`,
`Classical.choice`, `Quot.sound`).

## Modelling choices (where the code is *not* followed literally, and why)

* Pubkeys are abstracted as `Nat` party ids; u64 amounts as `Nat`
  (no wrap-around; see `NOTES.md` for the bounds argument).
* The states are the code's actual `EscrowStatus` enum.  There is **no**
  `Created`/`Funded` state (creation lands in `Active` with the vault
  already funded), **no** `Disputed` state or dispute instruction at all,
  and no `Refunded` state (the refund path *is* `cancel_escrow`).
* `release_funds` checks the verdict of an attestation account *passed
  in by the caller*, which the code never binds to the attestation
  recorded in the escrow (`escrow.compliance_attestation` is only
  checked with `is_some`).  The model keeps that passed-in verdict as an
  explicit free parameter (`passed`) instead of pretending the binding
  exists.  The invariant `inv_of_reach` then shows that on every
  *reachable* state a `cleared` escrow's recorded attestation is
  `cleared` anyway, so the gate's conclusion survives — see
  `release_preconditions` and `NOTES.md` finding 4.
* The Solana runtime forbids debiting an account below zero lamports,
  but the program never checks the vault balance itself.  Successful
  fund-moving steps therefore carry an explicit `amount ≤ vault`
  hypothesis, flagged in `NOTES.md` finding 10.
-/

namespace LexEscrow

/-- Escrow status — mirrors `EscrowStatus`, lib.rs ll. 107–114. -/
inductive Status where
  | active
  | pendingCompliance
  | cleared
  | released
  | blocked
  | cancelled
deriving DecidableEq, Repr

/-- Compliance verdict — mirrors `AttestationStatus`, lib.rs ll. 117–120. -/
inductive AttStatus where
  | cleared
  | blocked
deriving DecidableEq, Repr

/-- Abstract escrow state.

`approvals` is the list of approver ids recorded so far
(`approved_signers[..approval_count]`, lib.rs l. 218); its length is the
code's `approval_count`.  `attestation` is the recorded
`compliance_attestation` together with its verdict — `none` until
`submit_attestation` runs.  `paidRecipient` / `paidDepositor` accumulate
the lamports actually transferred out of the vault by `release_funds` /
`cancel_escrow`; the on-chain program has no such counters — they exist
so exactly-once settlement can be stated and proved. -/
structure Escrow where
  status : Status
  depositor : Nat
  recipient : Nat
  amount : Nat
  vault : Nat
  required : Nat
  approvals : List Nat
  attestation : Option AttStatus
  paidRecipient : Nat
  paidDepositor : Nat
deriving DecidableEq, Repr

/-- One instruction call of the program, as a transition relation.
Each constructor mirrors one `pub fn` of lib.rs, with the instruction's
`require!` checks as hypotheses. -/
inductive Step : Escrow → Escrow → Prop where
  /-- `approve_release` (ll. 210–241): only from `Active`; the signer
  must not already have approved; when the incremented count reaches
  `required_signatures` the escrow pauses in `PendingCompliance`.
  The code places *no* restriction on who the signer is. -/
  | approve (s : Escrow) (signer : Nat)
      (hStatus : s.status = .active)
      (hNew : signer ∉ s.approvals) :
      Step s { s with
        approvals := s.approvals ++ [signer],
        status := if s.required ≤ s.approvals.length + 1
                  then .pendingCompliance else .active }
  /-- `submit_attestation` (ll. 244–290): only from
  `PendingCompliance`; the attestation account is `init` (ll. 396–400),
  so this fires at most once per escrow — hence `hNone`.  The caller's
  identity is *not* checked in the code: any signer may play oracle. -/
  | attest (s : Escrow) (a : AttStatus)
      (hStatus : s.status = .pendingCompliance)
      (hNone : s.attestation = .none) :
      Step s { s with
        attestation := .some a,
        status := match a with | .cleared => .cleared | .blocked => .blocked }
  /-- `release_funds` (ll. 293–327): only from `Cleared`; a recorded
  attestation must exist (`is_some`, ll. 299–302) and the *passed-in*
  attestation's verdict must be `Cleared` (ll. 306–309) — never bound to
  the recorded one, so `passed` stays a free parameter.  No signer /
  authorisation check exists in the instruction at all.  Moves the full
  `amount` to the recipient: partial releases do not exist. -/
  | release (s : Escrow) (passed : AttStatus)
      (hStatus : s.status = .cleared)
      (hSome : s.attestation.isSome = true)
      (hPassed : passed = .cleared)
      (hVault : s.amount ≤ s.vault) :
      Step s { s with
        status := .released,
        vault := s.vault - s.amount,
        paidRecipient := s.paidRecipient + s.amount }
  /-- `cancel_escrow` (ll. 330–348): depositor only (ll. 332–335); the
  only status guard is `≠ Released` (ll. 336–339) — it may fire from
  `Cancelled` again and is then stopped only by `hVault`, i.e. by the
  Solana runtime on-chain, not by a program check.  Refunds the full
  `amount` to the depositor. -/
  | cancel (s : Escrow) (caller : Nat)
      (hCaller : caller = s.depositor)
      (hStatus : s.status ≠ .released)
      (hVault : s.amount ≤ s.vault) :
      Step s { s with
        status := .cancelled,
        vault := s.vault - s.amount,
        paidDepositor := s.paidDepositor + s.amount }

/-- Reachable states: `create_escrow` (ll. 151–207) followed by any
number of steps.  Creation checks `1 ≤ required_signatures ≤ MAX_SIGNERS`
(l. 161), initialises status `Active` (l. 172) with no approvals and no
attestation, and funds the vault with exactly `amount` (ll. 181–196). -/
inductive Reach : Escrow → Prop where
  | create (depositor recipient amount required : Nat)
      (hReq : 1 ≤ required ∧ required ≤ 5) :
      Reach { status := .active, depositor := depositor,
              recipient := recipient, amount := amount, vault := amount,
              required := required, approvals := [], attestation := .none,
              paidRecipient := 0, paidDepositor := 0 }
  | step {s s' : Escrow} (h : Reach s) (hstep : Step s s') : Reach s'

/-! ### The reachable-state invariant -/

/-- Invariant bundle enjoyed by every reachable state.

* `threshold` — post-approval states are entered only with the full
  approval count (the flip at ll. 230–239 plus the `Active`-only guard
  on further approvals).
* `activeLen` — an `Active` escrow is always still short of its
  threshold; this is also what keeps the on-chain write
  `approved_signers[approval_count]` (l. 220) inside the 5-slot array.
* `att*` — attestation/status coherence: the attestation is written
  exactly once, by the step that leaves `PendingCompliance`.
* `funds` — conservation: vault + paid-out = escrowed amount.
* `paid*` — settlement is all-or-nothing per side, and each side's
  full payment pins the status. -/
structure Inv (s : Escrow) : Prop where
  nodup : s.approvals.Nodup
  bounded : s.approvals.length ≤ s.required
  reqRange : 1 ≤ s.required ∧ s.required ≤ 5
  activeLen : s.status = .active → s.approvals.length < s.required
  threshold :
    (s.status = .pendingCompliance ∨ s.status = .cleared ∨
     s.status = .blocked ∨ s.status = .released) →
    s.approvals.length = s.required
  attNoneEarly :
    (s.status = .active ∨ s.status = .pendingCompliance) →
    s.attestation = .none
  attCleared :
    (s.status = .cleared ∨ s.status = .released) →
    s.attestation = .some .cleared
  attBlocked : s.status = .blocked → s.attestation = .some .blocked
  funds : s.vault + s.paidRecipient + s.paidDepositor = s.amount
  paidROr : s.paidRecipient = 0 ∨ s.paidRecipient = s.amount
  paidDOr : s.paidDepositor = 0 ∨ s.paidDepositor = s.amount
  releasedPaid : s.status = .released → s.paidRecipient = s.amount
  cancelledPaid : s.status = .cancelled → s.paidDepositor = s.amount
  paidRStatus : 0 < s.amount → s.paidRecipient = s.amount →
    s.status = .released
  paidDStatus : 0 < s.amount → s.paidDepositor = s.amount →
    s.status = .cancelled

theorem nodup_append_singleton {l : List Nat} {x : Nat}
    (h : l.Nodup) (hx : x ∉ l) : (l ++ [x]).Nodup := by
  induction l with
  | nil => simp
  | cons a l ih =>
      obtain ⟨ha, hl⟩ := List.nodup_cons.mp h
      have hx' : x ∉ l := fun hm => hx (List.mem_cons_of_mem a hm)
      have hxa : x ≠ a := fun e => hx (List.mem_cons.mpr (Or.inl e))
      rw [List.cons_append, List.nodup_cons]
      refine ⟨?_, ih hl hx'⟩
      simp only [List.mem_append, List.mem_singleton]
      rintro (hm | hm)
      · exact ha hm
      · exact hxa hm.symm

/-- Every step preserves the invariant. -/
theorem inv_step {s s' : Escrow} (hs : Inv s) (h : Step s s') : Inv s' := by
  cases h with
  | approve signer hStatus hNew =>
      have hlen : (s.approvals ++ [signer]).length
          = s.approvals.length + 1 := by simp
      have hlt : s.approvals.length < s.required := hs.activeLen hStatus
      refine ⟨?_, ?_, hs.reqRange, ?_, ?_, ?_, ?_, ?_, hs.funds, hs.paidROr,
        hs.paidDOr, ?_, ?_, ?_, ?_⟩
      · exact nodup_append_singleton hs.nodup hNew
      · show (s.approvals ++ [signer]).length ≤ s.required
        rw [hlen]; omega
      · intro hst
        by_cases hif : s.required ≤ s.approvals.length + 1
        · simp [hif] at hst
        · show (s.approvals ++ [signer]).length < s.required
          rw [hlen]; omega
      · intro hst
        by_cases hif : s.required ≤ s.approvals.length + 1
        · show (s.approvals ++ [signer]).length = s.required
          rw [hlen]; omega
        · obtain (h1 | h1 | h1 | h1) := hst <;> simp [hif] at h1
      · intro _
        exact hs.attNoneEarly (Or.inl hStatus)
      · intro hst
        obtain (h1 | h1) := hst <;>
          (by_cases hif : s.required ≤ s.approvals.length + 1 <;>
            simp [hif] at h1)
      · intro hst
        by_cases hif : s.required ≤ s.approvals.length + 1 <;>
          simp [hif] at hst
      · intro hst
        by_cases hif : s.required ≤ s.approvals.length + 1 <;>
          simp [hif] at hst
      · intro hst
        by_cases hif : s.required ≤ s.approvals.length + 1 <;>
          simp [hif] at hst
      · intro hpos hpaid
        have hst := hs.paidRStatus hpos hpaid
        rw [hStatus] at hst; exact Status.noConfusion hst
      · intro hpos hpaid
        have hst := hs.paidDStatus hpos hpaid
        rw [hStatus] at hst; exact Status.noConfusion hst
  | attest a hStatus hNone =>
      have hthr : s.approvals.length = s.required :=
        hs.threshold (Or.inl hStatus)
      refine ⟨hs.nodup, hs.bounded, hs.reqRange, ?_, ?_, ?_, ?_, ?_, hs.funds,
        hs.paidROr, hs.paidDOr, ?_, ?_, ?_, ?_⟩
      · intro hst; cases a <;> simp at hst
      · intro _; exact hthr
      · intro hst; cases a <;> simp at hst
      · intro hst
        cases a with
        | cleared => rfl
        | blocked => simp at hst
      · intro hst
        cases a with
        | cleared => simp at hst
        | blocked => rfl
      · intro hst; cases a <;> simp at hst
      · intro hst; cases a <;> simp at hst
      · intro hpos hpaid
        have hst := hs.paidRStatus hpos hpaid
        rw [hStatus] at hst; exact Status.noConfusion hst
      · intro hpos hpaid
        have hst := hs.paidDStatus hpos hpaid
        rw [hStatus] at hst; exact Status.noConfusion hst
  | release passed hStatus hSome hPassed hVault =>
      have hthr : s.approvals.length = s.required :=
        hs.threshold (Or.inr (Or.inl hStatus))
      have hatt : s.attestation = .some .cleared :=
        hs.attCleared (Or.inl hStatus)
      have hpaid0 : s.paidRecipient = 0 := by
        rcases hs.paidROr with h0 | hAmt
        · exact h0
        · by_cases hpos : 0 < s.amount
          · have hst := hs.paidRStatus hpos hAmt
            rw [hStatus] at hst; exact Status.noConfusion hst
          · have hz : s.amount = 0 := by omega
            rw [hz] at hAmt; exact hAmt
      refine ⟨hs.nodup, hs.bounded, hs.reqRange, ?_, ?_, ?_, ?_, ?_, ?_, ?_,
        hs.paidDOr, ?_, ?_, ?_, ?_⟩
      · intro hst; simp at hst
      · intro _; exact hthr
      · intro hst; simp at hst
      · intro _; exact hatt
      · intro hst; simp at hst
      · show s.vault - s.amount + (s.paidRecipient + s.amount)
            + s.paidDepositor = s.amount
        have hf := hs.funds; omega
      · show s.paidRecipient + s.amount = 0
            ∨ s.paidRecipient + s.amount = s.amount
        exact Or.inr (by omega)
      · intro _; show s.paidRecipient + s.amount = s.amount; omega
      · intro hst; simp at hst
      · intro _ _; rfl
      · intro hpos hpaid
        have hst := hs.paidDStatus hpos hpaid
        rw [hStatus] at hst; exact Status.noConfusion hst
  | cancel caller hCaller hStatus hVault =>
      have hpd : s.paidDepositor = 0 ∨ s.amount = 0 := by
        rcases hs.paidDOr with h0 | hAmt
        · exact Or.inl h0
        · rcases hs.paidROr with hr0 | hrAmt
          · have hf := hs.funds
            exact Or.inr (by omega)
          · by_cases hpos : 0 < s.amount
            · have hst := hs.paidRStatus hpos hrAmt
              exact absurd hst hStatus
            · exact Or.inr (by omega)
      refine ⟨hs.nodup, hs.bounded, hs.reqRange, ?_, ?_, ?_, ?_, ?_, ?_, ?_,
        ?_, ?_, ?_, ?_, ?_⟩
      · intro hst; simp at hst
      · intro hst; simp at hst
      · intro hst; simp at hst
      · intro hst; simp at hst
      · intro hst; simp at hst
      · show s.vault - s.amount + s.paidRecipient
            + (s.paidDepositor + s.amount) = s.amount
        have hf := hs.funds; omega
      · exact hs.paidROr
      · show s.paidDepositor + s.amount = 0
            ∨ s.paidDepositor + s.amount = s.amount
        rcases hs.paidDOr with h0 | hAmt <;>
          rcases hpd with hp0 | hz <;> omega
      · intro hst; simp at hst
      · intro _
        show s.paidDepositor + s.amount = s.amount
        rcases hs.paidDOr with h0 | hAmt <;>
          rcases hpd with hp0 | hz <;> omega
      · intro hpos hpaid
        have hst := hs.paidRStatus hpos hpaid
        exact absurd hst hStatus
      · intro _ _; rfl

/-- The invariant holds at creation and is preserved by every step,
hence holds of every reachable state. -/
theorem inv_of_reach {s : Escrow} (h : Reach s) : Inv s := by
  induction h with
  | create depositor recipient amount required hReq =>
      refine ⟨List.nodup_nil, Nat.zero_le _, hReq, ?_, ?_, ?_, ?_, ?_, ?_,
        ?_, ?_, ?_, ?_, ?_, ?_⟩
      · intro _; exact hReq.1
      · intro hst
        obtain (h1 | h1 | h1 | h1) := hst <;> simp at h1
      · intro _; rfl
      · intro hst
        obtain (h1 | h1) := hst <;> simp at h1
      · intro hst; simp at hst
      · rfl
      · exact Or.inl rfl
      · exact Or.inl rfl
      · intro hst; simp at hst
      · intro hst; simp at hst
      · intro hpos hpaid
        exfalso
        have h0 : (0 : Nat) = amount := hpaid
        have hpos' : 0 < amount := hpos
        omega
      · intro hpos hpaid
        exfalso
        have h0 : (0 : Nat) = amount := hpaid
        have hpos' : 0 < amount := hpos
        omega
  | step hr hstep ih => exact inv_step ih hstep

/-! ### Headline theorems -/

/-- **Release only from `Cleared`.**  The only step that can land in
`released` starts from `cleared` — approval and attestation states,
`blocked`, and `cancelled` can never release. -/
theorem release_requires_cleared {s s' : Escrow} (h : Step s s')
    (hr : s'.status = .released) : s.status = .cleared := by
  cases h with
  | approve x hStatus hNew =>
      by_cases hif : s.required ≤ s.approvals.length + 1 <;>
        simp [hif] at hr
  | attest a hStatus hNone => cases a <;> simp at hr
  | release passed hStatus hSome hPassed hVault => exact hStatus
  | cancel caller hCaller hStatus hVault => simp at hr

/-- **`Released` is absorbing.**  No instruction accepts a `released`
escrow: approve needs `active`, attest needs `pendingCompliance`,
release needs `cleared`, cancel excludes `released` (lib.rs ll. 336–339). -/
theorem no_step_from_released {s s' : Escrow} (h : Step s s') :
    s.status ≠ .released := by
  cases h with
  | approve x hStatus hNew => simp [hStatus]
  | attest a hStatus hNone => simp [hStatus]
  | release p hStatus hSome hP hV => simp [hStatus]
  | cancel c hCaller hStatus hVault => exact hStatus

/-- **Full release preconditions.**  On a reachable state, any step into
`released` came from a `cleared` escrow whose *recorded* attestation is
`cleared` (even though the code checks an unbound passed-in account),
with the full approval threshold met and the vault covering the amount. -/
theorem release_preconditions {s s' : Escrow} (hrch : Reach s)
    (h : Step s s') (hrel : s'.status = .released) :
    s.status = .cleared ∧ s.attestation = .some .cleared ∧
    s.required ≤ s.approvals.length ∧ s.amount ≤ s.vault := by
  have hi := inv_of_reach hrch
  have hsc : s.status = .cleared := release_requires_cleared h hrel
  refine ⟨hsc, hi.attCleared (Or.inl hsc), ?_, ?_⟩
  · have hthr := hi.threshold (Or.inr (Or.inl hsc)); omega
  · cases h with
    | approve x hStatus hNew =>
        by_cases hif : s.required ≤ s.approvals.length + 1 <;>
          simp [hif] at hrel
    | attest a hStatus hNone => cases a <;> simp at hrel
    | release p hStatus hSome hP hVault => exact hVault
    | cancel c hCaller hStatus hVault => simp at hrel

/-- **The compliance gate.**  From any non-`cleared` status, no step
releases funds — in particular a `blocked` escrow (attestation verdict
`Blocked`) can never be released, whatever is passed to `release_funds`. -/
theorem compliance_gate {s s' : Escrow} (h : Step s s')
    (hnot : s.status ≠ .cleared) : s'.status ≠ .released :=
  fun hr => hnot (release_requires_cleared h hr)

/-- From `blocked`, the *only* step that can fire at all is
`cancel_escrow` (the depositor refund): approve/attest/release are all
status-guarded away.  There is no dispute or appeal transition. -/
theorem blocked_only_exit_is_cancel {s s' : Escrow} (h : Step s s')
    (hb : s.status = .blocked) : s'.status = .cancelled := by
  cases h with
  | approve x hStatus hNew =>
      rw [hb] at hStatus; exact Status.noConfusion hStatus
  | attest a hStatus hNone =>
      rw [hb] at hStatus; exact Status.noConfusion hStatus
  | release p hStatus hSome hP hV =>
      rw [hb] at hStatus; exact Status.noConfusion hStatus
  | cancel c hCaller hStatus hVault => rfl

/-- The attestation is written exactly once and never changes
afterwards (the attestation account is `init`, ll. 396–400, and no
instruction updates it). -/
theorem attestation_frozen {s s' : Escrow} (h : Step s s')
    {a : AttStatus} (ha : s.attestation = .some a) :
    s'.attestation = .some a := by
  cases h with
  | approve x hStatus hNew => exact ha
  | attest a' hStatus hNone => rw [hNone] at ha; simp at ha
  | release p hStatus hSome hP hV => exact ha
  | cancel c hCaller hStatus hVault => exact ha

/-- …and the one write happens exactly when leaving
`PendingCompliance` — the gate cannot be attested early, late, or twice. -/
theorem attestation_changes_only_at_pending {s s' : Escrow}
    (h : Step s s') (hchg : s'.attestation ≠ s.attestation) :
    s.status = .pendingCompliance := by
  cases h with
  | approve x hStatus hNew => exact absurd rfl hchg
  | attest a hStatus hNone => exact hStatus
  | release p hStatus hSome hP hV => exact absurd rfl hchg
  | cancel c hCaller hStatus hVault => exact absurd rfl hchg

/-- **Conservation of funds** on every reachable state:
vault balance + everything paid out = the escrowed amount. -/
theorem funds_conserved {s : Escrow} (h : Reach s) :
    s.vault + s.paidRecipient + s.paidDepositor = s.amount :=
  (inv_of_reach h).funds

/-- **No partial settlement.**  Each side is paid either nothing or the
full escrow amount — the program has no partial-release path. -/
theorem no_partial_settlement {s : Escrow} (h : Reach s) :
    (s.paidRecipient = 0 ∨ s.paidRecipient = s.amount) ∧
    (s.paidDepositor = 0 ∨ s.paidDepositor = s.amount) :=
  ⟨(inv_of_reach h).paidROr, (inv_of_reach h).paidDOr⟩

/-- **Release and refund are mutually exclusive.**  The recipient and
the depositor can never both have been paid. -/
theorem settlement_mutually_exclusive {s : Escrow} (h : Reach s) :
    s.paidRecipient = 0 ∨ s.paidDepositor = 0 := by
  have hi := inv_of_reach h
  rcases hi.paidROr with hr0 | hrA
  · exact Or.inl hr0
  · rcases hi.paidDOr with hd0 | hdA
    · exact Or.inr hd0
    · have hf := hi.funds
      have hz : s.amount = 0 := by omega
      exact Or.inl (by omega)

/-- **Exactly-once settlement, recipient side.**  A released escrow has
paid the recipient in full, paid the depositor nothing, and admits no
further step of any kind. -/
theorem released_terminal {s : Escrow} (h : Reach s)
    (hs : s.status = .released) :
    s.paidRecipient = s.amount ∧ s.paidDepositor = 0 ∧
    ∀ s', ¬ Step s s' := by
  have hi := inv_of_reach h
  refine ⟨hi.releasedPaid hs, ?_, fun s' hstep => no_step_from_released hstep hs⟩
  rcases hi.paidDOr with hd0 | hdA
  · exact hd0
  · by_cases hpos : 0 < s.amount
    · have hst := hi.paidDStatus hpos hdA
      rw [hs] at hst; exact Status.noConfusion hst
    · have hz : s.amount = 0 := by omega
      rw [hz] at hdA; exact hdA

/-- **Exactly-once settlement, depositor side.**  For a positive
amount, a cancelled escrow is fully absorbing too: the code re-allows
`cancel_escrow` from `cancelled`, but the drained vault
(`funds_conserved` gives `vault = 0`) blocks every fund-moving step.
(For `amount = 0` a re-cancel is a harmless no-op on-chain.) -/
theorem cancelled_terminal {s : Escrow} (h : Reach s)
    (hs : s.status = .cancelled) (hamt : 0 < s.amount) :
    ∀ s', ¬ Step s s' := by
  have hi := inv_of_reach h
  have hdA : s.paidDepositor = s.amount := hi.cancelledPaid hs
  have hr0 : s.paidRecipient = 0 := by
    rcases hi.paidROr with h0 | hA
    · exact h0
    · have hst := hi.paidRStatus hamt hA
      rw [hs] at hst; exact Status.noConfusion hst
  have hv0 : s.vault = 0 := by have hf := hi.funds; omega
  intro s' hstep
  cases hstep with
  | approve x hStatus hNew =>
      rw [hs] at hStatus; exact Status.noConfusion hStatus
  | attest a hStatus hNone =>
      rw [hs] at hStatus; exact Status.noConfusion hStatus
  | release p hStatus hSome hP hV =>
      rw [hs] at hStatus; exact Status.noConfusion hStatus
  | cancel c hCaller hStatus hVault =>
      rw [hv0] at hVault
      have hz : s.amount = 0 := by omega
      omega

/-- The depositor is paid **only** via `cancel_escrow`, and then in
full: no other instruction moves funds to the depositor, and cancel is
the unique source of a `cancelled` state. -/
theorem depositor_paid_only_via_cancel {s s' : Escrow} (h : Step s s')
    (hpay : s.paidDepositor < s'.paidDepositor) :
    s'.status = .cancelled ∧
    s'.paidDepositor = s.paidDepositor + s.amount := by
  cases h with
  | approve x hStatus hNew => simp at hpay
  | attest a hStatus hNone => simp at hpay
  | release p hStatus hSome hP hV => simp at hpay
  | cancel c hCaller hStatus hVault => exact ⟨rfl, rfl⟩

/-- Smoke test: creation is reachable, and a 1-of-1 escrow reaches
`PendingCompliance` with a single approval (any signer — see
`NOTES.md` finding 1). -/
example : ∃ s : Escrow, Reach s ∧ s.status = .pendingCompliance ∧
    s.approvals = [7] :=
  ⟨_, Reach.step (Reach.create 1 2 100 1 ⟨by decide, by decide⟩)
      (Step.approve _ 7 (by rfl) (by simp)), by rfl, by rfl⟩

end LexEscrow
