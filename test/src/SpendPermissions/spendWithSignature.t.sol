// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {MockERC20} from "solady/../test/utils/mocks/MockERC20.sol";

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";

contract SpendWithSignatureTest is SpendPermissionManagerBase {
    MockERC20 mockERC20 = new MockERC20("mockERC20", "TEST", 18);

    function setUp() public {
        _initializeSpendPermissionManager();
        vm.prank(owner);
        account.addOwnerAddress(address(mockSpendPermissionManager));
    }

    function test_spendWithSignature_revert_invalidSender(
        address sender,
        address spender,
        address recipient,
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
        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);
        vm.startPrank(sender);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.InvalidSender.selector, sender, spender));
        mockSpendPermissionManager.spendWithSignature(spendPermission, signature, recipient, spend);
        vm.stopPrank();
    }

    function test_spendWithSignature_revert_invalidSignature(
        uint128 invalidPk,
        address sender,
        address recipient,
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
            spender: sender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: period,
            allowance: allowance
        });
        bytes memory invalidSignature = _signSpendPermission(spendPermission, invalidPk, 0);
        vm.warp(start);
        vm.startPrank(sender);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.InvalidSignature.selector));
        mockSpendPermissionManager.spendWithSignature(spendPermission, invalidSignature, recipient, spend);
        vm.stopPrank();
    }

    function test_spendWithSignature_success_ether(
        address sender,
        address recipient,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint160 spend
    ) public {
        vm.assume(recipient != address(account)); // otherwise balance checks can fail
        assumePayable(recipient);
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(spend > 0);
        vm.assume(allowance > 0);
        vm.assume(allowance >= spend);
        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: sender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: period,
            allowance: allowance
        });
        vm.deal(address(account), allowance);
        vm.deal(recipient, 0);
        assertEq(address(account).balance, allowance);
        assertEq(recipient.balance, 0);

        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);

        vm.warp(start);

        vm.startPrank(sender);
        mockSpendPermissionManager.spendWithSignature(spendPermission, signature, recipient, spend);

        assertEq(address(account).balance, allowance - spend);
        assertEq(recipient.balance, spend);
        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period));
        assertEq(usage.spend, spend);
    }

    function test_spendWithSignature_success_ether_alreadyInitialized(
        address sender,
        address recipient,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint160 spend
    ) public {
        vm.assume(recipient != address(account)); // otherwise balance checks can fail
        assumePayable(recipient);
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(spend > 0);
        vm.assume(allowance > 0);
        vm.assume(allowance >= spend);
        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: sender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: period,
            allowance: allowance
        });
        vm.deal(address(account), allowance);
        vm.deal(recipient, 0);
        vm.prank(address(account));
        mockSpendPermissionManager.approve(spendPermission); // can still use permit version if approval has been made
            // previously
        vm.warp(start);

        assertEq(address(account).balance, allowance);
        assertEq(recipient.balance, 0);
        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);
        vm.prank(sender);
        mockSpendPermissionManager.spendWithSignature(spendPermission, signature, recipient, spend);
        assertEq(address(account).balance, allowance - spend);
        assertEq(recipient.balance, spend);
        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period));
        assertEq(usage.spend, spend);
    }

    function test_spendWithSignature_success_ERC20(
        address sender,
        address recipient,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint160 spend
    ) public {
        vm.assume(recipient != address(account)); // otherwise balance checks can fail
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(spend > 0);
        vm.assume(allowance > 0);
        vm.assume(allowance >= spend);
        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: sender,
            token: address(mockERC20),
            start: start,
            end: end,
            period: period,
            allowance: allowance
        });
        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);
        mockERC20.mint(address(account), allowance);

        vm.warp(start);

        assertEq(mockERC20.balanceOf(address(account)), allowance);
        assertEq(mockERC20.balanceOf(recipient), 0);

        vm.prank(sender);
        mockSpendPermissionManager.spendWithSignature(spendPermission, signature, recipient, spend);

        assertEq(mockERC20.balanceOf(address(account)), allowance - spend);
        assertEq(mockERC20.balanceOf(recipient), spend);
        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period));
        assertEq(usage.spend, spend);
    }
}
