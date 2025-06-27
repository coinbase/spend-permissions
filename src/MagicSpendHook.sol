// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SpendPermission} from "./Permit3.sol";

import {Permit3} from "./Permit3.sol";
import {MagicSpend} from "magicspend/MagicSpend.sol";
import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";

/// @title MagicSpendHook
/// @notice Hook implementation for integrating MagicSpend withdrawals with spend permissions
/// @dev This contract is designed to be used as a delegate via delegatecall from Permit3
contract MagicSpendHook {
    /// @notice ERC-7528 native token address convention
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice Permit3 contract address
    Permit3 public permit3;

    /// @notice `SpendPermission.token` and `WithdrawRequest.asset` are not equal.
    error SpendTokenWithdrawAssetMismatch(address spendToken, address withdrawAsset);

    /// @notice Attempted spend value is less than the `WithdrawRequest.amount`.
    error SpendValueWithdrawAmountMismatch(uint256 spendValue, uint256 withdrawAmount);

    /// @notice `WithdrawRequest.nonce` is not postfixed with the lower 128 bits of the spend permission hash.
    error InvalidWithdrawRequestNonce(uint128 noncePostfix, uint128 permissionHashPostfix);

    /// @notice Invalid hookData format for MagicSpend withdrawal.
    error InvalidMagicSpendHookData();

    constructor(Permit3 _permit3) {
        permit3 = _permit3;
    }

    /// @notice Apply MagicSpend withdrawal logic before token transfer
    /// @dev Expects hookData to contain ABI-encoded MagicSpend address and WithdrawRequest
    /// @param spendPermission Details of the spend permission
    /// @param value Amount being spent
    /// @param hookData ABI-encoded (address magicSpend, MagicSpend.WithdrawRequest withdrawRequest)
    function applyHookData(SpendPermission calldata spendPermission, uint160 value, bytes calldata hookData) external {
        // Decode hookData to extract MagicSpend address and withdraw request
        (address magicSpend, MagicSpend.WithdrawRequest memory withdrawRequest) =
            abi.decode(hookData, (address, MagicSpend.WithdrawRequest));

        // Validate hookData was decoded properly
        if (magicSpend == address(0)) revert InvalidMagicSpendHookData();

        // Check spend token and withdraw asset are the same
        if (
            !(spendPermission.token == NATIVE_TOKEN && withdrawRequest.asset == address(0))
                && spendPermission.token != withdrawRequest.asset
        ) {
            revert SpendTokenWithdrawAssetMismatch(spendPermission.token, withdrawRequest.asset);
        }

        // Check spend value is not less than withdraw request amount
        if (withdrawRequest.amount > value) {
            revert SpendValueWithdrawAmountMismatch(value, withdrawRequest.amount);
        }

        // Check withdraw request nonce postfix matches spend permission hash postfix
        bytes32 permissionHash = permit3.getHash(spendPermission);
        if (uint128(withdrawRequest.nonce) != uint128(uint256(permissionHash))) {
            revert InvalidWithdrawRequestNonce(uint128(withdrawRequest.nonce), uint128(uint256(permissionHash)));
        }

        // Execute withdraw call on MagicSpend to fund the account
        _execute({
            account: spendPermission.account,
            target: magicSpend,
            value: 0,
            data: abi.encodeWithSelector(MagicSpend.withdraw.selector, withdrawRequest)
        });
    }

    function _execute(address account, address target, uint256 value, bytes memory data) internal {
        CoinbaseSmartWallet(payable(account)).execute({target: target, value: value, data: data});
    }
}
