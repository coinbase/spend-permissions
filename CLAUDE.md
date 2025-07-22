# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Solidity smart contract project for **Spend Permissions**, which enables apps to spend native and ERC-20 tokens on behalf of users through a permission-based system. The project is built using the Foundry toolkit for Ethereum development.

### Key Contracts

- **SpendPermissionManager** (`src/SpendPermissionManager.sol`): Main contract that manages spend permissions, allowing external entities to spend user tokens within defined limits and time periods
- **PublicERC6492Validator** (`src/PublicERC6492Validator.sol`): Validates ERC-6492 signatures and performs contract deployment when necessary

### Core Architecture

The system works as a periphery addition to Coinbase Smart Wallet V1, where:
1. The `SpendPermissionManager` is added as an owner to user's smart wallets
2. Apps request spend permissions from users (signed off-chain via `eth_signTypedData`)
3. Apps can then spend user tokens by calling `SpendPermissionManager.spend()` within the approved constraints
4. Supports both native tokens (ETH) and ERC-20 tokens with recurring periods and allowances

## Development Commands

### Building and Testing
```bash
# Build the project
forge build

# Run all tests
forge test

# Run tests with verbosity
forge test -vvv

# Run specific test file
forge test --match-path test/src/SpendPermissions/spend.t.sol

# Run tests with gas reporting
forge test --gas-report

# Format code
forge fmt
```

### Deployment
```bash
# Deploy to testnet (example with Base Sepolia)
forge script Deploy --account dev --sender $SENDER --rpc-url $BASE_SEPOLIA_RPC --verify --broadcast -vvvv
```

### Dependencies

Key external dependencies (in `lib/` directory):
- **account-abstraction**: ERC-4337 account abstraction contracts
- **forge-std**: Foundry's standard library for testing
- **magicspend**: MagicSpend contract for funding accounts
- **openzeppelin-contracts**: OpenZeppelin contract library
- **smart-wallet**: Coinbase Smart Wallet implementation
- **solady**: Gas-optimized Solidity libraries
- **webauthn-sol**: WebAuthn signature verification

## Testing Structure

Tests are organized under `test/src/` by contract:
- `SpendPermissions/`: Tests for SpendPermissionManager functionality
- `PublicERC6492Validator/`: Tests for signature validation
- `base/`: Base test contracts and utilities
- `mocks/`: Mock contracts for testing

## Important Security Considerations

- The system is designed to prevent arbitrary external calls from user accounts (only token transfers)
- ERC-721 tokens are explicitly not supported to prevent NFT transfers
- The contracts have been audited by Spearbit (see `audits/` directory)
- Uses ERC-6492 for signature validation with side effects (contract deployment)

## Contract Deployments

The contracts are deployed at consistent addresses across multiple networks:
- `SpendPermissionManager`: `0xf85210B21cC50302F477BA56686d2019dC9b67Ad`
- `PublicERC6492Validator`: `0xcfCE48B757601F3f351CB6f434CB0517aEEE293D`

Networks include Base, Ethereum, Optimism, Arbitrum, Polygon, Zora, BSC, and Avalanche.