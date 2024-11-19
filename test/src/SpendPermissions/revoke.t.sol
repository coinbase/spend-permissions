// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";

import {Vm} from "forge-std/Test.sol";

contract RevokeTest is SpendPermissionManagerBase {
    function setUp() public {
        _initializeSpendPermissionManager();
    }

    function test_revoke_revert_invalidSender(
        address sender,
        address account,
        address spender,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(token != address(0));
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);
        vm.assume(sender != address(0));
        vm.assume(sender != account);

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: account,
            spender: spender,
            token: token,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });

        vm.prank(account);
        mockSpendPermissionManager.approve(spendPermission);
        assertTrue(mockSpendPermissionManager.isValid(spendPermission));
        vm.startPrank(sender);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.InvalidSender.selector, sender, account));
        mockSpendPermissionManager.revoke(spendPermission);
        vm.stopPrank();
    }

    function test_revoke_success_isNoLongerAuthorized(
        address account,
        address spender,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(token != address(0));
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: account,
            spender: spender,
            token: token,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        vm.startPrank(account);
        mockSpendPermissionManager.approve(spendPermission);
        assertTrue(mockSpendPermissionManager.isValid(spendPermission));
        mockSpendPermissionManager.revoke(spendPermission);
        assertFalse(mockSpendPermissionManager.isValid(spendPermission));
    }

    function test_revoke_success_emitsEvent(
        address account,
        address spender,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(token != address(0));
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: account,
            spender: spender,
            token: token,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        vm.startPrank(account);
        mockSpendPermissionManager.approve(spendPermission);
        assertTrue(mockSpendPermissionManager.isValid(spendPermission));
        vm.expectEmit(address(mockSpendPermissionManager));
        emit SpendPermissionManager.SpendPermissionRevoked({
            hash: mockSpendPermissionManager.getHash(spendPermission),
            spendPermission: spendPermission
        });
        mockSpendPermissionManager.revoke(spendPermission);
    }

    function test_revoke_success_returnsEarlyNoEventIfAlreadyRevoked(
        address account,
        address spender,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(token != address(0));
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: account,
            spender: spender,
            token: token,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        vm.startPrank(account);
        mockSpendPermissionManager.approve(spendPermission);
        assertTrue(mockSpendPermissionManager.isValid(spendPermission));
        mockSpendPermissionManager.revoke(spendPermission); // first revoke
        vm.recordLogs();
        mockSpendPermissionManager.revoke(spendPermission); // second revoke
        vm.getRecordedLogs();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertTrue(logs.length == 0);
        assertFalse(mockSpendPermissionManager.isValid(spendPermission));
    }
}
