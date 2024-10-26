// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";

import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

contract ApproveBatchWithSignatureTest is SpendPermissionManagerBase {
    bytes32 SPEND_PERMISSION_APPROVED_EVENT_SIGNATURE = keccak256(
        "SpendPermissionApproved(bytes32,address,(address,address,address,uint160,uint48,uint48,uint48,uint256,bytes))"
    );

    function setUp() public {
        _initializeSpendPermissionManager();
        vm.prank(owner);
        account.addOwnerAddress(address(mockSpendPermissionManager));
    }

    function test_approveBatchWithSignature_revert_invalidSignature(
        uint128 invalidPk,
        address spender,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt1,
        uint256 salt2
    ) public {
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);
        vm.assume(invalidPk != 0);
        vm.assume(invalidPk != ownerPk);
        SpendPermissionManager.TokenAllowance memory tokenAllowance1 = SpendPermissionManager.TokenAllowance({
            token: token,
            allowance: allowance,
            spender: spender,
            salt: salt1,
            extraData: "0x"
        });
        SpendPermissionManager.TokenAllowance memory tokenAllowance2 = SpendPermissionManager.TokenAllowance({
            token: token,
            allowance: allowance,
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

        bytes memory invalidSignature = _signSpendPermissionBatch(spendPermissionBatch, invalidPk, 0);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.InvalidSignature.selector));
        mockSpendPermissionManager.approveBatchWithSignature(spendPermissionBatch, invalidSignature);
        _assertSpendPermissionBatchNotApproved(spendPermissionBatch, mockSpendPermissionManager);
    }

    function test_approveBatchWithSignature_revert_invalidSpendPermissionInBatch(
        address spender,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance1,
        uint256 salt
    ) public {
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance1 > 0);
        uint160 allowance2 = 0; // invalid allowance for second spend permission
        SpendPermissionManager.TokenAllowance memory tokenAllowance1 = SpendPermissionManager.TokenAllowance({
            token: token,
            allowance: allowance1,
            spender: spender,
            salt: salt,
            extraData: "0x"
        });
        SpendPermissionManager.TokenAllowance memory tokenAllowance2 = SpendPermissionManager.TokenAllowance({
            token: token,
            allowance: allowance2,
            spender: spender,
            salt: salt,
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

        bytes memory signature = _signSpendPermissionBatch(spendPermissionBatch, ownerPk, 0);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.ZeroAllowance.selector));
        mockSpendPermissionManager.approveBatchWithSignature(spendPermissionBatch, signature);
        _assertSpendPermissionBatchNotApproved(spendPermissionBatch, mockSpendPermissionManager);
    }

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

        bytes memory signature = _signSpendPermissionBatch(spendPermissionBatch, ownerPk, 0);
        mockSpendPermissionManager.approveBatchWithSignature(spendPermissionBatch, signature);
        _assertSpendPermissionBatchApproved(spendPermissionBatch, mockSpendPermissionManager);
    }

    function test_approveBatchWithSignature_success_emitsEvents(
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
            extraData: "0x01"
        });
        SpendPermissionManager.TokenAllowance memory tokenAllowance2 = SpendPermissionManager.TokenAllowance({
            token: token,
            allowance: allowance2,
            spender: spender,
            salt: salt2,
            extraData: "0x01"
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

        bytes memory signature = _signSpendPermissionBatch(spendPermissionBatch, ownerPk, 0);

        SpendPermissionManager.SpendPermission[] memory expectedSpendPermissions =
            _generateSpendPermissionArrayFromBatch(spendPermissionBatch);
        for (uint256 i = 0; i < expectedSpendPermissions.length; i++) {
            vm.expectEmit(address(mockSpendPermissionManager));
            emit SpendPermissionManager.SpendPermissionApproved({
                hash: mockSpendPermissionManager.getHash(expectedSpendPermissions[i]),
                account: address(account),
                spendPermission: expectedSpendPermissions[i]
            });
        }

        mockSpendPermissionManager.approveBatchWithSignature(spendPermissionBatch, signature);
        _assertSpendPermissionBatchApproved(spendPermissionBatch, mockSpendPermissionManager);
    }

    function _generateSpendPermissionArrayFromBatch(
        SpendPermissionManager.SpendPermissionBatch memory spendPermissionBatch
    ) internal pure returns (SpendPermissionManager.SpendPermission[] memory) {
        SpendPermissionManager.SpendPermission[] memory spendPermissions =
            new SpendPermissionManager.SpendPermission[](spendPermissionBatch.tokenAllowances.length);
        for (uint256 i = 0; i < spendPermissionBatch.tokenAllowances.length; i++) {
            SpendPermissionManager.TokenAllowance memory tokenAllowance = spendPermissionBatch.tokenAllowances[i];
            SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
                account: spendPermissionBatch.account,
                spender: tokenAllowance.spender,
                token: tokenAllowance.token,
                start: spendPermissionBatch.start,
                end: spendPermissionBatch.end,
                period: spendPermissionBatch.period,
                allowance: tokenAllowance.allowance,
                salt: tokenAllowance.salt,
                extraData: tokenAllowance.extraData
            });
            spendPermissions[i] = spendPermission;
        }
        return spendPermissions;
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
                salt: tokenAllowance.salt,
                extraData: tokenAllowance.extraData
            });
            vm.assertTrue(spendPermissionManager.isApproved(spendPermission));
        }
    }

    function _assertSpendPermissionBatchNotApproved(
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
                salt: tokenAllowance.salt,
                extraData: tokenAllowance.extraData
            });
            vm.assertFalse(spendPermissionManager.isApproved(spendPermission));
        }
    }
}
