# Spend Permissions

> :information_source: These contracts are unaudited. Please use at your own risk.

**Spend Permissions enable apps to spend native and ERC-20 tokens on behalf of users.**

## Design Overview

### 1. Periphery addition to Coinbase Smart Wallet V1

While implementing this feature as a new V2 wallet implementation was tempting, we decided to leverage the modular owner system from [Smart Wallet V1](https://github.com/coinbase/smart-wallet) and avoid a hard upgrade. This helped reduce our launch timeline and also reduced the risk of introducing this unique account authentication paradigm.

### 2. Only Native and ERC-20 token support

Spend Permissions only support spending Native (e.g. ETH) and ERC-20 (e.g. USDC) tokens with a recurring allowance refresh. This enables use cases like subscriptins (e.g 10 USDC per month) out of the box and also can support apps that want to limit asking users for spend permissions every session.

Compared to an approach that enables apps to make arbitrary external calls from user accounts, we consider this implementation safer given the tighter and fully-known scope of account control.

### 3. Spender-originated calls

Spend Permissions allow users to delegate token spending to a `spender` address, presumably controlled by the app. When an app wants to spend user tokens, it has `spender` call into the user account through a middleware contract, `SpendPermissionManager`, which validates the spend is within the approved allowance.

Compared to an approach that uses the ERC-4337 EntryPoint to prompt external calls from user accounts, we consider this implementation safer given the avoided edge case of accounting for when ERC-4337 Paymasters spend user tokens.

## End-to-end Journey

### 1. App requests permissions from user (offchain)

Apps request spend permissions from users by sending an `eth_signTypedData` request containing the permission details.

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

Apps approve their permission by calling `SpendPermissionManager.approveWithSignature` using the signature returned from the wallet when [requesting spend permissions](requestSpendPermission.md).

```mermaid
sequenceDiagram
    autonumber
    participant S as Spender
    participant PM as Permission Manager
    participant A as Account
    participant F as Factory

    S->>PM: approveWithSignature
    Note over PM: validate signature
    opt if 6492 initCode
        PM->>F: createAccount
        F->>A: create2
    end
    PM->>A: isValidSignature
    A-->>PM: EIP-1271 magic value
    Note over PM: revert or store approval
```

### 3. User revokes permission (onchain)

Users can revoke permissions at any time by calling `SpendPermissionManager.revoke`, which can also be batched via `CoinbaseSmartWallet.executeBatch`.

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
