import * as anchor from '@coral-xyz/anchor';
import {
  Keypair,
  SystemProgram,
  LAMPORTS_PER_SOL,
  PublicKey,
} from '@solana/web3.js';
import { assert } from 'chai';

describe('lexescrow', () => {
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);
  const program = anchor.workspace.Lexescrow as anchor.Program;

  const depositor = provider.wallet as anchor.Wallet;
  const recipient = Keypair.generate();
  const escrowId = new Uint8Array(Array(32).fill(1));
  const amount = 1 * LAMPORTS_PER_SOL; // 1 SOL for test

  const [escrowPda] = PublicKey.findProgramAddressSync(
    [Buffer.from('escrow'), depositor.publicKey.toBuffer(), escrowId],
    program.programId,
  );
  const [vaultPda] = PublicKey.findProgramAddressSync(
    [Buffer.from('vault'), escrowPda.toBuffer()],
    program.programId,
  );

  it('Creates a compliance-gated escrow', async () => {
    // Airdrop to recipient so it can receive rent-exempt
    await provider.connection.requestAirdrop(
      recipient.publicKey,
      2 * LAMPORTS_PER_SOL,
    );

    const tx = await program.methods
      .createEscrow(
        Array.from(escrowId),
        'Test Recipient Corp',
        'US',
        new anchor.BN(amount),
        2,
      )
      .accounts({
        depositor: depositor.publicKey,
        recipient: recipient.publicKey,
        vault: vaultPda,
        systemProgram: SystemProgram.programId,
      })
      .rpc();

    console.log('create_escrow tx:', tx);

    const escrow = await program.account.escrowAccount.fetch(escrowPda);
    assert.equal(escrow.status.active, true);
    assert.equal(escrow.amount.toNumber(), amount);
    assert.equal(escrow.jurisdiction, 'US');
    assert.equal(escrow.requiredSignatures, 2);
    assert.equal(escrow.approvalCount, 0);
  });

  it('First signer approves release', async () => {
    const tx = await program.methods
      .approveRelease()
      .accounts({
        escrow: escrowPda,
        approver: depositor.publicKey,
      })
      .rpc();

    console.log('approve_release (1/2) tx:', tx);

    const escrow = await program.account.escrowAccount.fetch(escrowPda);
    assert.equal(escrow.approvalCount, 1);
    assert.equal(escrow.status.active, true);
  });

  it('Second signer triggers PendingCompliance', async () => {
    const secondSigner = Keypair.generate();
    await provider.connection.requestAirdrop(
      secondSigner.publicKey,
      2 * LAMPORTS_PER_SOL,
    );

    const secondProvider = new anchor.AnchorProvider(
      provider.connection,
      new anchor.Wallet(secondSigner),
      provider.opts,
    );
    const secondProgram = new anchor.Program(
      program.idl,
      program.programId,
      secondProvider,
    );

    const tx = await secondProgram.methods
      .approveRelease()
      .accounts({
        escrow: escrowPda,
        approver: secondSigner.publicKey,
      })
      .signers([secondSigner])
      .rpc();

    console.log('approve_release (2/2) tx:', tx);

    const escrow = await program.account.escrowAccount.fetch(escrowPda);
    assert.equal(escrow.approvalCount, 2);
    assert.equal(escrow.status.pendingCompliance, true);
  });

  it('Submits CLEARED attestation', async () => {
    const [attestationPda] = PublicKey.findProgramAddressSync(
      [Buffer.from('attestation'), escrowPda.toBuffer()],
      program.programId,
    );

    const summaryHash = Array(32)
      .fill(0)
      .map((_, i) => i);
    const sourceHashes = Array(5)
      .fill(null)
      .map((_, row) =>
        Array(32)
          .fill(0)
          .map((_, col) => row * 32 + col),
      );

    const tx = await program.methods
      .submitAttestation(
        summaryHash,
        'No adverse information found for this entity in any jurisdiction.',
        0,
        5,
        sourceHashes,
        { cleared: {} },
      )
      .accounts({
        escrow: escrowPda,
        attestation: attestationPda,
        authority: depositor.publicKey,
        systemProgram: SystemProgram.programId,
      })
      .rpc();

    console.log('submit_attestation tx:', tx);

    const escrow = await program.account.escrowAccount.fetch(escrowPda);
    assert.equal(escrow.status.cleared, true);
    assert.ok(escrow.complianceAttestation !== null);

    const attestation = await program.account.complianceAttestation.fetch(
      attestationPda,
    );
    assert.equal(attestation.riskScore, 0);
    assert.equal(attestation.status.cleared, true);
  });

  it('Releases funds after CLEARED', async () => {
    const [attestationPda] = PublicKey.findProgramAddressSync(
      [Buffer.from('attestation'), escrowPda.toBuffer()],
      program.programId,
    );

    const balBefore = await provider.connection.getBalance(
      recipient.publicKey,
    );

    const tx = await program.methods
      .releaseFunds()
      .accounts({
        escrow: escrowPda,
        attestation: attestationPda,
        recipient: recipient.publicKey,
        vault: vaultPda,
      })
      .rpc();

    console.log('release_funds tx:', tx);

    const balAfter = await provider.connection.getBalance(recipient.publicKey);
    assert.equal(balAfter - balBefore, amount);

    const escrow = await program.account.escrowAccount.fetch(escrowPda);
    assert.equal(escrow.status.released, true);
    assert.ok(escrow.releasedAt !== null);
  });
});
