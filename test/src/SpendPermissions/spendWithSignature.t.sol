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
        mockSpendPermissionManager.spendWithSignature(spendPermission, signature, spend);
        vm.stopPrank();
    }

    function test_spendWithSignature_revert_invalidSignature(
        uint128 invalidPk,
        address sender,
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
        mockSpendPermissionManager.spendWithSignature(spendPermission, invalidSignature, spend);
        vm.stopPrank();
    }

    function test_spendWithSignature_success_ether(
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
        mockSpendPermissionManager.spendWithSignature(spendPermission, signature, spend);

        assertEq(address(account).balance, allowance - spend);
        assertEq(spender.balance, spend);
        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period));
        assertEq(usage.spend, spend);
    }

    function test_spendWithSignature_success_ether_alreadyInitialized(
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
        vm.prank(address(account));
        mockSpendPermissionManager.approve(spendPermission); // pre-approve permission
        vm.warp(start);

        assertEq(address(account).balance, allowance);
        assertEq(spender.balance, 0);
        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);
        vm.prank(spender);
        mockSpendPermissionManager.spendWithSignature(spendPermission, signature, spend);
        assertEq(address(account).balance, allowance - spend);
        assertEq(spender.balance, spend);
        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period));
        assertEq(usage.spend, spend);
    }

    function test_spendWithSignature_success_ERC20(
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
        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);
        mockERC20.mint(address(account), allowance);

        vm.warp(start);

        assertEq(mockERC20.balanceOf(address(account)), allowance);
        assertEq(mockERC20.balanceOf(spender), 0);

        vm.prank(spender);
        mockSpendPermissionManager.spendWithSignature(spendPermission, signature, spend);

        assertEq(mockERC20.balanceOf(address(account)), allowance - spend);
        assertEq(mockERC20.balanceOf(spender), spend);
        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period));
        assertEq(usage.spend, spend);
    }

    function test_spendWithSignature_success_ether_erc6492PreDeploy(
        uint128 ownerPk,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint160 spend
    ) public {
        vm.assume(spender != address(account)); // otherwise balance checks can fail
        assumePayable(spender);
        vm.assume(ownerPk != 0);
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(spend > 0);
        vm.assume(allowance > 0);
        vm.assume(allowance >= spend);
        address ownerAddress = vm.addr(ownerPk);
        bytes[] memory owners = new bytes[](2);
        owners[0] = abi.encode(ownerAddress);
        owners[1] = abi.encode(address(mockSpendPermissionManager));
        address counterfactualAccount = mockCoinbaseSmartWalletFactory.getAddress(owners, 0);
        vm.assume(spender != counterfactualAccount); // otherwise balance checks can fail

        // create a 6492-compliant signature for the spend permission
        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: counterfactualAccount,
            spender: spender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: period,
            allowance: allowance
        });
        vm.deal(counterfactualAccount, allowance);
        vm.deal(spender, 0);
        assertEq(counterfactualAccount.balance, allowance);
        assertEq(spender.balance, 0);

        bytes memory signature = _signSpendPermission6492(spendPermission, ownerPk, 0, owners);
        // verify that the account isn't deployed yet
        vm.assertEq(counterfactualAccount.code.length, 0);

        vm.warp(start);

        vm.startPrank(spender);
        mockSpendPermissionManager.spendWithSignature(spendPermission, signature, spend);

        assertEq(counterfactualAccount.balance, allowance - spend);
        assertEq(spender.balance, spend);
        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period));
        assertEq(usage.spend, spend);
    }
}
