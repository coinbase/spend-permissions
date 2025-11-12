// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SpendPermissionManager} from "../SpendPermissionManager.sol";
import {NativeTokenHook} from "../hooks/NativeTokenHook.sol";
import {SpendPermissionManagerBaseHookTest} from "./SpendPermissionManagerBaseHookTest.sol";

contract NativeTokenHook_HappyPath_Test is SpendPermissionManagerBaseHookTest {
    function setUp() public {
        _initializeSpendPermissionManager();

        vm.startPrank(owner);
        account.addOwnerAddress(address(mockSpendPermissionManager));
        vm.stopPrank();
    }

    function test_nativeTokenHook_spend_success(
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        uint160 spend
    ) public {
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);
        vm.assume(spend > 0);
        vm.assume(allowance >= spend);

        SpendPermissionManager.SpendPermission memory spendPermission = _createSpendPermission();
        spendPermission.spender = spender;
        spendPermission.start = start;
        spendPermission.end = end;
        spendPermission.period = period;
        spendPermission.allowance = allowance;
        spendPermission.salt = salt;
        spendPermission.hookConfig.hook = address(nativeTokenHook);
        spendPermission.hookConfig.hookData = hex"";

        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);

        vm.deal(address(account), allowance);
        vm.deal(spender, 0);

        vm.warp(start);

        vm.startPrank(spender);
        mockSpendPermissionManager.approveWithSignature(spendPermission, signature);
        mockSpendPermissionManager.spend(spendPermission, spend, hex"");
        vm.stopPrank();

        assertEq(address(account).balance, allowance - spend);
        assertEq(spender.balance, spend);

        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period, end));
        assertEq(usage.spend, spend);
    }
}

