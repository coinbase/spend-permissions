# Sign Spend Permission

Apps request spend permissions from users by sending an `eth_signTypedData` request containing the permission details.

Users are guided to sign the permission hash (or the hash of a batch of spend permissions) and add the `SpendPermissionManager` contract as an owner if it is not already. Signing to approve enables users to not spend gas on this action, offloading this cost to the app.

If a users account is not yet deployed, but has the `SpendPermissionManager` as an initial owner in its `initCode`, the returned signature is formatted according to [ERC-6492](https://eips.ethereum.org/EIPS/eip-6492) with the `CoinbaseSmartWalletFactory` address and this `initCode`.

This entire process takes place offchain and requires no transactions or network fees.

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
