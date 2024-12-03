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
    struct CommonTestParams {
        address spender;
        uint48 start;
        uint48 end;
        uint48 period;
        uint160 allowance;
        uint256 salt;
        bytes extraData;
        uint256 entropy;
    }

    // Helper function to validate common assumptions
    function _validateCommonAssumptions(CommonTestParams memory params) internal view {
        vm.assume(params.spender != address(0));
        vm.assume(params.spender != address(account));
        vm.assume(params.spender != address(magicSpend));
        vm.assume(params.start > 0);
        vm.assume(params.end > 0);
        vm.assume(params.start < params.end);
        vm.assume(params.period > 0);
        vm.assume(params.allowance > 0);
    }

    MockERC20 mockERC20 = new MockERC20("mockERC20", "TEST", 18);
    ReturnsFalseToken mockERC20ReturnsFalse = new ReturnsFalseToken();
    MockERC20MissingReturn mockERC20MissingReturn = new MockERC20MissingReturn("mockERC20MissingReturn", "TEST", 18);
    MockERC20LikeUSDT mockERC20LikeUSDT = new MockERC20LikeUSDT();

    function setUp() public {
        _initializeSpendPermissionManager();
        vm.prank(owner);
        account.addOwnerAddress(address(mockSpendPermissionManager));
    }

    function test_spendWithWithdraw_revert_invalidSender(CommonTestParams memory params, address sender, uint160 spend)
        public
    {
        _validateCommonAssumptions(params);
        vm.assume(sender != params.spender);
        vm.assume(spend > 0);
        vm.assume(params.allowance >= spend);

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: params.spender,
            token: NATIVE_TOKEN,
            start: params.start,
            end: params.end,
            period: params.period,
            allowance: params.allowance,
            salt: params.salt,
            extraData: params.extraData
        });

        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(params.spender, params.entropy);
        withdrawRequest.amount = spend;

        vm.prank(address(account));
        mockSpendPermissionManager.approve(spendPermission);

        vm.startPrank(sender);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.InvalidSender.selector, sender, params.spender));
        mockSpendPermissionManager.spendWithWithdraw(spendPermission, spend, withdrawRequest);
        vm.stopPrank();
    }

    function test_spendWithWithdraw_revert_nativeTokenWithdrawAssetMismatch(
        CommonTestParams memory params,
        address withdrawAsset
    ) public {
        _validateCommonAssumptions(params);
        vm.assume(withdrawAsset != address(0));
        uint160 spend = 0;

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: params.spender,
            token: NATIVE_TOKEN,
            start: params.start,
            end: params.end,
            period: params.period,
            allowance: params.allowance,
            salt: params.salt,
            extraData: params.extraData
        });

        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(params.spender, params.entropy);
        withdrawRequest.asset = withdrawAsset;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        vm.warp(params.start);
        vm.startPrank(params.spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                SpendPermissionManager.SpendTokenWithdrawAssetMismatch.selector, NATIVE_TOKEN, withdrawAsset
            )
        );
        mockSpendPermissionManager.spendWithWithdraw(spendPermission, spend, withdrawRequest);
        vm.stopPrank();
    }

    function test_spendWithWithdraw_revert_erc20TokenWithdrawAssetMismatch(
        CommonTestParams memory params,
        address spendToken,
        address withdrawAsset
    ) public {
        _validateCommonAssumptions(params);
        vm.assume(spendToken != NATIVE_TOKEN);
        vm.assume(spendToken != withdrawAsset);
        uint160 spend = 0;

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: params.spender,
            token: spendToken,
            start: params.start,
            end: params.end,
            period: params.period,
            allowance: params.allowance,
            salt: params.salt,
            extraData: params.extraData
        });

        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(params.spender, params.entropy);
        withdrawRequest.asset = withdrawAsset;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        vm.warp(params.start);
        vm.startPrank(params.spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                SpendPermissionManager.SpendTokenWithdrawAssetMismatch.selector, spendToken, withdrawAsset
            )
        );
        mockSpendPermissionManager.spendWithWithdraw(spendPermission, spend, withdrawRequest);
        vm.stopPrank();
    }

    function test_spendWithWithdraw_success_combinedBalance_erc20(
        CommonTestParams memory params,
        uint160 existingBalance
    ) public {
        _validateCommonAssumptions(params);
        vm.assume(existingBalance > 0);
        vm.assume(params.allowance > 0); // this is now our withdrawAmount
        vm.assume(params.allowance < type(uint160).max - existingBalance); // Prevent overflow
        uint160 totalSpend = params.allowance + existingBalance;

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: params.spender,
            token: address(mockERC20),
            start: params.start,
            end: params.end,
            period: params.period,
            allowance: totalSpend,
            salt: params.salt,
            extraData: params.extraData
        });

        // Setup withdraw request for partial amount
        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(params.spender, params.entropy);
        withdrawRequest.asset = address(mockERC20);
        withdrawRequest.amount = params.allowance; // allowance is our withdrawAmount
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        // Setup initial token balances
        mockERC20.mint(address(magicSpend), params.allowance);
        mockERC20.mint(address(account), existingBalance);

        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);

        vm.warp(params.start);

        vm.startPrank(params.spender);
        mockSpendPermissionManager.approveWithSignature(spendPermission, signature);
        mockSpendPermissionManager.spendWithWithdraw(spendPermission, totalSpend, withdrawRequest);

        // Verify final balances
        assertEq(mockERC20.balanceOf(address(magicSpend)), 0);
        assertEq(mockERC20.balanceOf(address(account)), 0);
        assertEq(mockERC20.balanceOf(params.spender), totalSpend);

        // Verify spend permission usage
        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, params.start);
        assertEq(usage.end, _safeAddUint48(params.start, params.period, params.end));
        assertEq(usage.spend, totalSpend);
    }

    function test_spendWithWithdraw_revert_spendLessThanWithdrawAmount(
        CommonTestParams memory params,
        uint160 spendValue
    ) public {
        _validateCommonAssumptions(params);
        vm.assume(spendValue < params.allowance); // spendValue must be less than withdrawAmount

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: params.spender,
            token: NATIVE_TOKEN,
            start: params.start,
            end: params.end,
            period: params.period,
            allowance: params.allowance,
            salt: params.salt,
            extraData: params.extraData
        });

        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(params.spender, params.entropy);
        withdrawRequest.amount = params.allowance; // allowance is our withdrawAmount
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        vm.warp(params.start);
        vm.prank(address(account));
        mockSpendPermissionManager.approve(spendPermission);

        vm.startPrank(params.spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                SpendPermissionManager.SpendValueWithdrawAmountMismatch.selector, spendValue, params.allowance
            )
        );
        mockSpendPermissionManager.spendWithWithdraw(spendPermission, spendValue, withdrawRequest);
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
        uint160 spend,
        uint256 entropy
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
        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(spender, entropy);
        withdrawRequest.amount = spend;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        vm.warp(start);
        vm.startPrank(spender);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.UnauthorizedSpendPermission.selector));
        mockSpendPermissionManager.spendWithWithdraw(spendPermission, spend, withdrawRequest);
        vm.stopPrank();
    }

    function test_spendWithWithdraw_reverts_magicSpendWithdrawFailed(CommonTestParams memory params, uint160 spend)
        public
    {
        _validateCommonAssumptions(params);
        vm.assume(spend > 0);
        vm.assume(params.allowance >= spend);

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: params.spender,
            token: NATIVE_TOKEN,
            start: params.start,
            end: params.end,
            period: params.period,
            allowance: params.allowance,
            salt: params.salt,
            extraData: params.extraData
        });

        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(params.spender, params.entropy);
        withdrawRequest.amount = spend;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        vm.prank(address(account));
        mockSpendPermissionManager.approve(spendPermission);

        vm.warp(params.start);

        uint256 accountBalance = address(account).balance;
        uint256 spenderBalance = address(params.spender).balance;

        vm.startPrank(params.spender);
        vm.expectRevert(abi.encodeWithSelector(MagicSpend.WithdrawTooLarge.selector, spend, 0)); // no funds
        mockSpendPermissionManager.spendWithWithdraw(spendPermission, spend, withdrawRequest);

        // assert spend not marked as used and balances unchanged
        assertEq(mockSpendPermissionManager.getCurrentPeriod(spendPermission).spend, 0);
        assertEq(address(account).balance, accountBalance);
        assertEq(address(params.spender).balance, spenderBalance);
    }

    function test_spendWithWithdraw_success_ether(CommonTestParams memory params, uint160 spend) public {
        _validateCommonAssumptions(params);
        assumePayable(params.spender);
        vm.assume(spend > 0);
        vm.assume(params.allowance >= spend);

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: params.spender,
            token: NATIVE_TOKEN,
            start: params.start,
            end: params.end,
            period: params.period,
            allowance: params.allowance,
            salt: params.salt,
            extraData: params.extraData
        });

        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(params.spender, params.entropy);
        withdrawRequest.amount = spend;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        vm.deal(address(magicSpend), params.allowance);
        vm.deal(address(account), 0);
        vm.deal(params.spender, 0);

        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);

        vm.warp(params.start);

        vm.startPrank(params.spender);
        mockSpendPermissionManager.approveWithSignature(spendPermission, signature);
        mockSpendPermissionManager.spendWithWithdraw(spendPermission, spend, withdrawRequest);

        assertEq(address(magicSpend).balance, params.allowance - spend);
        assertEq(address(account).balance, 0);
        assertEq(params.spender.balance, spend);

        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, params.start);
        assertEq(usage.end, _safeAddUint48(params.start, params.period, params.end));
        assertEq(usage.spend, spend);
    }

    function test_spendWithWithdraw_success_erc20(CommonTestParams memory params, uint160 spend) public {
        _validateCommonAssumptions(params);
        assumePayable(params.spender);
        vm.assume(spend > 0);
        vm.assume(params.allowance >= spend);

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: params.spender,
            token: address(mockERC20),
            start: params.start,
            end: params.end,
            period: params.period,
            allowance: params.allowance,
            salt: params.salt,
            extraData: params.extraData
        });

        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(params.spender, params.entropy);
        withdrawRequest.asset = address(mockERC20);
        withdrawRequest.amount = spend;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        mockERC20.mint(address(magicSpend), params.allowance);

        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);

        vm.warp(params.start);

        vm.startPrank(params.spender);
        mockSpendPermissionManager.approveWithSignature(spendPermission, signature);
        mockSpendPermissionManager.spendWithWithdraw(spendPermission, spend, withdrawRequest);

        assertEq(mockERC20.balanceOf(address(magicSpend)), params.allowance - spend);
        assertEq(mockERC20.balanceOf(address(account)), 0);
        assertEq(mockERC20.balanceOf(params.spender), spend);

        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, params.start);
        assertEq(usage.end, _safeAddUint48(params.start, params.period, params.end));
        assertEq(usage.spend, spend);
    }

    function test_spendWithWithdraw_success_combinedBalance_ether(
        CommonTestParams memory params,
        uint160 existingBalance
    ) public {
        _validateCommonAssumptions(params);
        assumePayable(params.spender);
        vm.assume(existingBalance > 0);
        vm.assume(params.allowance > 0); // this is now our withdrawAmount
        vm.assume(params.allowance < type(uint160).max - existingBalance); // Prevent overflow
        uint160 totalSpend = params.allowance + existingBalance;

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: params.spender,
            token: NATIVE_TOKEN,
            start: params.start,
            end: params.end,
            period: params.period,
            allowance: totalSpend,
            salt: params.salt,
            extraData: params.extraData
        });

        // Setup withdraw request for partial amount
        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(params.spender, params.entropy);
        withdrawRequest.amount = params.allowance; // allowance is our withdrawAmount
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        // Setup initial balances
        vm.deal(address(magicSpend), params.allowance);
        vm.deal(address(account), existingBalance);

        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);

        vm.warp(params.start);

        vm.startPrank(params.spender);
        mockSpendPermissionManager.approveWithSignature(spendPermission, signature);
        mockSpendPermissionManager.spendWithWithdraw(spendPermission, totalSpend, withdrawRequest);

        // Verify final balances
        assertEq(address(magicSpend).balance, 0);
        assertEq(address(account).balance, 0);
        assertEq(params.spender.balance, totalSpend);

        // Verify spend permission usage
        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, params.start);
        assertEq(usage.end, _safeAddUint48(params.start, params.period, params.end));
        assertEq(usage.spend, totalSpend);
    }

    function test_spendWithWithdraw_revert_invalidEncodedSpender(
        CommonTestParams memory params,
        uint160 spend,
        address encodedSpender
    ) public {
        _validateCommonAssumptions(params);
        vm.assume(encodedSpender != params.spender); // Ensure encoded spender is different
        vm.assume(spend > 0);
        vm.assume(params.allowance >= spend);

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: params.spender,
            token: NATIVE_TOKEN,
            start: params.start,
            end: params.end,
            period: params.period,
            allowance: params.allowance,
            salt: params.salt,
            extraData: params.extraData
        });

        // Create withdraw request with incorrect encoded spender
        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(encodedSpender, params.entropy);
        withdrawRequest.amount = spend;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        vm.deal(address(magicSpend), params.allowance);

        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);

        vm.warp(params.start);

        vm.startPrank(params.spender);
        mockSpendPermissionManager.approveWithSignature(spendPermission, signature);

        vm.expectRevert(
            abi.encodeWithSelector(
                SpendPermissionManager.InvalidWithdrawRequestSpender.selector, encodedSpender, params.spender
            )
        );
        mockSpendPermissionManager.spendWithWithdraw(spendPermission, spend, withdrawRequest);
        vm.stopPrank();
    }

    function test_spendWithWithdraw_success_withEncodedSpender(CommonTestParams memory params, uint160 spend) public {
        _validateCommonAssumptions(params);
        assumePayable(params.spender);
        vm.assume(spend > 0);
        vm.assume(params.allowance >= spend);

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: params.spender,
            token: NATIVE_TOKEN,
            start: params.start,
            end: params.end,
            period: params.period,
            allowance: params.allowance,
            salt: params.salt,
            extraData: params.extraData
        });

        // Create withdraw request with correctly encoded spender
        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(params.spender, params.entropy);
        withdrawRequest.amount = spend;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        vm.deal(address(magicSpend), params.allowance);
        vm.deal(address(account), 0);
        vm.deal(params.spender, 0);

        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);

        vm.warp(params.start);

        vm.startPrank(params.spender);
        mockSpendPermissionManager.approveWithSignature(spendPermission, signature);
        mockSpendPermissionManager.spendWithWithdraw(spendPermission, spend, withdrawRequest);

        // Verify balances and state changes
        assertEq(address(magicSpend).balance, params.allowance - spend);
        assertEq(address(account).balance, 0);
        assertEq(params.spender.balance, spend);
        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, params.start);
        assertEq(usage.end, _safeAddUint48(params.start, params.period, params.end));
        assertEq(usage.spend, spend);
        vm.stopPrank();
    }
}
