// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";

import {SpendPolicy} from "../policies/SpendPolicy.sol";
import {SpendHook} from "./SpendHook.sol";

contract SubAccountSpendHook is SpendHook {
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public immutable SPEND_PERMISSION_POLICY;

    constructor(address spendPermissionPolicy) {
        SPEND_PERMISSION_POLICY = spendPermissionPolicy;
    }

    function prepare(
        SpendPolicy.SpendPermission calldata spendPermission,
        uint160 value,
        bytes calldata hookData
    ) external override returns (CoinbaseSmartWallet.Call[] memory calls) {
        hookData;
        (address subAccount) = abi.decode(spendPermission.spendHookConfig, (address));

        if (spendPermission.token == NATIVE_TOKEN) {
            revert SpendPolicy.SpendPermissionNotCallableForNativeToken();
        }

        calls = new CoinbaseSmartWallet.Call[](2);
        calls[0] = CoinbaseSmartWallet.Call({
            target: subAccount,
            value: 0,
            data: abi.encodeWithSelector(
                CoinbaseSmartWallet.execute.selector,
                spendPermission.token,
                0,
                abi.encodeWithSelector(IERC20.transfer.selector, spendPermission.account, value)
            )
        });
        calls[1] = CoinbaseSmartWallet.Call({
            target: spendPermission.token,
            value: 0,
            data: abi.encodeWithSelector(IERC20.approve.selector, SPEND_PERMISSION_POLICY, value)
        });
    }
}

