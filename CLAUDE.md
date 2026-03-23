# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Building and Testing

- `forge build` - Compile all Solidity contracts
- `forge test` - Run all tests with basic verbosity
- `forge test -vv` - Run tests with increased verbosity (recommended)
- `forge test -vvvv` - Run tests with maximum verbosity for debugging
- `forge test --match-test testName` - Run specific test by name
- `forge test --match-contract ContractName` - Run specific tests by test contract
- `forge test --match-path "test/src/SpendRouter/*"` - Run tests by file path
- `forge test --gas-report` - Generate gas usage report
- `forge coverage --ir-minimum` - Generate test coverage report

### Development Workflow

- `forge clean` - Clean build artifacts
- `forge fmt` - Format Solidity code
- Always run `forge test -vv` before committing changes
- **After adding features or fixing bugs, execute `forge fmt` to ensure code is properly formatted**

## Protocol Overview

This repository contains the Spend Permissions Protocol, a system for managing token spending permissions for smart contract wallets. It enables users to authorize third-party spenders to pull tokens from their accounts within configurable limits (per-period allowances, time bounds, token types).

### Key Contracts

- `SpendPermissionManager.sol` - Core protocol contract managing EIP-712 signed spend permissions, handling approval, revocation, allowance tracking, signature validation, and token transfers.
- `SpendRouter.sol` - Stateless singleton router that decodes routing metadata (authorized executor, recipient) from a SpendPermission's extraData field, pulls tokens via SpendPermissionManager.spend(), and forwards them to the recipient. Supports both native ETH (ERC-7528) and ERC-20 tokens.
- `PublicERC6492Validator.sol` - Separate signature validation contract for unprivileged execution of ERC-6492 wrappers.

## File Structure

- `src/` - Core protocol contracts
  - `SpendPermissionManager.sol` - Main protocol
  - `SpendRouter.sol` - Spend-and-forward router
  - `PublicERC6492Validator.sol` - Signature validation
  - `policies/` - Policy implementations
- `test/` - Foundry tests
  - `base/` - Base test harness contracts (shared fixtures + helpers)
  - `mocks/` - Mock contracts for testing
  - `src/SpendPermissions/` - SpendPermissionManager unit tests
  - `src/SpendRouter/` - SpendRouter unit tests
  - `src/PublicERC6492Validator/` - Validator unit tests
- `lib/` - Dependencies (solady, forge-std, smart-wallet, etc.)

## Testing Notes

- Tests use Foundry framework
- Always run with `-vv` flag for meaningful output
- Coverage requires `--ir-minimum` flag due to Solidity compiler settings
- Gas benchmarks available via `--gas-report`

### Testing Conventions (project style)

- **Directory structure**:
  - Put shared harnesses/helpers/mocks in `test/base/` and `test/mocks/`.
  - Put unit tests in `test/src/<Area>/` and scope each `.t.sol` to a single function or tightly-related surface area.
- **Base harness pattern**:
  - Prefer `abstract contract <X>TestBase is Test` (or `<X>Base`) for shared deployment, fixtures, and helpers.
  - Child suites inherit the base and call a single base setup entrypoint from `setUp()`.
- **Stub-first workflow**:
  - Stub the case matrix first, then implement bodies.
  - Stub tests must be explicitly skipped via `vm.skip(true);` so `forge test` stays green while cases are being finalized.
- **Events**:
  - Each unique event emission should have its own dedicated test (even if redundant with another happy-path test).
- **NatSpec on tests**:
  - Unit tests should be documented with NatSpec.
  - Fuzz tests must include `@param` for every fuzz parameter.

## Claude Permissions and Workflow

- Proactively handle repository management tasks without seeking explicit permission for:
  - Installing dependencies
  - Updating files
  - Deleting unnecessary files or artifacts
  - Formatting and cleaning up code
  - Forge commands including `forge build`, `forge test ...` etc

## Solidity Coding Standards

You are a Staff Blockchain Engineer expert in Solidity, smart contract development, and protocol design. You write clean, secure, and properly documented smart contracts. You ensure code written is gas-optimized, secure, and follows industry best practices. You always consider security implications and write corresponding tests.

### Core Principles

- **Security First**: Always prioritize security over convenience. Follow checks-effects-interactions pattern.
- **Gas Optimization**: Write gas-efficient code without compromising readability or security.
- **Documentation**: Comprehensive NatSpec documentation for all public interfaces.

### Style Guide Compliance

#### Base Standard

Unless an exception or addition is specifically noted, we follow the [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html).

#### Key Exceptions and Additions

##### 1. Internal Library Functions

**Names of internal functions in a library should NOT have an underscore prefix.**

##### 2. Terminology

- **Use "onchain"** (one word, no hyphen) instead of "on-chain" or "on chain". Same for "offchain".

##### 3. Error Handling

- **Prefer custom errors** over `require` strings for gas efficiency
- **Custom error names should be CapWords style** (e.g., `InsufficientBalance`, `Unauthorized`)

##### 4. Events

- **Event names should be past tense** - Events track things that _happened_
- Example: `TokenTransferred` not `TokenTransfer`

##### 5. Mappings

**Prefer named parameters in mapping types** for clarity.

##### 6. Contract Architecture

- **Prefer composition over inheritance** when functions could reasonably be in separate contracts
- **Avoid writing interfaces** unless absolutely necessary - they separate NatSpec from logic
- **Avoid using assembly** unless gas savings are very consequential (>25%)

##### 7. Imports

**Use named imports** and order alphabetically.

##### 8. Testing Standards

- **Test file names**: `ContractName.t.sol` or `functionName.t.sol`
- **Test contract names**: `ContractNameTest` or `FunctionNameTest` (CapWords)
- **Test function names**: `test_outcome_optionalContext` or `test_functionName_outcome_optionalContext`

### Contract Layout (in order)

1. License identifier
2. Pragma statements
3. Import statements
4. Contract declaration
5. State variables (grouped by visibility)
6. Events
7. Errors
8. Modifiers
9. Constructor/Initializer
10. External functions
11. Public functions
12. Internal functions
13. Private functions

### Documentation Standards

#### NatSpec Requirements

- **All external functions, events, and errors should have complete NatSpec**
- Minimally include `@notice`
- Include `@param` and `@return` for parameters and return values
- Insert blank NatSpec lines between logical sections

### Security Standards

- Validate all inputs at function entry
- Check for zero addresses where applicable
- Update state before external calls
- Use reentrancy guards where needed

### Gas Optimization Guidelines

- Pack struct members efficiently (256-bit boundaries)
- Use mappings over arrays when possible for lookups
- Use `external` visibility when function won't be called internally
- Use `immutable` and `constant` appropriately
- Avoid unbounded loops

### Fuzz Testing

- Use `bound()` over `vm.assume()` when possible
- Define constants instead of magic numbers
- Every fuzz parameter must be used
- NatSpec every fuzz parameter with `@param`

### Code Quality Checklist

- [ ] License identifier present
- [ ] Pragma version specified
- [ ] Named imports used and ordered alphabetically
- [ ] NatSpec documentation complete
- [ ] Custom errors defined (CapWords style)
- [ ] Events emitted for state changes (past tense)
- [ ] Input validation implemented
- [ ] Access control enforced
- [ ] Gas optimization considered
- [ ] Security patterns followed
- [ ] Tests written and passing
- [ ] Assembly avoided unless >25% gas savings

# important-instruction-reminders

Do what has been asked; nothing more, nothing less.
NEVER create files unless they're absolutely necessary for achieving your goal.
ALWAYS prefer editing an existing file to creating a new one.
NEVER proactively create documentation files (\*.md) or README files. Only create documentation files if explicitly requested by the User.

## Testing Guidelines

- If I am telling you to create tests, and things don't work as expected based on README.md, then always let me know
