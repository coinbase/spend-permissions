// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";

import {SpendPolicy} from "../policies/SpendPolicy.sol";
import {SpendHook} from "./SpendHook.sol";

contract NativeTokenSpendHook is SpendHook {
    address internal constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    error NotNativeToken(address token);

    address public immutable SPEND_PERMISSION_POLICY;

    constructor(address spendPermissionPolicy) {
        SPEND_PERMISSION_POLICY = spendPermissionPolicy;
    }

    function prepare(
        SpendPolicy.SpendPermission calldata spendPermission,
        uint160 value,
        bytes calldata
    ) external view override returns (CoinbaseSmartWallet.Call[] memory) {
        if (spendPermission.token != NATIVE_TOKEN) revert NotNativeToken(spendPermission.token);
        CoinbaseSmartWallet.Call[] memory calls = new CoinbaseSmartWallet.Call[](1);
        // Transfer ETH from the account into the spend-permission policy, so it can finalize in `afterExecute`.
        calls[0] = CoinbaseSmartWallet.Call({target: SPEND_PERMISSION_POLICY, value: value, data: bytes("")});
        return calls;
    }
}

