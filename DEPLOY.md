# LexEscrow — Deployment Guide

## Quick Deploy to Devnet

```bash
# Clone the repo
git clone https://github.com/icohangar-ops/lexescrow.git
cd lexescrow

# Install Solana CLI + Anchor
sh -c "$(curl -sSfL https://release.anza.xyz/stable/install)"
export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
cargo install --git https://github.com/coral-xyz/anchor anchor-cli --tag v0.30.0

# Get devnet SOL
solana config set --url devnet
solana airdrop 2 --keypair deploy-keypair.json

# Build & Deploy
anchor build
anchor deploy --provider.cluster devnet --program-keypair deploy-keypair.json
```

## Pre-generated Keypair

The repo includes `deploy-keypair.json` with a fresh keypair:

- **Address**: `CrKyEtxZnrFQfQFwTNLfBMuPbKVqkqawBigrv2VQG5BP`
- **Network**: Solana Devnet
- **Seed Phrase**: `use enough scheme orient isolate used chalk lava coffee elite weasel mix`

> **Important**: This keypair is for devnet only. Never use it on mainnet.

## Post-Deploy

After deploying, update these files with your new Program ID:

1. `programs/lexescrow/src/lib.rs` — `declare_id!("YOUR_PROGRAM_ID")`
2. `Anchor.toml` — `[programs.devnet]` section
3. `programs/lexescrow/tests/lexescrow.ts` — test constants
4. `lib.rs` — any hardcoded program ID references

## Verify On-Chain

```bash
solana program show YOUR_PROGRAM_ID --url devnet
```

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Smart Contract | Solana / Anchor 0.30.0 / Rust |
| Compliance Oracle | FastAPI / Python / Tavily AI |
| Event Listener | Node.js / Solana WebSocket |
| Dashboard | Next.js / Tailwind CSS |
| Deployment | Solana Devnet |
