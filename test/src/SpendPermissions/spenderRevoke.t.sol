// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";

contract SpenderRevokeTest is SpendPermissionManagerBase {
    function setUp() public {
        _initializeSpendPermissionManager();
    }

    function test_spenderRevoke_revert_invalidSender(
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
        vm.assume(sender != spender);

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
        assertTrue(mockSpendPermissionManager.isApproved(spendPermission));
        vm.startPrank(sender);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.InvalidSender.selector, sender, account));
        mockSpendPermissionManager.spenderRevoke(spendPermission);
        vm.stopPrank();
    }

    function test_spenderRevoke_success_isNoLongerAuthorized(
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
        vm.prank(account);
        mockSpendPermissionManager.approve(spendPermission);
        assertTrue(mockSpendPermissionManager.isApproved(spendPermission));
        vm.prank(spender);
        mockSpendPermissionManager.spenderRevoke(spendPermission);
        assertFalse(mockSpendPermissionManager.isApproved(spendPermission));
    }

    function test_spenderRevoke_success_emitsEvent(
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
        vm.prank(account);
        mockSpendPermissionManager.approve(spendPermission);
        assertTrue(mockSpendPermissionManager.isApproved(spendPermission));
        vm.startPrank(spender);
        vm.expectEmit(address(mockSpendPermissionManager));
        emit SpendPermissionManager.SpendPermissionRevoked({
            hash: mockSpendPermissionManager.getHash(spendPermission),
            spendPermission: spendPermission
        });
        mockSpendPermissionManager.spenderRevoke(spendPermission);
    }
}
