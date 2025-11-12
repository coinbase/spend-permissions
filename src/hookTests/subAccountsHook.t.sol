// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SpendPermissionManager} from "../SpendPermissionManager.sol";
import {SubAccountsHook} from "../hooks/SubAccountsHook.sol";
import {SpendPermissionManagerBaseHookTest} from "./SpendPermissionManagerBaseHookTest.sol";
import {MockCoinbaseSmartWallet} from "../../test/mocks/MockCoinbaseSmartWallet.sol";

contract SubAccountsHook_HappyPath_Test is SpendPermissionManagerBaseHookTest {
    SubAccountsHook subAccountsHook;
    MockCoinbaseSmartWallet subAccount;

    function setUp() public {
        _initializeSpendPermissionManager();
        subAccountsHook = new SubAccountsHook(address(mockSpendPermissionManager));
        subAccount = new MockCoinbaseSmartWallet();
        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(owner);
        subAccount.initialize(owners);

        // authorize PERMIT3 on the main account and main account on the sub-account
        vm.startPrank(owner);
        account.addOwnerAddress(address(mockSpendPermissionManager));
        subAccount.addOwnerAddress(address(account));
        vm.stopPrank();
    }

    function test_subAccountsHook_native_spend_success(
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
        spendPermission.token = NATIVE_TOKEN;
        spendPermission.start = start;
        spendPermission.end = end;
        spendPermission.period = period;
        spendPermission.allowance = allowance;
        spendPermission.salt = salt;
        spendPermission.hook = address(subAccountsHook);

        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);

        // fund the sub-account which will forward ETH to PERMIT3 via hook execution
        vm.deal(address(subAccount), spend);
        assertEq(address(subAccount).balance, spend);

        vm.warp(start);

        // hookData carries the sub-account address
        vm.startPrank(spender);
        mockSpendPermissionManager.approveWithSignature(spendPermission, signature);
        mockSpendPermissionManager.spend(spendPermission, spend, abi.encode(address(subAccount)));
        vm.stopPrank();

        // sub account forwarded to PERMIT3, which forwarded to spender
        assertEq(address(subAccount).balance, 0);
        assertEq(spender.balance, spend);

        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period, end));
        assertEq(usage.spend, spend);
    }
}


