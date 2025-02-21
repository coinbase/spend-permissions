// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MagicSpend} from "magic-spend/MagicSpend.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";

import {IHooks} from "./HooksForwarder.sol";
import {Permit3} from "./Permit3.sol";
import {SpendPermission} from "./SpendPermission.sol";

contract CoinbaseSmartWalletHooks is IHooks {
    Permit3 immutable PERMIT3;
    address immutable MAGIC_SPEND;

    error SpendTokenWithdrawAssetMismatch(address spendToken, address withdrawAsset);
    error SpendValueWithdrawAmountMismatch(uint256 spendValue, uint256 withdrawAmount);
    error InvalidWithdrawRequestNonce(uint128 noncePostfix, uint128 permissionHashPostfix);

    constructor(address permit3, address magicSpend) {
        PERMIT3 = Permit3(payable(permit3));
        MAGIC_SPEND = magicSpend;
    }

    function preSpend(SpendPermission calldata spendPermission, uint256 value, bytes calldata hookData) external {
        if (msg.sender != address(PERMIT3.HOOKS_FORWARDER())) revert();

        // withdraw from magic spend if hookData present
        if (hookData.length > 0) {
            MagicSpend.WithdrawRequest memory withdrawRequest = abi.decode(hookData, (MagicSpend.WithdrawRequest));

            // check spend token and withdraw asset are the same
            if (
                !(spendPermission.token == PERMIT3.NATIVE_TOKEN() && withdrawRequest.asset == address(0))
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

            _execute({
                account: spendPermission.account,
                target: MAGIC_SPEND,
                value: 0,
                data: abi.encodeWithSelector(MagicSpend.withdraw.selector, withdrawRequest)
            });
        }

        if (spendPermission.token == PERMIT3.NATIVE_TOKEN()) {
            // call account to send native token to this contract
            _execute({account: spendPermission.account, target: address(PERMIT3), value: value, data: hex""});
        } else {
            // set allowance for this contract to spend exact value on behalf of account
            _execute({
                account: spendPermission.account,
                target: spendPermission.token,
                value: 0,
                data: abi.encodeWithSelector(IERC20.approve.selector, address(PERMIT3), value)
            });
        }
    }

    function postSpend(SpendPermission calldata spendPermission, uint256 value, bytes calldata hookData) external {}

    function _execute(address account, address target, uint256 value, bytes memory data) internal virtual {
        CoinbaseSmartWallet(payable(account)).execute({target: target, value: value, data: data});
    }
}
