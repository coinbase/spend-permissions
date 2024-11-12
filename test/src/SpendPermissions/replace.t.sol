// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";

contract ReplaceTest is SpendPermissionManagerBase {
    SpendPermissionManager.SpendPermission existingSpendPermission;
    SpendPermissionManager.PeriodSpend lastValidUpdatedPeriod;

    function setUp() public {
        _initializeSpendPermissionManager();
        vm.prank(owner);
        account.addOwnerAddress(address(mockSpendPermissionManager));

        // establish an existing spend permission and capture the last valid updated period
        existingSpendPermission = _createSpendPermission();
        vm.prank(address(account));
        mockSpendPermissionManager.approve(existingSpendPermission);
        lastValidUpdatedPeriod = mockSpendPermissionManager.getLastUpdatedPeriod(existingSpendPermission);
    }

    function test_replace_revert_invalidSender(
        address sender,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(sender != address(0));
        vm.assume(sender != address(account));
        SpendPermissionManager.SpendPermission memory newSpendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
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
        mockSpendPermissionManager.replace(existingSpendPermission, newSpendPermission, lastValidUpdatedPeriod);
        vm.stopPrank();
    }

    function test_replace_revert_invalidLastUpdatedPeriod(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(spender != address(account));
        vm.assume(start > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);
        vm.deal(address(account), 1 ether);

        SpendPermissionManager.SpendPermission memory newSpendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: spender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        // spend after having calculated the `lastValidUpdatedPeriod`
        vm.prank(existingSpendPermission.spender);
        mockSpendPermissionManager.spend(existingSpendPermission, 1 wei);
        // this will be the actual last
        SpendPermissionManager.PeriodSpend memory invalidLastUpdatedPeriod =
            mockSpendPermissionManager.getCurrentPeriod(existingSpendPermission);
        vm.startPrank(address(account));
        vm.expectRevert(
            abi.encodeWithSelector(
                SpendPermissionManager.InvalidLastUpdatedPeriod.selector,
                invalidLastUpdatedPeriod,
                lastValidUpdatedPeriod
            )
        );
        mockSpendPermissionManager.replace(existingSpendPermission, newSpendPermission, lastValidUpdatedPeriod);
        vm.stopPrank();
    }

    function test_replace_revert_mismatchedAccounts(
        address newAccount,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(newAccount != address(0));
        vm.assume(newAccount != address(account));
        SpendPermissionManager.SpendPermission memory newSpendPermission = SpendPermissionManager.SpendPermission({
            account: newAccount,
            spender: spender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        vm.startPrank(newAccount);
        vm.expectRevert(
            abi.encodeWithSelector(SpendPermissionManager.MismatchedAccounts.selector, address(account), newAccount)
        );
        mockSpendPermissionManager.replace(existingSpendPermission, newSpendPermission, lastValidUpdatedPeriod);
        vm.stopPrank();
    }

    function test_replace_success_oldRevokedNewApproved(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(spender != address(account));
        vm.assume(start > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

        SpendPermissionManager.SpendPermission memory newSpendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: spender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        vm.startPrank(address(account));
        mockSpendPermissionManager.replace(existingSpendPermission, newSpendPermission, lastValidUpdatedPeriod);
        vm.stopPrank();
        vm.assertFalse(mockSpendPermissionManager.isApproved(existingSpendPermission));
        vm.assertTrue(mockSpendPermissionManager.isApproved(newSpendPermission));
    }

    function test_replace_success_emitsEvents(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(spender != address(account));
        vm.assume(start > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

        SpendPermissionManager.SpendPermission memory newSpendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: spender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        vm.startPrank(address(account));
        vm.expectEmit(address(mockSpendPermissionManager));
        emit SpendPermissionManager.SpendPermissionRevoked({
            hash: mockSpendPermissionManager.getHash(existingSpendPermission),
            spendPermission: existingSpendPermission
        });
        vm.expectEmit(address(mockSpendPermissionManager));
        emit SpendPermissionManager.SpendPermissionApproved({
            hash: mockSpendPermissionManager.getHash(newSpendPermission),
            spendPermission: newSpendPermission
        });
        mockSpendPermissionManager.replace(existingSpendPermission, newSpendPermission, lastValidUpdatedPeriod);
        vm.stopPrank();
    }

    function test_replace_success_severalPeriodsTimeElapsed(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(spender != address(account));
        vm.assume(start > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

        SpendPermissionManager.SpendPermission memory newSpendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: spender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        vm.warp(existingSpendPermission.start + existingSpendPermission.period * 4);
        vm.startPrank(address(account));
        mockSpendPermissionManager.replace(existingSpendPermission, newSpendPermission, lastValidUpdatedPeriod);
        vm.stopPrank();
        vm.assertFalse(mockSpendPermissionManager.isApproved(existingSpendPermission));
        vm.assertTrue(mockSpendPermissionManager.isApproved(newSpendPermission));
    }

    function test_replace_success_nonZeroSpend(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(spender != address(account));
        vm.assume(start > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

        vm.deal(address(account), 1 ether);
        vm.prank(existingSpendPermission.spender);
        mockSpendPermissionManager.spend(existingSpendPermission, 1 wei);

        SpendPermissionManager.PeriodSpend memory latestPeriodSpend =
            mockSpendPermissionManager.getLastUpdatedPeriod(existingSpendPermission);
        SpendPermissionManager.SpendPermission memory newSpendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: spender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        vm.warp(existingSpendPermission.start + existingSpendPermission.period * 4);
        vm.startPrank(address(account));
        mockSpendPermissionManager.replace(existingSpendPermission, newSpendPermission, latestPeriodSpend);
        vm.stopPrank();
        vm.assertFalse(mockSpendPermissionManager.isApproved(existingSpendPermission));
        vm.assertTrue(mockSpendPermissionManager.isApproved(newSpendPermission));
    }
}
