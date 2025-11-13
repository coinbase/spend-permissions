// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";

import {SpendPermissionManager} from "../SpendPermissionManager.sol";
import {SpendHook} from "./SpendHook.sol";

contract SubAccountsHook is SpendHook {
    constructor(address permit3) SpendHook(permit3) {}
    /// @notice ERC-7528 native token address convention (https://eips.ethereum.org/EIPS/eip-7528).
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function onSpend(
        SpendPermissionManager.SpendPermission calldata spendPermission,
        uint160 value,
        bytes memory hookData
    ) external view override returns (bytes memory callData) {
        // decode hook data to get the sub account address
        (address subAccount) = abi.decode(spendPermission.hookConfig, (address));

        // native token case
        if (spendPermission.token == NATIVE_TOKEN) {
            CoinbaseSmartWallet.Call[] memory nativeTokenCall = new CoinbaseSmartWallet.Call[](1);
            nativeTokenCall[0] = CoinbaseSmartWallet.Call({
                target: subAccount,
                value: 0,
                data: abi.encodeWithSelector(CoinbaseSmartWallet.execute.selector, address(PERMIT3), value, "")
            });
            return abi.encodeWithSelector(CoinbaseSmartWallet.executeBatch.selector, nativeTokenCall);
        }
        // ERC-20 token case
        else {
            CoinbaseSmartWallet.Call[] memory erc20TokenCalls = new CoinbaseSmartWallet.Call[](2);
            // encode a call to approve Permit3 to spend the ERC-20 tokens
            erc20TokenCalls[0] = CoinbaseSmartWallet.Call({
                target: spendPermission.token,
                value: 0,
                data: abi.encodeWithSelector(IERC20.approve.selector, address(PERMIT3), value)
            });
            // encode a call to transfer the ERC-20 tokens from the sub account
            erc20TokenCalls[1] = CoinbaseSmartWallet.Call({
                target: subAccount,
                value: 0,
                data: abi.encodeWithSelector(
                    CoinbaseSmartWallet.execute.selector,
                    spendPermission.token,
                    0,
                    abi.encodeWithSelector(IERC20.transfer.selector, spendPermission.account, value)
                )
            });
            return abi.encodeWithSelector(CoinbaseSmartWallet.executeBatch.selector, erc20TokenCalls);
        }
    }
}
