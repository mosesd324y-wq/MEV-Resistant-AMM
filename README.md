# 🛡️ MEV-Resistant AMM

> A sandwich-proof Automated Market Maker (AMM) on Stacks with batch auctions and TWAP pricing.

## 🚀 Features

- **🛡️ Sandwich-Proof**: Uses batch auctions to execute orders at a uniform clearing price, preventing front-running and sandwich attacks.
- **⏱️ TWAP Pricing**: Time-Weighted Average Price oracle enables robust on-chain pricing.
- **💧 Liquidity Management**: Simple interface to add and remove liquidity.

## 📦 Contracts

### `mev-resistant-amm`
The core contract managing the AMM logic.

- `add-liquidity`: Provide STX and Token pairs.
- `submit-order`: Submit a swap order (queued for the current batch).
- `finalize-current-batch`: Process all queued orders and update the TWAP.
- `claim-order`: Withdraw swapped tokens after batch finalization.

## 🛠️ Usage

### Prerequisites
- [Clarinet](https://github.com/hirosystems/clarinet)
- Stacks Wallet

### Setup

```bash
clarinet new .
clarinet check
```

### Interactions

**Add Liquidity**
```clarity
(contract-call? .mev-resistant-amm add-liquidity token-x token-y u1000000 u1000000)
```

**Submit Order**
```clarity
(contract-call? .mev-resistant-amm submit-order token-x u50000 u100)
```

**Finalize Batch**
(Called every 6 blocks)
```clarity
(contract-call? .mev-resistant-amm finalize-current-batch)
```
