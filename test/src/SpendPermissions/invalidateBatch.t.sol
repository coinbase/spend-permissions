// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";

contract InvalidateBatchTest is SpendPermissionManagerBase {
    function setUp() public {
        _initializeSpendPermissionManager();
        vm.prank(owner);
        account.addOwnerAddress(address(mockSpendPermissionManager));
    }

    function test_invalidateBatch_revert_invalidSender(
        address spender,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance1,
        uint160 allowance2,
        uint256 salt1,
        uint256 salt2
    ) public {
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance1 > 0);
        vm.assume(allowance2 > 0);

        SpendPermissionManager.TokenAllowance memory tokenAllowance1 = SpendPermissionManager.TokenAllowance({
            token: token,
            allowance: allowance1,
            spender: spender,
            salt: salt1,
            extraData: "0x"
        });
        SpendPermissionManager.TokenAllowance memory tokenAllowance2 = SpendPermissionManager.TokenAllowance({
            token: token,
            allowance: allowance2,
            spender: spender,
            salt: salt2,
            extraData: "0x"
        });
        SpendPermissionManager.TokenAllowance[] memory tokenAllowances = new SpendPermissionManager.TokenAllowance[](2);
        tokenAllowances[0] = tokenAllowance1;
        tokenAllowances[1] = tokenAllowance2;
        SpendPermissionManager.SpendPermissionBatch memory spendPermissionBatch = SpendPermissionManager
            .SpendPermissionBatch({
            account: address(account),
            start: start,
            end: end,
            period: period,
            tokenAllowances: tokenAllowances
        });
        // pranking as spender instead of account
        vm.startPrank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(SpendPermissionManager.InvalidSender.selector, spender, address(account))
        );
        mockSpendPermissionManager.invalidateBatch(spendPermissionBatch);
        vm.stopPrank();
        // did not invalidate batch, can still approve
        bytes memory signature = _signSpendPermissionBatch(spendPermissionBatch, ownerPk, 0);
        mockSpendPermissionManager.approveBatchWithSignature(spendPermissionBatch, signature);
    }

    function test_invalidateBatch_success(
        address spender,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance1,
        uint160 allowance2,
        uint256 salt1,
        uint256 salt2
    ) public {
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance1 > 0);
        vm.assume(allowance2 > 0);

        SpendPermissionManager.TokenAllowance memory tokenAllowance1 = SpendPermissionManager.TokenAllowance({
            token: token,
            allowance: allowance1,
            spender: spender,
            salt: salt1,
            extraData: "0x"
        });
        SpendPermissionManager.TokenAllowance memory tokenAllowance2 = SpendPermissionManager.TokenAllowance({
            token: token,
            allowance: allowance2,
            spender: spender,
            salt: salt2,
            extraData: "0x"
        });
        SpendPermissionManager.TokenAllowance[] memory tokenAllowances = new SpendPermissionManager.TokenAllowance[](2);
        tokenAllowances[0] = tokenAllowance1;
        tokenAllowances[1] = tokenAllowance2;
        SpendPermissionManager.SpendPermissionBatch memory spendPermissionBatch = SpendPermissionManager
            .SpendPermissionBatch({
            account: address(account),
            start: start,
            end: end,
            period: period,
            tokenAllowances: tokenAllowances
        });
        vm.prank(address(account));
        mockSpendPermissionManager.invalidateBatch(spendPermissionBatch);

        bytes memory signature = _signSpendPermissionBatch(spendPermissionBatch, ownerPk, 0);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.InvalidatedBatch.selector));
        mockSpendPermissionManager.approveBatchWithSignature(spendPermissionBatch, signature);
    }

    function test_invalidateBatch_success_emitsEvent(
        address spender,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance1,
        uint160 allowance2,
        uint256 salt1,
        uint256 salt2
    ) public {
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance1 > 0);
        vm.assume(allowance2 > 0);

        SpendPermissionManager.TokenAllowance memory tokenAllowance1 = SpendPermissionManager.TokenAllowance({
            token: token,
            allowance: allowance1,
            spender: spender,
            salt: salt1,
            extraData: "0x"
        });
        SpendPermissionManager.TokenAllowance memory tokenAllowance2 = SpendPermissionManager.TokenAllowance({
            token: token,
            allowance: allowance2,
            spender: spender,
            salt: salt2,
            extraData: "0x"
        });
        SpendPermissionManager.TokenAllowance[] memory tokenAllowances = new SpendPermissionManager.TokenAllowance[](2);
        tokenAllowances[0] = tokenAllowance1;
        tokenAllowances[1] = tokenAllowance2;
        SpendPermissionManager.SpendPermissionBatch memory spendPermissionBatch = SpendPermissionManager
            .SpendPermissionBatch({
            account: address(account),
            start: start,
            end: end,
            period: period,
            tokenAllowances: tokenAllowances
        });
        vm.expectEmit(address(mockSpendPermissionManager));
        emit SpendPermissionManager.SpendPermissionBatchInvalidated({
            hash: mockSpendPermissionManager.getBatchHash(spendPermissionBatch),
            account: address(account),
            spendPermissionBatch: spendPermissionBatch
        });
        vm.prank(address(account));
        mockSpendPermissionManager.invalidateBatch(spendPermissionBatch);

        bytes memory signature = _signSpendPermissionBatch(spendPermissionBatch, ownerPk, 0);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.InvalidatedBatch.selector));
        mockSpendPermissionManager.approveBatchWithSignature(spendPermissionBatch, signature);
    }
}
