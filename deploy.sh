#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# LexEscrow — One-Click Devnet Deploy Script
# ═══════════════════════════════════════════════════════════════
# Prerequisites: solana-cli, anchor-cli, cargo
# Usage: ./deploy.sh
# ═══════════════════════════════════════════════════════════════

set -e

echo "=== LexEscrow Devnet Deployment ==="

# 1. Configure Solana CLI for devnet
echo "[1/5] Switching to devnet..."
solana config set --url devnet

# 2. Use the generated deploy keypair
echo "[2/5] Setting deploy keypair..."
KEYPAIR=$(dirname "$0")/deploy-keypair.json
if [ ! -f "$KEYPAIR" ]; then
    echo "ERROR: deploy-keypair.json not found at $KEYPAIR"
    exit 1
fi

# Show wallet address
WALLET=$(solana address -k "$KEYPAIR")
echo "  Deploy wallet: $WALLET"

# 3. Airdrop SOL if balance is too low
BALANCE=$(solana balance "$WALLET" --keypair "$KEYPAIR" 2>/dev/null | awk '{print $1}')
if [ "$BALANCE" = "0" ] || [ -z "$BALANCE" ]; then
    echo "[3/5] Requesting devnet SOL airdrop (2 SOL)..."
    solana airdrop 2 --keypair "$KEYPAIR"
else
    echo "[3/5] Wallet has $BALANCE SOL, skipping airdrop"
fi

# 4. Build the Anchor program
echo "[4/5] Building smart contract..."
anchor build

# 5. Deploy to devnet
echo "[5/5] Deploying to devnet..."
anchor deploy --provider.cluster devnet --program-keypair "$KEYPAIR"

# Get the deployed program ID
PROGRAM_ID=$(solana program show --keypair "$KEYPAIR" 2>/dev/null | head -1)

echo ""
echo "=== Deployment Complete ==="
echo "Program ID: $PROGRAM_ID"
echo "Deploy wallet: $WALLET"
echo "Network: devnet"
echo ""
echo "Next steps:"
echo "  1. Update lib.rs with the new Program ID"
echo "  2. Update Anchor.toml with the new Program ID" 
echo "  3. Update test files with the new Program ID"
echo "  4. Run tests: anchor test --provider.cluster devnet"
