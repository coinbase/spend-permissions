// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SpendPermissionManager} from "../../src/SpendPermissionManager.sol";
import {CoinbaseSmartWalletFactory} from "smart-wallet/CoinbaseSmartWalletFactory.sol";

contract MockSpendPermissionManager is SpendPermissionManager {
    constructor(CoinbaseSmartWalletFactory _factory) SpendPermissionManager(_factory) {}

    function useSpendPermission(SpendPermission memory spendPermission, uint256 value) public {
        _useSpendPermission(spendPermission, value);
    }

    function validateSignature(SpendPermission calldata spendPermission, bytes calldata signature) public {
        _validateSignature(spendPermission, signature);
    }
}
