// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MagicSpend} from "magicspend/MagicSpend.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";

import {SpendPolicy} from "../policies/SpendPolicy.sol";
import {SpendHook} from "./SpendHook.sol";

contract MagicSpendSpendHook is SpendHook {
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address public immutable MAGIC_SPEND;
    SpendPolicy public immutable SPEND_PERMISSION_POLICY;

    error SpendTokenWithdrawAssetMismatch(address spendToken, address withdrawAsset);
    error SpendValueWithdrawAmountMismatch(uint256 spendValue, uint256 withdrawAmount);
    error InvalidWithdrawRequestNonce(uint128 noncePostfix, uint128 permissionHashPostfix);

    constructor(address spendPermissionPolicy, address magicSpend) {
        SPEND_PERMISSION_POLICY = SpendPolicy(payable(spendPermissionPolicy));
        MAGIC_SPEND = magicSpend;
    }

    function prepare(
        SpendPolicy.SpendPermission calldata spendPermission,
        uint160 value,
        bytes calldata hookData
    ) external override returns (CoinbaseSmartWallet.Call[] memory calls) {
        MagicSpend.WithdrawRequest memory withdrawRequest = abi.decode(hookData, (MagicSpend.WithdrawRequest));

        if (
            !(spendPermission.token == NATIVE_TOKEN && withdrawRequest.asset == address(0))
                && spendPermission.token != withdrawRequest.asset
        ) revert SpendTokenWithdrawAssetMismatch(spendPermission.token, withdrawRequest.asset);

        if (withdrawRequest.amount > value) revert SpendValueWithdrawAmountMismatch(value, withdrawRequest.amount);

        bytes32 permissionHash = SPEND_PERMISSION_POLICY.getHash(spendPermission);
        if (uint128(withdrawRequest.nonce) != uint128(uint256(permissionHash))) {
            revert InvalidWithdrawRequestNonce(uint128(withdrawRequest.nonce), uint128(uint256(permissionHash)));
        }

        if (spendPermission.token == NATIVE_TOKEN) {
            revert SpendPolicy.SpendPermissionNotCallableForNativeToken();
        }

        calls = new CoinbaseSmartWallet.Call[](2);
        calls[0] = CoinbaseSmartWallet.Call({
            target: MAGIC_SPEND, value: 0, data: abi.encodeWithSelector(MagicSpend.withdraw.selector, withdrawRequest)
        });
        calls[1] = CoinbaseSmartWallet.Call({
            target: spendPermission.token,
            value: 0,
            data: abi.encodeWithSelector(IERC20.approve.selector, address(SPEND_PERMISSION_POLICY), value)
        });
    }
}

