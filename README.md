# ⚡ NFT Exchange Core: Atomic Settlement Protocol

![Solidity](https://img.shields.io/badge/Solidity-0.8.24-363636?style=flat-square&logo=solidity)
![Framework](https://img.shields.io/badge/Framework-Foundry-bf4904?style=flat-square&logo=rust)
![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)

A robust, non-custodial exchange protocol for ERC-721 assets, engineered for **atomic settlement** and **gas efficiency**.

The system ensures that asset (NFT) and value (ETH) transfers occur within a single transaction block, removing the need for off-chain reconciliation or escrow intermediaries. It implements defensive coding patterns to mitigate common Denial of Service (DoS) vectors found in decentralized marketplaces.

## 🏗 Architecture & Design Decisions

### 1. Gas Optimization (EVM-First Design)
- **Custom Errors:** Utilizes `error Name()` instead of expensive string-based `require` statements to reduce deployment and runtime gas costs.
- **Storage Efficiency:** Implemented constant variables for immutable values (e.g., `MAX_BPS`) to minimize storage read operations.

### 2. Security Patterns
- **DoS Prevention (Defensive Transfer Logic):**
  - The protocol uses low-level `.call` instead of `.transfer` to accommodate smart contract wallets and prevent gas limit issues during settlement.
  - **Explicit Failure Handling:** Return values from all external calls are strictly validated (`if (!success) revert()`) to prevent inconsistent states if a recipient contract reverts.
- **Checks-Effects-Interactions (CEI):** Strict adherence to the CEI pattern where listings are deleted from storage *before* external asset or value transfers to mitigate reentrancy risks.
- **Reentrancy Protection:** Integrated `ReentrancyGuard` on high-value functions as an additional security layer.

### 3. Financial Precision
- **Basis Points (BPS):** Fee calculations utilize a BPS system (1/10000th) to ensure granular precision and avoid rounding errors during fee splitting between sellers and the protocol.

## 🧪 Testing Strategy (Foundry)

The protocol is validated using **Foundry** with a focus on edge cases and defensive logic.

| Test Category | Focus |
| :--- | :--- |
| **Unit Testing** | Full coverage of listing, buying, and cancellation flows. |
| **Hostile Actors** | Simulation of `RevertingSeller` and `RevertingReceiver` to verify the protocol fails gracefully rather than locking assets. |
| **Edge Cases** | Validation of zero-fee scenarios, self-purchasing prevention, and administrative permission checks. |

### Running the tests

```bash
# Install dependencies
forge install

# Run tests
forge test -vvv

# Check coverage
forge coverage
