/**
 * LexEscrow Event Listener
 * Adapted from: icohangar-ops/chainsight-ai (Mantle anomaly detection)
 * 
 * Monitors Solana blockchain for EscrowApproved events.
 * When detected, invokes the Compliance Oracle and submits attestation.
 */

const { Connection, PublicKey } = require('@solana/web3.js');
const { Program, AnchorProvider, BorshCoder } = require('@coral-xyz/anchor');
const IDL = require('../target/idl/lexescrow.json');
require('dotenv').config();

const PROGRAM_ID = new PublicKey(process.env.PROGRAM_ID || 'LeXeScRoW11111111111111111111111111111111');
const RPC_URL = process.env.RPC_URL || 'https://api.devnet.solana.com';
const ORACLE_URL = process.env.ORACLE_URL || 'http://localhost:8001';
const SLACK_WEBHOOK = process.env.SLACK_WEBHOOK || '';

const connection = new Connection(RPC_URL, { commitment: 'confirmed', wsEndpoint: undefined });

// ═══ Event Listener ═══

async function listenForEvents() {
  console.log(`[${new Date().toISOString()}] LexEscrow Event Listener started`);
  console.log(`Listening on: ${RPC_URL}`);
  console.log(`Oracle URL: ${ORACLE_URL}`);

  // Subscribe to program logs
  connection.onLogs(PROGRAM_ID, async (logs, ctx) => {
    if (logs.err) return;

    const logStr = logs.logs.join('\n');

    // Detect ComplianceCheckRequested event
    if (logStr.includes('ComplianceCheckRequested')) {
      console.log(`\n[EVENT] ComplianceCheckRequested detected in tx: ${logs.signature}`);
      try {
        await handleComplianceCheckRequested(logs.signature);
      } catch (err) {
        console.error(`[ERROR] Failed to handle event: ${err.message}`);
      }
    }

    // Log other events for monitoring
    if (logStr.includes('EscrowCreated')) {
      console.log(`[EVENT] EscrowCreated in tx: ${logs.signature}`);
    }
    if (logStr.includes('FundsReleased')) {
      console.log(`[EVENT] FundsReleased in tx: ${logs.signature}`);
    }
    if (logStr.includes('EscrowCancelled')) {
      console.log(`[EVENT] EscrowCancelled in tx: ${logs.signature}`);
    }
  }, 'confirmed');

  console.log('Subscribed to LexEscrow program events.');
}

// ═══ Compliance Oracle Integration ═══

async function handleComplianceCheckRequested(txSignature) {
  // 1. Parse the event data from the transaction
  const tx = await connection.getTransaction(txSignature, { commitment: 'confirmed' });
  if (!tx || !tx.meta) {
    console.error('[ERROR] Could not fetch transaction details');
    return;
  }

  // Extract recipient_name and jurisdiction from account data
  // (In production, parse the event struct from the transaction logs)
  const recipientName = 'Acme Corp Holdings'; // placeholder - parse from tx
  const jurisdiction = 'US';
  const escrowId = txSignature.slice(0, 32);

  console.log(`[ORACLE] Checking: ${recipientName} (${jurisdiction})`);

  // 2. Call the Compliance Oracle
  try {
    const oracleResponse = await fetch(`${ORACLE_URL}/api/compliance/check`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        entity_name: recipientName,
        jurisdiction: jurisdiction,
        escrow_id: escrowId,
      }),
    });

    if (!oracleResponse.ok) {
      throw new Error(`Oracle returned ${oracleResponse.status}`);
    }

    const result = await oracleResponse.json();

    if (result.status === 'CLEARED') {
      console.log(`[CLEARED] Risk: ${result.risk_score}/100 - Minting attestation...`);
      await submitAttestation(escrowId, result);
    } else {
      console.log(`[BLOCKED] Risk: ${result.risk_score}/100 - Alerting compliance partner...`);
      await alertCompliancePartner(escrowId, result);
    }
  } catch (err) {
    console.error(`[ORACLE ERROR] ${err.message}`);
    // Fallback: log and alert
    await alertCompliancePartner(escrowId, {
      status: 'ORACLE_ERROR',
      risk_score: 100,
      compliance_summary: `Compliance oracle failed: ${err.message}`,
    });
  }
}

// ═══ Attestation Submission ═══

async function submitAttestation(escrowId, oracleResult) {
  // In production, this would use the Anchor program to call submit_attestation
  // with the on-chain formatted data
  console.log(`[ATTESTATION] Submitting for escrow ${escrowId}`);
  console.log(`  - Summary hash: ${oracleResult.summary_hash.slice(0, 8)}...`);
  console.log(`  - Sources: ${oracleResult.source_count}`);
  console.log(`  - Status: ${oracleResult.status}`);

  // TODO: Build and send the Anchor transaction
  // const provider = new AnchorProvider(connection, wallet, {});
  // const program = new Program(IDL, PROGRAM_ID, provider);
  // await program.methods.submit_attestation(
  //   new Uint8Array(oracleResult.summary_hash),
  //   oracleResult.summary_truncated,
  //   oracleResult.risk_score,
  //   oracleResult.source_count,
  //   oracleResult.source_hashes.map(h => new Uint8Array(h)),
  //   { cleared: {} }
  // ).accounts({...}).rpc();
}

// ═══ Alert Workflow ═══

async function alertCompliancePartner(escrowId, result) {
  const message = {
    text: `*LexEscrow COMPLIANCE BLOCK*\n` +
      `Escrow: ${escrowId}\n` +
      `Status: ${result.status}\n` +
      `Risk Score: ${result.risk_score}/100\n` +
      `Summary: ${result.compliance_summary?.slice(0, 300) || 'N/A'}`,
  };

  if (SLACK_WEBHOOK) {
    try {
      await fetch(SLACK_WEBHOOK, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(message),
      });
      console.log('[ALERT] Slack notification sent.');
    } catch (err) {
      console.error(`[ALERT ERROR] Slack failed: ${err.message}`);
    }
  }

  console.log(`[ALERT] Compliance partner should review escrow ${escrowId}`);
}

// ═══ Start ═══

listenForEvents().catch(console.error);
