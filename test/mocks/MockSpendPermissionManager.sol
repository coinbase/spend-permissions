// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PublicERC6492Validator} from "../../src/PublicERC6492Validator.sol";
import {SpendPermissionManager} from "../../src/SpendPermissionManager.sol";

contract MockSpendPermissionManager is SpendPermissionManager {
    constructor(PublicERC6492Validator _publicERC6492Validator) SpendPermissionManager(_publicERC6492Validator) {}

    function useSpendPermission(SpendPermission memory spendPermission, uint256 value) public {
        _useSpendPermission(spendPermission, value);
    }

    function extractOwnerIndexFromSignatureWrapper(bytes calldata signature) public pure returns (uint256) {
        return _extractOwnerIndexFromSignatureWrapper(signature);
    }
}
