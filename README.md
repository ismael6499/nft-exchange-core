# 🏪 NFT Exchange Core: Atomic Settlement Protocol

A trustless, decentralized exchange protocol for ERC-721 assets, featuring atomic settlement logic, configurable fee structures, and defensive security patterns against DoS attacks.

## 🚀 Engineering Context

As a **Java Software Engineer**, building an E-commerce platform typically involves utilizing a database transaction manager (like Spring's `@Transactional`) to handle inventory updates and integrating third-party payment gateways (Stripe/PayPal) for settlement.

In **Solidity**, "settlement" is immediate and irreversible. This project explores the **Atomic Swap** pattern: ensuring that the asset transfer (NFT) and the value transfer (ETH) happen in the exact same transaction block, or fail entirely. It removes the need for an escrow intermediary or off-chain reconciliation.

## 💡 Project Overview

**NFT Exchange Core** is a smart contract system that facilitates the non-custodial listing and purchasing of NFTs. It implements a dual-fee model (Listing Fee + Platform Fee) and enforces strict checks to prevent common market exploits.

### 🔍 Key Technical Features:

* **Atomic Settlement & Fee Splitting:**
    * **Logic:** The `buyNft` function calculates the platform fee (in Basis Points), transfers the net amount to the seller, and the fee to the protocol in a single execution flow.
    * **Precision:** Implemented granular fee calculation using Basis Points (BPS) (`fee * feeBps / 10000`) to avoid rounding errors common in integer arithmetic.

* **Defensive Transfer Logic (DoS Prevention):**
    * **The Problem:** If a seller's address is a smart contract that reverts on receiving ETH, it could permanently lock an item or break the marketplace flow.
    * **The Solution:** The protocol explicitly handles failure cases. I wrote specific Foundry tests (`RevertingSeller`) to simulate hostile actors rejecting ETH, ensuring the protocol reverts safely rather than leaving the state inconsistent.

* **Security Patterns:**
    * **Reentrancy Protection:** Applied `nonReentrant` modifiers to all functions performing external ETH calls (`buyNft`) to prevent reentrancy attacks during the value transfer.
    * **State-First Design:** Follows the "Checks-Effects-Interactions" pattern, deleting the listing from storage *before* transferring the asset to prevent re-listing exploits.

## 🛠️ Stack & Tools

* **Language:** Solidity `0.8.24`.
* **Testing:** Foundry (Forge).
    * *Highlights:* Usage of Mocks (`MockNFT`) and hostile contracts (`RevertingReceiver`) to test edge cases.
* **Standards:** ERC-721, Ownable.

---

*This repository contains the core settlement logic for a decentralized marketplace infrastructure.*