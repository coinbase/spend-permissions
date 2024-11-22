// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PublicERC6492Validator} from "../../src/PublicERC6492Validator.sol";
import {SpendPermissionManager} from "../../src/SpendPermissionManager.sol";

contract MockSpendPermissionManager is SpendPermissionManager {
    constructor(PublicERC6492Validator _publicERC6492Validator, address _magicSpend)
        SpendPermissionManager(_publicERC6492Validator, _magicSpend)
    {}

    function useSpendPermission(SpendPermission memory spendPermission, uint256 value) public {
        _useSpendPermission(spendPermission, value);
    }
}
