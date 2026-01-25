# Git & PR Metadata

## 📝 One-line Git Commit Message
`feat(amm): init MEV-resistant AMM 🛡️ with batch auctions & TWAP`

## 🐙 GitHub Pull Request Title
`feat: Initial Release of MEV-Resistant AMM MVP 🛡️`

## 📋 GitHub Pull Request Description
### Summary
This PR introduces the MVP for the **MEV-Resistant AMM**, designed to prevent sandwich attacks using a batch auction mechanism.

### Key Features
- **Batch Auctions**: Orders are collected and executed at a single clearing price every 6 blocks.
- **TWAP Oracle**: Built-in Time-Weighted Average Price for secure external price referencing.
- **Slippage Protection**: Users specify minimum output for swaps.

### Changes
- Added `contracts/mev-resistant-amm.clar` (>150 lines).
- Implemented `add-liquidity`, `submit-order`, and `finalize-batch`.
- Added `README.md` with usage instructions.

### Verification
- [x] Syntax checked with `clarinet check`
- [x] Manual review of logic (Batch ID increment, TWAP updates)
