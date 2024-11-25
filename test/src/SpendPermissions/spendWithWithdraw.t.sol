// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {MagicSpend} from "magic-spend/MagicSpend.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {MockERC20} from "solady/../test/utils/mocks/MockERC20.sol";
import {MockERC20LikeUSDT} from "solady/../test/utils/mocks/MockERC20LikeUSDT.sol";
import {ReturnsFalseToken} from "solady/../test/utils/weird-tokens/ReturnsFalseToken.sol";
import {ERC20} from "solady/tokens/ERC20.sol";

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";
import {MockERC20MissingReturn} from "../../mocks/MockERC20MissingReturn.sol";

contract SpendWithWithdrawTest is SpendPermissionManagerBase {
    MockERC20 mockERC20 = new MockERC20("mockERC20", "TEST", 18);
    ReturnsFalseToken mockERC20ReturnsFalse = new ReturnsFalseToken();
    MockERC20MissingReturn mockERC20MissingReturn = new MockERC20MissingReturn("mockERC20MissingReturn", "TEST", 18);
    MockERC20LikeUSDT mockERC20LikeUSDT = new MockERC20LikeUSDT();

    function setUp() public {
        _initializeSpendPermissionManager();
        vm.prank(owner);
        account.addOwnerAddress(address(mockSpendPermissionManager));
    }

    function test_spendWithWithdraw_revert_invalidSender(
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
        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest();
        vm.prank(account);
        mockSpendPermissionManager.approve(spendPermission);
        vm.startPrank(sender);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.InvalidSender.selector, sender, spender));
        mockSpendPermissionManager.spendWithWithdraw(spendPermission, spend, withdrawRequest);
        vm.stopPrank();
    }

    function test_spendWithWithdraw_revert_nativeTokenWithdrawAssetMismatch(
        uint128 invalidPk,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData,
        address withdrawAsset
    ) public {
        vm.assume(invalidPk != 0);
        vm.assume(spender != address(0));
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);
        vm.assume(withdrawAsset != address(0));
        uint160 spend = 0;
        address spendToken = NATIVE_TOKEN;

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: spender,
            token: spendToken,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest();
        withdrawRequest.asset = withdrawAsset;

        vm.warp(start);
        vm.startPrank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                SpendPermissionManager.SpendTokenWithdrawAssetMismatch.selector, spendToken, withdrawAsset
            )
        );
        mockSpendPermissionManager.spendWithWithdraw(spendPermission, spend, withdrawRequest);
        vm.stopPrank();
    }

    function test_spendWithWithdraw_revert_erc20TokenWithdrawAssetMismatch(
        uint128 invalidPk,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData,
        address spendToken,
        address withdrawAsset
    ) public {
        vm.assume(invalidPk != 0);
        vm.assume(spender != address(0));
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);
        vm.assume(spendToken != NATIVE_TOKEN);
        vm.assume(spendToken != withdrawAsset);
        uint160 spend = 0;

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: spender,
            token: spendToken,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest();
        withdrawRequest.asset = withdrawAsset;

        vm.warp(start);
        vm.startPrank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                SpendPermissionManager.SpendTokenWithdrawAssetMismatch.selector, spendToken, withdrawAsset
            )
        );
        mockSpendPermissionManager.spendWithWithdraw(spendPermission, spend, withdrawRequest);
        vm.stopPrank();
    }

    function test_spendWithWithdraw_revert_spendValueWithdrawAmountMismatch(
        uint128 invalidPk,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData,
        address spendToken,
        uint160 spendValue,
        uint256 withdrawAmount
    ) public {
        vm.assume(invalidPk != 0);
        vm.assume(spender != address(0));
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

        vm.assume(spendToken != NATIVE_TOKEN);
        vm.assume(spendValue != withdrawAmount);

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: spender,
            token: spendToken,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest();
        withdrawRequest.asset = spendToken;
        withdrawRequest.amount = withdrawAmount;

        vm.warp(start);
        vm.startPrank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                SpendPermissionManager.SpendValueWithdrawAmountMismatch.selector, spendValue, withdrawAmount
            )
        );
        mockSpendPermissionManager.spendWithWithdraw(spendPermission, spendValue, withdrawRequest);
        vm.stopPrank();
    }

    function test_spendWithWithdraw_revert_zeroValue(
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
        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest();

        vm.warp(start);
        vm.startPrank(spender);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.ZeroValue.selector));
        mockSpendPermissionManager.spendWithWithdraw(spendPermission, spend, withdrawRequest);
        vm.stopPrank();
    }

    function test_spendWithWithdraw_revert_unauthorizedSpendPermission(
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
        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest();
        withdrawRequest.amount = spend;

        vm.warp(start);
        vm.startPrank(spender);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.UnauthorizedSpendPermission.selector));
        mockSpendPermissionManager.spendWithWithdraw(spendPermission, spend, withdrawRequest);
        vm.stopPrank();
    }

    function test_spendWithWithdraw_reverts_magicSpendWithdrawFailed(
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
        address token = NATIVE_TOKEN;

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
        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest();
        withdrawRequest.amount = spend;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        vm.prank(address(account));
        mockSpendPermissionManager.approve(spendPermission);

        vm.warp(start);

        uint256 accountBalance = address(account).balance;
        uint256 spenderBalance = address(spender).balance;

        vm.startPrank(spender);
        vm.expectRevert(abi.encodeWithSelector(MagicSpend.WithdrawTooLarge.selector, spend, 0)); // no funds
        mockSpendPermissionManager.spendWithWithdraw(spendPermission, spend, withdrawRequest);

        // assert spend not marked as used and balances unchanged
        assertEq(mockSpendPermissionManager.getCurrentPeriod(spendPermission).spend, 0);
        assertEq(address(account).balance, accountBalance);
        assertEq(address(spender).balance, spenderBalance);
    }

    function test_spendWithWithdraw_success_ether(
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
        vm.assume(spender != address(magicSpend)); // otherwise balance checks can fail
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
        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest();
        withdrawRequest.amount = spend;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        vm.deal(address(magicSpend), allowance);

        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);

        vm.warp(start);

        vm.startPrank(spender);
        mockSpendPermissionManager.approveWithSignature(spendPermission, signature);
        mockSpendPermissionManager.spendWithWithdraw(spendPermission, spend, withdrawRequest);

        assertEq(address(magicSpend).balance, allowance - spend);
        assertEq(address(account).balance, 0);
        assertEq(spender.balance, spend);
        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period, end));
        assertEq(usage.spend, spend);
    }

    function test_spendWithWithdraw_success_erc20(
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
        vm.assume(spender != address(magicSpend)); // otherwise balance checks can fail
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
            token: address(mockERC20),
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest();
        withdrawRequest.asset = address(mockERC20);
        withdrawRequest.amount = spend;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        mockERC20.mint(address(magicSpend), allowance);

        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);

        vm.warp(start);

        vm.startPrank(spender);
        mockSpendPermissionManager.approveWithSignature(spendPermission, signature);
        mockSpendPermissionManager.spendWithWithdraw(spendPermission, spend, withdrawRequest);

        assertEq(mockERC20.balanceOf(address(magicSpend)), allowance - spend);
        assertEq(mockERC20.balanceOf(address(account)), 0);
        assertEq(mockERC20.balanceOf(spender), spend);
        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period, end));
        assertEq(usage.spend, spend);
    }
}