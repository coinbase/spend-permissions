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
    ) external view override returns (bytes memory callData) {
        return abi.encodeWithSelector(
            CoinbaseSmartWallet.execute.selector,
            spendPermission.token,
            0,
            abi.encodeWithSelector(IERC20.approve.selector, address(PERMIT3), value)
        );
    }
}
