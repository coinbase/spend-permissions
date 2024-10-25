// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";
import {Test, console2} from "forge-std/Test.sol";

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
        console2.log(extraData.length);
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

    function test_approve_revert_zeroPeriod(
        address account,
        address spender,
        uint48 start,
        uint48 end,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
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
            account: account,
            spendPermission: spendPermission
        });
        mockSpendPermissionManager.approve(spendPermission);
    }
}
