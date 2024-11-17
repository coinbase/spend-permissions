// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {MockERC20MissingReturn} from "../../mocks/MockERC20MissingReturn.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ERC20} from "solady/../src/tokens/ERC20.sol";
import {MockERC20} from "solady/../test/utils/mocks/MockERC20.sol";
import {ReturnsFalseToken} from "solady/../test/utils/weird-tokens/ReturnsFalseToken.sol";

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";
import {MockMaliciousCoinbaseSmartWallet} from "../../mocks/MockMaliciousCoinbaseSmartWallet.sol";

contract SpendTest is SpendPermissionManagerBase {
    MockERC20 mockERC20 = new MockERC20("mockERC20", "TEST", 18);
    ReturnsFalseToken mockERC20ReturnsFalse = new ReturnsFalseToken();
    MockERC20MissingReturn mockERC20MissingReturn = new MockERC20MissingReturn("mockERC20MissingReturn", "TEST", 18);
    MockMaliciousCoinbaseSmartWallet mockMaliciousCoinbaseSmartWallet = new MockMaliciousCoinbaseSmartWallet();

    function setUp() public {
        _initializeSpendPermissionManager();
        vm.startPrank(owner);
        account.addOwnerAddress(address(mockSpendPermissionManager));

        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(owner);
        mockMaliciousCoinbaseSmartWallet.initialize(owners);
        mockMaliciousCoinbaseSmartWallet.addOwnerAddress(address(mockSpendPermissionManager));
        vm.stopPrank();
    }

    function test_spend_succeeds_maliciousUserWallet(
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
        vm.assume(spender != address(mockMaliciousCoinbaseSmartWallet)); // otherwise balance checks can fail
        assumePayable(spender);
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(spend > 0);
        vm.assume(allowance > 0);
        vm.assume(allowance >= spend);
        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: address(mockMaliciousCoinbaseSmartWallet),
            spender: spender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        vm.deal(address(mockMaliciousCoinbaseSmartWallet), allowance);
        vm.deal(spender, 0);
        vm.prank(address(mockMaliciousCoinbaseSmartWallet));
        mockSpendPermissionManager.approve(spendPermission);
        vm.warp(start);

        assertEq(address(mockMaliciousCoinbaseSmartWallet).balance, allowance);
        assertEq(spender.balance, 0);
        vm.prank(spender);
        mockSpendPermissionManager.spend(spendPermission, spend);
        assertNotEq(address(mockMaliciousCoinbaseSmartWallet).balance, allowance - spend); // balance didn't transfer!!
        assertNotEq(spender.balance, spend); // balance didn't transfer!!
        assertEq(address(mockMaliciousCoinbaseSmartWallet).balance, allowance); // original balances still there
        assertEq(spender.balance, 0); // original balances still there
        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission); // usage
            // was still recorded
        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period, end));
        assertEq(usage.spend, spend);
    }

    function test_spend_revert_invalidSender(
        address sender,
        address account,
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
            allowance: allowance,
            salt: salt,
            extraData: extraData
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
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(invalidPk != 0);
        vm.assume(spender != address(0));
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
            allowance: allowance,
            salt: salt,
            extraData: extraData
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
        uint256 salt,
        bytes memory extraData,
        uint160 spend
    ) public {
        vm.assume(invalidPk != 0);
        vm.assume(spender != address(0));
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
        uint256 salt,
        bytes memory extraData,
        uint160 spend
    ) public {
        vm.assume(spender != address(0));
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
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        vm.deal(address(account), allowance);
        assertEq(address(account).balance, allowance);
        vm.deal(spender, 0);
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
        uint256 salt,
        bytes memory extraData,
        uint160 spend
    ) public {
        vm.assume(spender != address(0));
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
            allowance: allowance,
            salt: salt,
            extraData: extraData
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

    function test_spend_success_ERC20ReturnsTrue(
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
            allowance: allowance,
            salt: salt,
            extraData: extraData
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

    function test_spend_success_ERC20NoReturn(
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
            token: address(mockERC20MissingReturn),
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        mockERC20MissingReturn.mint(address(account), allowance);
        vm.prank(address(account));
        mockSpendPermissionManager.approve(spendPermission);
        vm.warp(start);

        assertEq(mockERC20MissingReturn.balanceOf(address(account)), allowance);
        assertEq(mockERC20MissingReturn.balanceOf(spender), 0);
        vm.prank(spender);
        mockSpendPermissionManager.spend(spendPermission, spend);
        assertEq(mockERC20MissingReturn.balanceOf(address(account)), allowance - spend);
        assertEq(mockERC20MissingReturn.balanceOf(spender), spend);
        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period, end));
        assertEq(usage.spend, spend);
    }

    function test_spend_reverts_ERC20FailedTransfer_ERC20Reverts(
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
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        vm.prank(address(account));
        mockSpendPermissionManager.approve(spendPermission);
        vm.warp(start);

        vm.startPrank(spender);
        // account has no balance, so the transfer will fail
        vm.expectRevert(abi.encodeWithSelector(ERC20.InsufficientBalance.selector));
        mockSpendPermissionManager.spend(spendPermission, spend);
    }

    function test_spend_reverts_ERC20FailedTransfer_ERC20ReturnsFalse(
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
            token: address(mockERC20ReturnsFalse),
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        vm.prank(address(account));
        mockSpendPermissionManager.approve(spendPermission);
        vm.warp(start);

        vm.startPrank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(mockERC20ReturnsFalse))
        );
        mockSpendPermissionManager.spend(spendPermission, spend);
    }
}
