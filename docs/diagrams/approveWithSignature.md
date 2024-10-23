# Approve Permission With Signature

Apps approve their permission by calling `SpendPermissionManager.approveWithSignature` using the signature returned from the wallet when [signing spend permissions](signSpendPermission.md).

If the signature is [ERC-6492](https://eips.ethereum.org/EIPS/eip-6492) formatted, `SpendPermissionManager` will automatically detect this and deploy the account on behalf of the app. Afterwards, it will call `isValidSignature` to verify the account signed the permission.

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
