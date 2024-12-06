// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SpendPermission, SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";

contract IsRevokedTest is SpendPermissionManagerBase {
    function setUp() public {
        _initializeSpendPermissionManager();
    }

    function test_isRevoked_true(
        address account,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

        SpendPermission memory spendPermission = SpendPermission({
            account: account,
            spender: spender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        vm.startPrank(account);
        mockSpendPermissionManager.approve(spendPermission);
        vm.assertTrue(mockSpendPermissionManager.isValid(spendPermission));
        mockSpendPermissionManager.revoke(spendPermission);
        vm.assertTrue(mockSpendPermissionManager.isRevoked(spendPermission));
    }

    function test_isRevoked_false(
        address account,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

        SpendPermission memory spendPermission = SpendPermission({
            account: account,
            spender: spender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        // no approval
        vm.assertFalse(mockSpendPermissionManager.isValid(spendPermission));
        vm.prank(account);
        mockSpendPermissionManager.revoke(spendPermission);
        vm.assertTrue(mockSpendPermissionManager.isRevoked(spendPermission));
    }
}
