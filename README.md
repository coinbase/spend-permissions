# Spend Permissions

> :information_source: These contracts are unaudited. Please use at your own risk.

**Spend Permissions enable apps to spend native and ERC-20 tokens on behalf of users.**

## Design Overview

### 1. Periphery addition to Coinbase Smart Wallet V1

While implementing this feature as a new V2 wallet implementation was tempting, we decided to leverage the modular owner system from [Smart Wallet V1](https://github.com/coinbase/smart-wallet) and avoid a hard upgrade.

### 2. Only Native and ERC-20 token support

Spend Permissions only supports spending Native (e.g. ETH) and ERC-20 (e.g. USDC) tokens on a recurring period. This enables use cases like subscriptions out of the box (e.g 10 USDC per month) and also can support apps that want to avoid asking users for spend permissions every session.

This approach does **not** enable apps to make arbitrary external calls from user accounts, improving security by having a tighter and fully-known scope of account control.

### 3. Spender-originated calls

Spend Permissions allow users to delegate token spending to a `spender` address, presumably controlled by the app. When an app wants to spend user tokens, it calls into `SpendPermissionManager` from this `spender` address. `SpendPermissionManager` will then validate the spend is within the approved permission's allowance and calls into the user's account to transfer tokens.

This approach does **not** use the ERC-4337 EntryPoint to prompt external calls from user accounts, improving security by avoiding the possibility of ERC-4337 Paymasters spending users' tokens on gas fees.

## End-to-end Journey

### 1. App requests and user signs permissions (offchain)

Apps request spend permissions for users to sign by sending an `eth_signTypedData` RPC request containing the permission details.

Read more details [here](./docs/diagrams/signSpendPermission.md).

```mermaid
sequenceDiagram
    autonumber
    participant A as App
    participant WF as Wallet Frontend
    participant U as User
    participant WB as Wallet Backend

    A->>WF: eth_signTypedData
    WF->>U: approve permission
    U-->>WF: signature
    WF->>WB: get account status
    WB-->>WF: deploy status, initCode, current + pending owners
    alt  account not deployed && manager in initCode
        Note right of WF: wrap signature in ERC-6492
    else manager not in initCode && manager not owner
        WF->>U: add manager
        U-->>WF: signature
    end
    WF-->>A: signature
```

### 2. App approves and spends (onchain)

Spenders (apps) spend tokens by calling `SpendPermissionManager.spend` with their spend permission values, a recipient, and an amount of tokens to spend.

Spenders may want to batch this call with an additionally prepended call to [approve their permission via user signature](./approveWithSignature.md) or the convenience function `SpendPermissionManager.spendWithSignature`.

Read more details [here](./docs/diagrams/spend.md).

```mermaid
sequenceDiagram
    autonumber
    participant S as Spender
    participant PM as Permission Manager
    participant A as Account
    participant ERC20

    opt
        S->>PM: approveWithSignature
    Note over PM: validate signature and store approval
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

### 3. User revokes permission (onchain)

Users can revoke permissions at any time by calling `SpendPermissionManager.revoke`, which can also be batched via `CoinbaseSmartWallet.executeBatch`.

Read more details [here](./docs/diagrams/revoke.md).

```mermaid
sequenceDiagram
    autonumber
    participant E as Entrypoint
    participant A as Account
    participant PM as Permission Manager

    Note over E: Validation phase
    E->>A: validateUserOp
    A-->>E: validation data
    Note over E: Execution phase
    E->>A: executeBatch
    loop
        A->>PM: revoke
        Note over A,PM: SpendPermission data
    end
```
