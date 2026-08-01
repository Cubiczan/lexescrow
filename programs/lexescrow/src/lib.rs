use anchor_lang::prelude::*;
use anchor_lang::solana_program::{
    program::invoke_signed,
    system_instruction::{self, transfer},
};

declare_id!("LeXeScRoW11111111111111111111111111111111");

/// Max signers required for multi-sig approval
const MAX_SIGNERS: usize = 5;

/// Space constants
const ESCROW_SPACE: usize = 8   // discriminator
    + 32  // escrow_id
    + 32  // depositor
    + 32  // recipient
    + (4 + 128)  // recipient_name (String: 4-byte len + 128 max)
    + (4 + 8)   // jurisdiction
    + 8   // amount
    + (1 + 32)  // mint (Option<Pubkey>)
    + 32  // vault
    + 1   // status enum
    + 1   // required_signatures
    + 1   // approval_count
    + MAX_SIGNERS * 32  // approved_signers
    + (1 + 32)  // compliance_attestation
    + 1   // bump
    + 8   // created_at
    + (1 + 8);  // released_at

const ATTESTATION_SPACE: usize = 8  // discriminator
    + 32  // escrow
    + (4 + 128)  // entity_name
    + (4 + 8)   // jurisdiction
    + 1   // risk_score
    + 1   // status enum
    + 32  // summary_hash
    + (4 + 256)  // summary_truncated
    + 1   // source_count
    + 5 * 32  // source_hashes
    + 8   // checked_at
    + 1;  // bump

#[account]
pub struct EscrowAccount {
    /// Unique escrow identifier
    pub escrow_id: [u8; 32],
    /// Depositor (law firm or client)
    pub depositor: Pubkey,
    /// Recipient entity
    pub recipient: Pubkey,
    /// Receiving entity name (for compliance oracle)
    pub recipient_name: String,  // max 128 chars
    /// Jurisdiction code (e.g. "US", "UK", "EU")
    pub jurisdiction: String,    // max 8 chars
    /// Amount in lamports (or SPL token amount)
    pub amount: u64,
    /// SPL mint address (null = native SOL)
    pub mint: Option<Pubkey>,
    /// Vault holding the escrowed funds
    pub vault: Pubkey,
    /// Escrow status
    pub status: EscrowStatus,
    /// Required signer count for release approval
    pub required_signatures: u8,
    /// Current approval count
    pub approval_count: u8,
    /// Approved signer pubkeys
    pub approved_signers: [Pubkey; MAX_SIGNERS],
    /// Compliance attestation PDA (if exists)
    pub compliance_attestation: Option<Pubkey>,
    /// Bump seed for PDA derivation
    pub bump: u8,
    /// Timestamp of creation
    pub created_at: i64,
    /// Timestamp of release (if released)
    pub released_at: Option<i64>,
}

#[account]
pub struct ComplianceAttestation {
    /// The escrow this attestation is for
    pub escrow: Pubkey,
    /// Entity that was screened
    pub entity_name: String,
    /// Jurisdiction of the screening
    pub jurisdiction: String,
    /// Risk score 0-100 (0 = CLEARED)
    pub risk_score: u8,
    /// Compliance status
    pub status: AttestationStatus,
    /// AI-generated compliance summary (CID or on-chain truncated)
    pub summary_hash: [u8; 32],  // SHA-256 hash of full summary
    /// Truncated summary for on-chain display (max 256 bytes)
    pub summary_truncated: String,
    /// Number of regulatory sources checked
    pub source_count: u8,
    /// SHA-256 hashes of source URLs (max 5)
    pub source_hashes: [[u8; 32]; 5],
    /// Unix timestamp of the compliance check
    pub checked_at: i64,
    /// Bump seed
    pub bump: u8,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, PartialEq, Eq)]
pub enum EscrowStatus {
    Active,
    PendingCompliance,
    Cleared,
    Released,
    Blocked,
    Cancelled,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, PartialEq, Eq)]
pub enum AttestationStatus {
    Cleared,
    Blocked,
}

#[error_code]
pub enum EscrowError {
    #[msg("Escrow is not in the correct status for this operation.")]
    InvalidStatus,
    #[msg("Signer has already approved this escrow.")]
    AlreadyApproved,
    #[msg("Not enough approvals to proceed to compliance check.")]
    InsufficientApprovals,
    #[msg("Compliance attestation required before release.")]
    AttestationRequired,
    #[msg("Compliance attestation indicates BLOCKED status.")]
    EntityBlocked,
    #[msg("Only the depositor can cancel.")]
    UnauthorizedCancel,
    #[msg("Recipient name exceeds 128 characters.")]
    RecipientNameTooLong,
    #[msg("Jurisdiction code exceeds 8 characters.")]
    JurisdictionTooLong,
    #[msg("Summary exceeds 256 bytes.")]
    SummaryTooLong,
    #[msg("Exceeded maximum signer count.")]
    TooManySigners,
}

#[program]
pub mod lexescrow {
    use super::*;

    /// Create a new compliance-gated escrow
    pub fn create_escrow(
        ctx: Context<CreateEscrow>,
        escrow_id: [u8; 32],
        recipient_name: String,
        jurisdiction: String,
        amount: u64,
        required_signatures: u8,
    ) -> Result<()> {
        require!(recipient_name.len() <= 128, EscrowError::RecipientNameTooLong);
        require!(jurisdiction.len() <= 8, EscrowError::JurisdictionTooLong);
        require!(required_signatures > 0 && (required_signatures as usize) <= MAX_SIGNERS, EscrowError::TooManySigners);

        let escrow = &mut ctx.accounts.escrow;
        escrow.escrow_id = escrow_id;
        escrow.depositor = ctx.accounts.depositor.key();
        escrow.recipient = ctx.accounts.recipient.key();
        escrow.recipient_name = recipient_name;
        escrow.jurisdiction = jurisdiction;
        escrow.amount = amount;
        escrow.mint = None;
        escrow.vault = ctx.accounts.vault.key();
        escrow.status = EscrowStatus::Active;
        escrow.required_signatures = required_signatures;
        escrow.approval_count = 0;
        escrow.approved_signers = [Pubkey::default(); MAX_SIGNERS];
        escrow.compliance_attestation = None;
        escrow.bump = ctx.bumps.escrow;
        escrow.created_at = Clock::get()?.unix_timestamp;
        escrow.released_at = None;

        // Transfer SOL to vault PDA via signed invoke
        let vault_seeds = &[
            b"vault",
            escrow.to_account_info().key.as_ref(),
            &[ctx.bumps.vault],
        ];
        let signer_seeds = &[&vault_seeds[..]];
        invoke_signed(
            &transfer(ctx.accounts.depositor.key(), ctx.accounts.vault.key(), amount),
            &[
                ctx.accounts.depositor.to_account_info(),
                ctx.accounts.vault.to_account_info(),
                ctx.accounts.system_program.to_account_info(),
            ],
            signer_seeds,
        )?;

        emit!(EscrowCreated {
            escrow: escrow.key(),
            depositor: escrow.depositor,
            recipient: escrow.recipient,
            amount,
            jurisdiction: escrow.jurisdiction.clone(),
        });

        Ok(())
    }

    /// Approve escrow release (multi-sig). Transitions to PendingCompliance when threshold met.
    pub fn approve_release(ctx: Context<ApproveRelease>) -> Result<()> {
        let escrow = &mut ctx.accounts.escrow;
        require!(
            escrow.status == EscrowStatus::Active,
            EscrowError::InvalidStatus
        );

        let signer = ctx.accounts.approver.key();
        require!(!escrow.approved_signers[..(escrow.approval_count as usize)].contains(&signer), EscrowError::AlreadyApproved);

        escrow.approved_signers[escrow.approval_count as usize] = signer;
        escrow.approval_count += 1;

        emit!(ReleaseApproved {
            escrow: escrow.key(),
            approver: signer,
            approval_count: escrow.approval_count,
            required: escrow.required_signatures,
        });

        // If threshold met, pause for compliance check
        if escrow.approval_count >= escrow.required_signatures {
            escrow.status = EscrowStatus::PendingCompliance;
            emit!(ComplianceCheckRequested {
                escrow: escrow.key(),
                recipient_name: escrow.recipient_name.clone(),
                jurisdiction: escrow.jurisdiction.clone(),
            });
        }

        Ok(())
    }

    /// Submit compliance attestation (called by the oracle/listener)
    pub fn submit_attestation(
        ctx: Context<SubmitAttestation>,
        summary_hash: [u8; 32],
        summary_truncated: String,
        risk_score: u8,
        source_count: u8,
        source_hashes: [[u8; 32]; 5],
        status: AttestationStatus,
    ) -> Result<()> {
        require!(summary_truncated.len() <= 256, EscrowError::SummaryTooLong);

        let escrow = &mut ctx.accounts.escrow;
        require!(
            escrow.status == EscrowStatus::PendingCompliance,
            EscrowError::InvalidStatus
        );

        let attestation = &mut ctx.accounts.attestation;
        attestation.escrow = escrow.key();
        attestation.entity_name = escrow.recipient_name.clone();
        attestation.jurisdiction = escrow.jurisdiction.clone();
        attestation.risk_score = risk_score;
        attestation.status = status.clone();
        attestation.summary_hash = summary_hash;
        attestation.summary_truncated = summary_truncated;
        attestation.source_count = source_count;
        attestation.source_hashes = source_hashes;
        attestation.checked_at = Clock::get()?.unix_timestamp;
        attestation.bump = ctx.bumps.attestation;

        escrow.compliance_attestation = Some(attestation.key());

        if status == AttestationStatus::Blocked {
            escrow.status = EscrowStatus::Blocked;
        } else {
            escrow.status = EscrowStatus::Cleared;
        }

        emit!(ComplianceAttestationMinted {
            escrow: escrow.key(),
            attestation: attestation.key(),
            risk_score,
            status: format!("{:?}", status),
        });

        Ok(())
    }

    /// Release funds (only if CLEARED with valid attestation)
    pub fn release_funds(ctx: Context<ReleaseFunds>) -> Result<()> {
        let escrow = &mut ctx.accounts.escrow;
        require!(
            escrow.status == EscrowStatus::Cleared,
            EscrowError::InvalidStatus
        );
        require!(
            escrow.compliance_attestation.is_some(),
            EscrowError::AttestationRequired
        );

        // Verify attestation status is CLEARED
        let attestation = &ctx.accounts.attestation;
        require!(
            attestation.status == AttestationStatus::Cleared,
            EscrowError::EntityBlocked
        );

        // Transfer funds from vault to recipient
        let vault_lamports = ctx.accounts.vault.lamports();
        **ctx.accounts.vault.try_borrow_mut_lamports()? -= escrow.amount;
        **ctx.accounts.recipient.try_borrow_mut_lamports()? += escrow.amount;

        escrow.status = EscrowStatus::Released;
        escrow.released_at = Some(Clock::get()?.unix_timestamp);

        emit!(FundsReleased {
            escrow: escrow.key(),
            recipient: escrow.recipient,
            amount: escrow.amount,
            attestation: attestation.key(),
        });

        Ok(())
    }

    /// Cancel escrow (depositor only, only if not released)
    pub fn cancel_escrow(ctx: Context<CancelEscrow>) -> Result<()> {
        let escrow = &mut ctx.accounts.escrow;
        require!(
            ctx.accounts.depositor.key() == escrow.depositor,
            EscrowError::UnauthorizedCancel
        );
        require!(
            escrow.status != EscrowStatus::Released,
            EscrowError::InvalidStatus
        );

        // Return funds to depositor
        **ctx.accounts.vault.try_borrow_mut_lamports()? -= escrow.amount;
        **ctx.accounts.depositor.try_borrow_mut_lamports()? += escrow.amount;

        escrow.status = EscrowStatus::Cancelled;

        emit!(EscrowCancelled { escrow: escrow.key() });
        Ok(())
    }
}

// ═══ Account Contexts ═══

#[derive(Accounts)]
#[instruction(escrow_id: [u8; 32], recipient_name: String, jurisdiction: String, amount: u64)]
pub struct CreateEscrow<'info> {
    #[account(
        init,
        payer = depositor,
        space = ESCROW_SPACE,
        seeds = [b"escrow", depositor.key().as_ref(), escrow_id.as_ref()],
        bump
    )]
    pub escrow: Account<'info, EscrowAccount>,

    #[account(mut)]
    pub depositor: Signer<'info>,

    /// CHECK: recipient can be any valid pubkey
    pub recipient: AccountInfo<'info>,

    /// CHECK: vault PDA - funds are held here, writable by this program
    #[account(
        mut,
        seeds = [b"vault", escrow.key().as_ref()],
        bump
    )]
    pub vault: AccountInfo<'info>,

    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct ApproveRelease<'info> {
    #[account(mut)]
    pub escrow: Account<'info, EscrowAccount>,
    pub approver: Signer<'info>,
}

#[derive(Accounts)]
pub struct SubmitAttestation<'info> {
    #[account(mut)]
    pub escrow: Account<'info, EscrowAccount>,

    #[account(
        init,
        payer = authority,
        space = ATTESTATION_SPACE,
        seeds = [b"attestation", escrow.key().as_ref()],
        bump
    )]
    pub attestation: Account<'info, ComplianceAttestation>,

    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct ReleaseFunds<'info> {
    #[account(mut)]
    pub escrow: Account<'info, EscrowAccount>,

    pub attestation: Account<'info, ComplianceAttestation>,

    /// CHECK: recipient is the original escrow recipient
    #[account(mut, constraint = escrow.recipient == recipient.key())]
    pub recipient: SystemAccount<'info>,

    /// CHECK: vault PDA - funds held here
    #[account(
        mut,
        seeds = [b"vault", escrow.key().as_ref()],
        bump = escrow.bump
    )]
    pub vault: AccountInfo<'info>,
}

#[derive(Accounts)]
pub struct CancelEscrow<'info> {
    #[account(mut)]
    pub escrow: Account<'info, EscrowAccount>,

    #[account(mut)]
    pub depositor: Signer<'info>,

    /// CHECK: vault PDA - refund from here
    #[account(
        mut,
        seeds = [b"vault", escrow.key().as_ref()],
        bump = escrow.bump
    )]
    pub vault: AccountInfo<'info>,
}

// ═══ Events ═══

#[event]
pub struct EscrowCreated {
    pub escrow: Pubkey,
    pub depositor: Pubkey,
    pub recipient: Pubkey,
    pub amount: u64,
    pub jurisdiction: String,
}

#[event]
pub struct ReleaseApproved {
    pub escrow: Pubkey,
    pub approver: Pubkey,
    pub approval_count: u8,
    pub required: u8,
}

#[event]
pub struct ComplianceCheckRequested {
    pub escrow: Pubkey,
    pub recipient_name: String,
    pub jurisdiction: String,
}

#[event]
pub struct ComplianceAttestationMinted {
    pub escrow: Pubkey,
    pub attestation: Pubkey,
    pub risk_score: u8,
    pub status: String,
}

#[event]
pub struct FundsReleased {
    pub escrow: Pubkey,
    pub recipient: Pubkey,
    pub amount: u64,
    pub attestation: Pubkey,
}

#[event]
pub struct EscrowCancelled {
    pub escrow: Pubkey,
}
