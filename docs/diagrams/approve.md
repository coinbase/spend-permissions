# Approve Permissions

While the default experience is for apps to request the user [sign spend permissions](signSpendPermission.md) and [approve with signatures](./approveWithSignature.md), it can also be valuable to approve permissions via direct calls to `SpendPermissionManager.approve`. For example, paying now to start a subscription and approving a permission to pay the same amount every month.

```mermaid
sequenceDiagram
    autonumber
    participant E as Entrypoint
    participant A as Account
    participant PM as Permission Manager
    participant EC as External Contract

    Note over E: Validation phase
    E->>A: validateUserOp
    A-->>E: validation data
    Note over E: Execution phase
    E->>A: executeBatch
    opt
        A->>EC: call
    end
    A->>PM: approve
    Note over A,PM: SpendPermission data
```
