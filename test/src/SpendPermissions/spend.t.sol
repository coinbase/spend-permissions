// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {MockERC20} from "solady/../test/utils/mocks/MockERC20.sol";

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";

contract SpendTest is SpendPermissionManagerBase {
    MockERC20 mockERC20 = new MockERC20("mockERC20", "TEST", 18);

    function setUp() public {
        _initializeSpendPermissionManager();
        vm.prank(owner);
        account.addOwnerAddress(address(mockSpendPermissionManager));
    }

    function test_spend_revert_invalidSender(
        address sender,
        address account,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint160 spend
    ) public {
        vm.assume(start > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(sender != spender);
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
            allowance: allowance
        });
        vm.prank(account);
        mockSpendPermissionManager.approve(spendPermission);
        vm.startPrank(sender);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.InvalidSender.selector, sender, spender));
        mockSpendPermissionManager.spend(spendPermission, spend);
        vm.stopPrank();
    }

    function test_spend_revert_zeroValue(
        uint128 invalidPk,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance
    ) public {
        vm.assume(invalidPk != 0);
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);
        uint160 spend = 0;

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: spender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: period,
            allowance: allowance
        });

        vm.warp(start);
        vm.startPrank(spender);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.ZeroValue.selector));
        mockSpendPermissionManager.spend(spendPermission, spend);
        vm.stopPrank();
    }

    function test_spend_revert_unauthorizedSpendPermission(
        uint128 invalidPk,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint160 spend
    ) public {
        vm.assume(invalidPk != 0);
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
            allowance: allowance
        });

        vm.warp(start);
        vm.startPrank(spender);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.UnauthorizedSpendPermission.selector));
        mockSpendPermissionManager.spend(spendPermission, spend);
        vm.stopPrank();
    }

    function test_spend_success_ether(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint160 spend
    ) public {
        vm.assume(spender != address(account)); // otherwise balance checks can fail
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
            allowance: allowance
        });
        vm.deal(address(account), allowance);
        assertEq(address(account).balance, allowance);
        assertEq(spender.balance, 0);

        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);

        vm.warp(start);

        vm.startPrank(spender);
        mockSpendPermissionManager.approveWithSignature(spendPermission, signature);
        mockSpendPermissionManager.spend(spendPermission, spend);

        assertEq(address(account).balance, allowance - spend);
        assertEq(spender.balance, spend);
        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period, end));
        assertEq(usage.spend, spend);
    }

    function test_spend_success_ether_alreadyInitialized(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint160 spend
    ) public {
        vm.assume(spender != address(account)); // otherwise balance checks can fail
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
            allowance: allowance
        });
        vm.deal(address(account), allowance);
        vm.deal(spender, 0);
        vm.prank(address(account));
        mockSpendPermissionManager.approve(spendPermission);
        vm.warp(start);

        assertEq(address(account).balance, allowance);
        assertEq(spender.balance, 0);
        vm.prank(spender);
        mockSpendPermissionManager.spend(spendPermission, spend);
        assertEq(address(account).balance, allowance - spend);
        assertEq(spender.balance, spend);
        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period, end));
        assertEq(usage.spend, spend);
    }

    function test_spend_success_ERC20(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint160 spend
    ) public {
        vm.assume(spender != address(account)); // otherwise balance checks can fail
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
            token: address(mockERC20),
            start: start,
            end: end,
            period: period,
            allowance: allowance
        });
        mockERC20.mint(address(account), allowance);
        vm.prank(address(account));
        mockSpendPermissionManager.approve(spendPermission);
        vm.warp(start);

        assertEq(mockERC20.balanceOf(address(account)), allowance);
        assertEq(mockERC20.balanceOf(spender), 0);
        vm.prank(spender);
        mockSpendPermissionManager.spend(spendPermission, spend);
        assertEq(mockERC20.balanceOf(address(account)), allowance - spend);
        assertEq(mockERC20.balanceOf(spender), spend);
        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period, end));
        assertEq(usage.spend, spend);
    }
}
