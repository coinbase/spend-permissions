// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";

import {Vm} from "forge-std/Test.sol";

contract ApproveTest is SpendPermissionManagerBase {
    function setUp() public {
        _initializeSpendPermissionManager();
    }

    function test_approve_revert_invalidSender(
        address sender,
        address account,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(sender != address(0));
        vm.assume(sender != account);
        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
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
        vm.startPrank(sender);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.InvalidSender.selector, sender, account));
        mockSpendPermissionManager.approve(spendPermission);
        vm.stopPrank();
    }

    function test_approve_revert_invalidStartEnd(
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
        vm.assume(period > 0);
        vm.assume(allowance > 0);

        vm.assume(start >= end);

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
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
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.InvalidStartEnd.selector, start, end));
        mockSpendPermissionManager.approve(spendPermission);
        vm.stopPrank();
    }

    function test_approve_revert_invalidTokenZeroAddress(
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

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: account,
            spender: spender,
            token: address(0),
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        vm.startPrank(account);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.ZeroToken.selector));
        mockSpendPermissionManager.approve(spendPermission);
        vm.stopPrank();
    }

    function test_approve_revert_invalidSpenderZeroAddress(
        address account,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(token != address(0));
        vm.assume(start < end);
        vm.assume(allowance > 0);

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: account,
            spender: address(0),
            token: token,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        vm.startPrank(account);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.ZeroSpender.selector));
        mockSpendPermissionManager.approve(spendPermission);
        vm.stopPrank();
    }

    function test_approve_revert_zeroPeriod(
        address account,
        address spender,
        uint48 start,
        uint48 end,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(start < end);

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: account,
            spender: spender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: 0,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        vm.startPrank(account);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.ZeroPeriod.selector));
        mockSpendPermissionManager.approve(spendPermission);
        vm.stopPrank();
    }

    function test_approve_revert_zeroAllowance(
        address account,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(start < end);
        vm.assume(period > 0);

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: account,
            spender: spender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: period,
            allowance: 0,
            salt: salt,
            extraData: extraData
        });
        vm.startPrank(account);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.ZeroAllowance.selector));
        mockSpendPermissionManager.approve(spendPermission);
        vm.stopPrank();
    }

    function test_approve_success_isAuthorized(
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

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
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
        vm.prank(account);
        mockSpendPermissionManager.approve(spendPermission);
        vm.assertTrue(mockSpendPermissionManager.isApproved(spendPermission));
    }

    function test_approve_success_emitsEvent(
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

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
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
        vm.expectEmit(address(mockSpendPermissionManager));
        emit SpendPermissionManager.SpendPermissionApproved({
            hash: mockSpendPermissionManager.getHash(spendPermission),
            spendPermission: spendPermission
        });
        mockSpendPermissionManager.approve(spendPermission);
    }

    function test_approve_success_returnsTrue(
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

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
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
        vm.prank(account);
        bool approved = mockSpendPermissionManager.approve(spendPermission);
        vm.assertTrue(approved);
        vm.assertTrue(mockSpendPermissionManager.isApproved(spendPermission));
    }

    function test_approve_success_returnsTrueNoEventEmittedIfAlreadyApproved(
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

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
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
        mockSpendPermissionManager.approve(spendPermission); // approve permission before second approval
        vm.recordLogs();
        bool approved = mockSpendPermissionManager.approve(spendPermission);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.assertEq(logs.length, 0); // no event emitted
        vm.assertTrue(approved);
        vm.assertTrue(mockSpendPermissionManager.isApproved(spendPermission));
    }

    function test_approve_success_returnsFalseIfPermissionRevoked(
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

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
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
        mockSpendPermissionManager.revoke(spendPermission); // revoke permission before approval
        vm.recordLogs();
        bool approved = mockSpendPermissionManager.approve(spendPermission);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.assertEq(logs.length, 0); // no event emitted
        vm.assertFalse(approved); // returns false
        vm.assertFalse(mockSpendPermissionManager.isApproved(spendPermission)); // permission is not approved
    }
}
