// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";

import {SpendPolicy} from "../policies/SpendPolicy.sol";
import {SpendHook} from "./SpendHook.sol";

/// @notice Spend hook that grants the spend-permission policy an exact ERC20 allowance for `value`.
contract ERC20SpendHook is SpendHook {
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
        calls = new CoinbaseSmartWallet.Call[](1);
        calls[0] = CoinbaseSmartWallet.Call({
            target: spendPermission.token,
            value: 0,
            data: abi.encodeWithSelector(IERC20.approve.selector, SPEND_PERMISSION_POLICY, value)
        });
    }
}

