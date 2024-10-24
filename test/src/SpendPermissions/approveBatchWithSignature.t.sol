// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";

contract ApproveBatchWithSignatureTest is SpendPermissionManagerBase {
    function setUp() public {
        _initializeSpendPermissionManager();
        vm.prank(owner);
        account.addOwnerAddress(address(mockSpendPermissionManager));
    }

    // TODO:
    // test revert with invalid permission included in otherwise valid batch
    // test revert with invalid batch signature
    // test success emits events for approvals
    // test success for identical permissions with different salts? (maybe add this to the salt PR since this is batch
    // independent)

    function test_approveBatchWithSignature_success_isApproved(
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

        SpendPermissionManager.TokenAllowance memory tokenAllowance1 =
            SpendPermissionManager.TokenAllowance({token: token, allowance: allowance1, spender: spender, salt: salt1});
        SpendPermissionManager.TokenAllowance memory tokenAllowance2 =
            SpendPermissionManager.TokenAllowance({token: token, allowance: allowance2, spender: spender, salt: salt2});
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

        bytes memory signature = _signSpendPermissionBatch(spendPermissionBatch, ownerPk, 0);
        mockSpendPermissionManager.approveBatchWithSignature(spendPermissionBatch, signature);
        _assertSpendPermissionBatchApproved(spendPermissionBatch, mockSpendPermissionManager);
    }

    function _assertSpendPermissionBatchApproved(
        SpendPermissionManager.SpendPermissionBatch memory spendPermissionBatch,
        SpendPermissionManager spendPermissionManager
    ) internal view {
        uint256 batchLength = spendPermissionBatch.tokenAllowances.length;
        for (uint256 i = 0; i < batchLength; i++) {
            SpendPermissionManager.TokenAllowance memory tokenAllowance = spendPermissionBatch.tokenAllowances[i];
            SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
                account: spendPermissionBatch.account,
                spender: tokenAllowance.spender,
                token: tokenAllowance.token,
                start: spendPermissionBatch.start,
                end: spendPermissionBatch.end,
                period: spendPermissionBatch.period,
                allowance: tokenAllowance.allowance,
                salt: tokenAllowance.salt
            });
            vm.assertTrue(spendPermissionManager.isApproved(spendPermission));
        }
    }
}
