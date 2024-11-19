// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {MockERC20MissingReturn} from "../../mocks/MockERC20MissingReturn.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ERC20} from "solady/../src/tokens/ERC20.sol";
import {MockERC20} from "solady/../test/utils/mocks/MockERC20.sol";
import {MockERC20LikeUSDT} from "solady/../test/utils/mocks/MockERC20LikeUSDT.sol";
import {ReturnsFalseToken} from "solady/../test/utils/weird-tokens/ReturnsFalseToken.sol";

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";

contract SpendTest is SpendPermissionManagerBase {
    MockERC20 mockERC20 = new MockERC20("mockERC20", "TEST", 18);
    ReturnsFalseToken mockERC20ReturnsFalse = new ReturnsFalseToken();
    MockERC20MissingReturn mockERC20MissingReturn = new MockERC20MissingReturn("mockERC20MissingReturn", "TEST", 18);
    MockERC20LikeUSDT mockERC20LikeUSDT = new MockERC20LikeUSDT();

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

    function test_spend_reverts_undeployedToken(
        address spender,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData,
        uint160 spend
    ) public {
        vm.assume(token.code.length == 0); // token is not deployed
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
            token: token,
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
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, token));
        mockSpendPermissionManager.spend(spendPermission, spend);
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

    function test_spend_success_ERC20LikeUSDT(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData,
        uint160 totalSpend
    ) public {
        vm.assume(spender != address(0));
        vm.assume(spender != address(account)); // otherwise balance checks can fail
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(totalSpend > 1);
        vm.assume(allowance > 0);
        vm.assume(allowance >= totalSpend);
        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: spender,
            token: address(mockERC20LikeUSDT),
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        mockERC20LikeUSDT.mint(address(account), allowance);
        vm.prank(address(account));
        mockSpendPermissionManager.approve(spendPermission);
        vm.warp(start);
        uint160 spend = totalSpend / 2; // allow two spends
        assertEq(mockERC20LikeUSDT.balanceOf(address(account)), allowance);
        assertEq(mockERC20LikeUSDT.balanceOf(spender), 0);
        vm.startPrank(spender);
        mockSpendPermissionManager.spend(spendPermission, spend);
        assertEq(mockERC20LikeUSDT.balanceOf(address(account)), allowance - spend);
        assertEq(mockERC20LikeUSDT.balanceOf(spender), spend);
        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period, end));
        assertEq(usage.spend, spend);
        // Second spend should succeed as well. This fails if the approval behavior in
        // `SpendPermissionManager._transferFrom` ever tries to
        // approve USDT allowance when the existing allowance is nonzero.
        mockSpendPermissionManager.spend(spendPermission, spend);
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

    function test_spend_success_ERC20_approvalSetToZero(
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
        vm.startPrank(address(account));
        mockSpendPermissionManager.approve(spendPermission);
        mockERC20.approve(address(mockSpendPermissionManager), 0);
        vm.stopPrank();
        vm.warp(start);

        assertEq(mockERC20.balanceOf(address(account)), allowance);
        assertEq(mockERC20.balanceOf(spender), 0);
        assertEq(mockERC20.allowance(address(account), address(mockSpendPermissionManager)), 0);
        vm.prank(spender);
        mockSpendPermissionManager.spend(spendPermission, spend);
        assertEq(mockERC20.balanceOf(address(account)), allowance - spend);
        assertEq(mockERC20.balanceOf(spender), spend);
        assertEq(mockERC20.allowance(address(account), address(mockSpendPermissionManager)), 0);
        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period, end));
        assertEq(usage.spend, spend);
    }
}
