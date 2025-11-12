// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";

import {SpendPermissionManager} from "../SpendPermissionManager.sol";
import {SpendHook} from "./SpendHook.sol";

contract NativeTokenHook is SpendHook {
    constructor(address permit3) SpendHook(permit3) {}

    function onSpend(
        SpendPermissionManager.SpendPermission calldata spendPermission,
        uint160 value,
        bytes memory hookData
    ) external override returns (bytes memory callData) {
        CoinbaseSmartWallet.Call memory call =
            CoinbaseSmartWallet.Call({target: address(PERMIT3), value: value, data: ""});

        return abi.encodeWithSelector(CoinbaseSmartWallet.execute.selector, call);
    }
}
