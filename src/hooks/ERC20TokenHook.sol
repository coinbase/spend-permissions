// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";

import {SpendPermissionManager} from "../SpendPermissionManager.sol";
import {SpendHook} from "./SpendHook.sol";

contract ERC20TokenHook is SpendHook {
    constructor(address permit3) SpendHook(permit3) {}

    function onSpend(
        SpendPermissionManager.SpendPermission calldata spendPermission,
        uint160 value,
        bytes memory hookData
    ) external override returns (bytes memory callData) {
        CoinbaseSmartWallet.Call memory call = CoinbaseSmartWallet.Call({
            target: spendPermission.token,
            value: 0,
            data: abi.encodeWithSelector(IERC20.approve.selector, address(PERMIT3), value)
        });

        return abi.encodeWithSelector(CoinbaseSmartWallet.execute.selector, call);
    }
}
