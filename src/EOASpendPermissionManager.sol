// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {PublicERC6492Validator} from "./PublicERC6492Validator.sol";
import {SpendPermissionManager} from "./SpendPermissionManager.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract EOASpendPermissionManager is SpendPermissionManager {
    using SafeERC20 for IERC20;

    error NativeTokenNotSupported();

    constructor(PublicERC6492Validator publicERC6492Validator, address magicSpend)
        SpendPermissionManager(publicERC6492Validator, magicSpend)
    {}

    /// @inheritdoc SpendPermissionManager
    /// @dev Because EOAs cannot be called into, native token not supported and assumes existing infinite ERC20
    /// allowance
    function _transferFrom(address token, address account, address recipient, uint256 value) internal override {
        if (token == NATIVE_TOKEN) {
            revert NativeTokenNotSupported();
        } else {
            // use allowance to transfer from account to recipient, which will revert if transfer fails
            IERC20(token).safeTransferFrom(account, recipient, value);
        }
    }
}
