// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";

contract GetLastUpdatedPeriod is SpendPermissionManagerBase {
    function setUp() public {
        _initializeSpendPermissionManager();
        vm.prank(owner);
        account.addOwnerAddress(address(mockSpendPermissionManager));
    }

    function test_getLastUpdatedPeriod_success_noSpend(
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
        assumePayable(spender);
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
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
        vm.prank(address(account));
        mockSpendPermissionManager.approve(spendPermission);

        SpendPermissionManager.PeriodSpend memory lastUpdatedPeriod =
            mockSpendPermissionManager.getLastUpdatedPeriod(spendPermission);
        vm.assertEq(lastUpdatedPeriod.start, 0);
        vm.assertEq(lastUpdatedPeriod.end, 0);
        vm.assertEq(lastUpdatedPeriod.spend, 0);
    }

    function test_getLastUpdatedPeriod_success_someSpend(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData,
        uint160 spend
    ) public {
        vm.assume(spender != address(0));
        vm.assume(spender != address(account));
        assumePayable(spender);
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(spend > 0);
        vm.assume(allowance > 0);
        vm.assume(allowance >= spend);

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
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
        vm.deal(address(account), spendPermission.allowance);
        vm.prank(address(account));
        mockSpendPermissionManager.approve(spendPermission);
        vm.warp(start);
        vm.prank(spender);
        mockSpendPermissionManager.spend(spendPermission, spend);

        SpendPermissionManager.PeriodSpend memory lastUpdatedPeriod =
            mockSpendPermissionManager.getLastUpdatedPeriod(spendPermission);
        vm.assertEq(lastUpdatedPeriod.start, start);
        vm.assertEq(lastUpdatedPeriod.end, _safeAddUint48(start, period, end));
        vm.assertEq(lastUpdatedPeriod.spend, spend);
    }

    function test_getLastUpdatedPeriod_success_someSpend_elapsedTime(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData,
        uint160 spend
    ) public {
        vm.assume(spender != address(0));
        vm.assume(spender != address(account));
        assumePayable(spender);
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(spend > 0);
        vm.assume(allowance > 0);
        vm.assume(allowance >= spend);

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
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
        vm.deal(address(account), spendPermission.allowance);
        vm.prank(address(account));
        mockSpendPermissionManager.approve(spendPermission);
        vm.warp(start);
        vm.prank(spender);
        mockSpendPermissionManager.spend(spendPermission, spend);

        vm.warp(uint256(start) + uint256(period) * 4); // 4 periods have passed, regardless of end
        SpendPermissionManager.PeriodSpend memory lastUpdatedPeriod =
            mockSpendPermissionManager.getLastUpdatedPeriod(spendPermission);
        vm.assertEq(lastUpdatedPeriod.start, start);
        vm.assertEq(lastUpdatedPeriod.end, _safeAddUint48(start, period, end));
        vm.assertEq(lastUpdatedPeriod.spend, spend);
    }

    function test_getLastUpdatedPeriod_success_multipleSpends(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData,
        uint160 spend
    ) public {
        vm.assume(spender != address(0));
        vm.assume(spender != address(account));
        assumePayable(spender);
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(spend > 0);
        vm.assume(spend <= type(uint48).max / 3); // ensure we don't overflow
        vm.assume(allowance > 0);
        vm.assume(allowance >= spend * 3); // allow for up to 3 spends

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
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
        vm.deal(address(account), spendPermission.allowance);
        vm.prank(address(account));
        mockSpendPermissionManager.approve(spendPermission);
        vm.warp(start);
        vm.startPrank(spender);
        mockSpendPermissionManager.spend(spendPermission, spend);
        mockSpendPermissionManager.spend(spendPermission, spend);
        mockSpendPermissionManager.spend(spendPermission, spend);
        vm.stopPrank();

        SpendPermissionManager.PeriodSpend memory lastUpdatedPeriod =
            mockSpendPermissionManager.getLastUpdatedPeriod(spendPermission);
        vm.assertEq(lastUpdatedPeriod.start, start);
        vm.assertEq(lastUpdatedPeriod.end, _safeAddUint48(start, period, end));
        vm.assertEq(lastUpdatedPeriod.spend, spend * 3);
    }
}
