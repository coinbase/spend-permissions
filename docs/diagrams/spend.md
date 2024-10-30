# Spend Tokens

Spenders (apps) spend tokens by calling `SpendPermissionManager.spend` with their spend permission values, a recipient, and an amount of tokens to spend.

Spenders may want to batch this call with an additionally prepended call to [approve their permission via user signature](./approveWithSignature.md) or the convenience function `SpendPermissionManager.spendWithSignature`. After a permission is approved, it is cheaper to avoid re-validating the signature and approval by just calling `SpendPermissionManager.spend` for repeated use.

When executing a spend, `SpendPermissionManager` calls `CoinbaseSmartWallet.execute` with either a call to transfer native or ERC-20 tokens to the recipient. Only these two kinds of calls are allowed by the `SpendPermissionManager` on a `CoinbaseSmartWallet` for reduced risk.

```mermaid
sequenceDiagram
    autonumber
    participant S as Spender
    participant PM as Permission Manager
    participant A as Account
    participant ERC20

    alt
    S->>PM: approveWithSignature
    Note over PM: validate signature and store approval
    else
    A->>PM: approve
    end
    S->>PM: spend
    Note over PM: validate permission approved <br> and spend value within allowance
    PM->>A: execute
    Note over PM,A: transfer tokens
    alt token is ERC-7528 address
        A->>S: call{value}()
        Note over A,S: transfer native token to spender
    else else is ERC-20 contract
        A->>ERC20: transfer(spender, value)
        Note over A,ERC20: transfer ERC-20 to spender
    end
```
