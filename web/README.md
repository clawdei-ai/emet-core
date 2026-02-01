# EMET Protocol Web UI

Minimal web interface for the EMET Protocol — trustless truth verification on Base.

## Features

- **Home** — Protocol overview and live stats
- **Submit Claim** — Create claims with evidence, staking EMET tokens
- **Browse Claims** — Filter by status (Active/Challenged/Verified/Rejected)
- **Claim Detail** — View details, stake for/against, challenge or resolve
- **My Activity** — Your claims, reputation score, and EMET balance

## Tech Stack

- React + TypeScript + Vite
- wagmi + viem for blockchain interaction
- RainbowKit for wallet connection
- Base mainnet

## Quick Start

```bash
# Install dependencies
npm install

# Copy env and set WalletConnect project ID
cp .env.example .env
# Edit .env with your WalletConnect project ID from https://cloud.walletconnect.com

# Run dev server
npm run dev
```

Open [http://localhost:5173](http://localhost:5173)

## Contracts (Base Mainnet)

| Contract | Address |
|----------|---------|
| EMET Token | `0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C` |
| EMETRegistry | `0x9D2550eB1Ee613E0f35c70524e1304B26392b0aC` |
| EMETStake | `0x63901ED9Fbd8262B4505819E2F39a6145f28Fbf0` |
| EMETChallenge | `0x5D47f36b0C768395CE49F2D7249DDe44086Fe37b` |
| EMETReputation | `0xAb6Aa88faaC77c1d941eE25A81e397a7A6fa3a85` |

## Deploy to Vercel

```bash
# Build
npm run build

# Deploy (if you have Vercel CLI)
npx vercel
```

Or connect your GitHub repo to Vercel — it auto-detects Vite.

**Build settings:**
- Framework: Vite
- Build command: `npm run build`
- Output directory: `dist`
- Environment variable: `VITE_WALLETCONNECT_PROJECT_ID`

## Project Structure

```
src/
├── contracts/    # ABIs and addresses
├── hooks/        # wagmi hooks for all protocol interactions
├── components/   # Shared UI components
├── pages/        # Route pages
├── lib/          # Utilities (formatting, wagmi config)
├── App.tsx       # Router + providers
└── main.tsx      # Entry point
```
