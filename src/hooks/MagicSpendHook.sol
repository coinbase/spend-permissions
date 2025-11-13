// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MagicSpend} from "magicspend/MagicSpend.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";

import {SpendPermissionManager} from "../SpendPermissionManager.sol";
import {SpendHook} from "./SpendHook.sol";

contract MagicSpendHook is SpendHook {
    /// @notice ERC-7528 native token address convention (https://eips.ethereum.org/EIPS/eip-7528).
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice MagicSpend singleton (https://github.com/coinbase/magicspend).
    address public immutable MAGIC_SPEND;

    /// @notice `SpendPermission.token` and `WithdrawRequest.asset` are not equal.
    ///
    /// @param spendToken Token belonging to the spend permission.
    /// @param withdrawAsset Asset belonging to the withdraw request.
    error SpendTokenWithdrawAssetMismatch(address spendToken, address withdrawAsset);

    /// @notice Attempted spend value is less than the `WithdrawRequest.amount`.
    ///
    /// @param spendValue Value attempting to spend, must not be less than withdraw amount.
    /// @param withdrawAmount Amount of asset attempting to withdraw from MagicSpend.
    error SpendValueWithdrawAmountMismatch(uint256 spendValue, uint256 withdrawAmount);

    /// @notice `WithdrawRequest.nonce` is not postfixed with the lower 128 bits of the spend permission hash.
    ///
    /// @param noncePostfix The lower 128 bits of the withdraw request nonce.
    /// @param permissionHashPostfix The lower 128 bits of the spend permission hash.
    error InvalidWithdrawRequestNonce(uint128 noncePostfix, uint128 permissionHashPostfix);

    constructor(address permit3, address magicSpend) SpendHook(permit3) {
        MAGIC_SPEND = magicSpend;
    }

    function onSpend(
        SpendPermissionManager.SpendPermission calldata spendPermission,
        uint160 value,
        bytes memory hookData
    ) external view override returns (bytes memory callData) {
        // decode withdraw request from hook data
        MagicSpend.WithdrawRequest memory withdrawRequest = abi.decode(hookData, (MagicSpend.WithdrawRequest));

        // check spend token and withdraw asset are the same
        if (
            !(spendPermission.token == NATIVE_TOKEN && withdrawRequest.asset == address(0))
                && spendPermission.token != withdrawRequest.asset
        ) {
            revert SpendTokenWithdrawAssetMismatch(spendPermission.token, withdrawRequest.asset);
        }

        // check spend value is not less than withdraw request amount
        if (withdrawRequest.amount > value) {
            revert SpendValueWithdrawAmountMismatch(value, withdrawRequest.amount);
        }

        // check withdraw request nonce postfix matches spend permission hash postfix.
        bytes32 permissionHash = PERMIT3.getHash(spendPermission);
        if (uint128(withdrawRequest.nonce) != uint128(uint256(permissionHash))) {
            revert InvalidWithdrawRequestNonce(uint128(withdrawRequest.nonce), uint128(uint256(permissionHash)));
        }

        // Prepare two-step flow:
        // 1) Withdraw from MagicSpend to the account
        // 2) If native, forward ETH to PERMIT3; if ERC20, approve PERMIT3 to spend `value`
        CoinbaseSmartWallet.Call[] memory calls = new CoinbaseSmartWallet.Call[](2);
        calls[0] = CoinbaseSmartWallet.Call({
            target: MAGIC_SPEND, value: 0, data: abi.encodeWithSelector(MagicSpend.withdraw.selector, withdrawRequest)
        });
        if (spendPermission.token == NATIVE_TOKEN) {
            calls[1] = CoinbaseSmartWallet.Call({target: address(PERMIT3), value: value, data: ""});
        } else {
            calls[1] = CoinbaseSmartWallet.Call({
                target: spendPermission.token,
                value: 0,
                data: abi.encodeWithSelector(IERC20.approve.selector, address(PERMIT3), value)
            });
        }
        return abi.encodeWithSelector(CoinbaseSmartWallet.executeBatch.selector, calls);
    }
}
