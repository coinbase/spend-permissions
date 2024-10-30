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
        vm.assume(spender != address(0));
        vm.assume(token != address(0));
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);
        vm.assume(invalidPk != 0);
        vm.assume(invalidPk != ownerPk);
        SpendPermissionManager.PermissionDetails memory permissionDetails1 = SpendPermissionManager.PermissionDetails({
            token: token,
            allowance: allowance,
            spender: spender,
            salt: salt1,
            extraData: "0x"
        });
        SpendPermissionManager.PermissionDetails memory permissionDetails2 = SpendPermissionManager.PermissionDetails({
            token: token,
            allowance: allowance,
            spender: spender,
            salt: salt2,
            extraData: "0x"
        });
        SpendPermissionManager.PermissionDetails[] memory permissions =
            new SpendPermissionManager.PermissionDetails[](2);
        permissions[0] = permissionDetails1;
        permissions[1] = permissionDetails2;
        SpendPermissionManager.SpendPermissionBatch memory spendPermissionBatch = SpendPermissionManager
            .SpendPermissionBatch({
            account: address(account),
            start: start,
            end: end,
            period: period,
            permissions: permissions
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
        vm.assume(spender != address(0));
        vm.assume(token != address(0));
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance1 > 0);
        uint160 allowance2 = 0; // invalid allowance for second spend permission
        SpendPermissionManager.PermissionDetails memory permissionDetails1 = SpendPermissionManager.PermissionDetails({
            token: token,
            allowance: allowance1,
            spender: spender,
            salt: salt,
            extraData: "0x"
        });
        SpendPermissionManager.PermissionDetails memory permissionDetails2 = SpendPermissionManager.PermissionDetails({
            token: token,
            allowance: allowance2,
            spender: spender,
            salt: salt,
            extraData: "0x"
        });
        SpendPermissionManager.PermissionDetails[] memory permissions =
            new SpendPermissionManager.PermissionDetails[](2);
        permissions[0] = permissionDetails1;
        permissions[1] = permissionDetails2;
        SpendPermissionManager.SpendPermissionBatch memory spendPermissionBatch = SpendPermissionManager
            .SpendPermissionBatch({
            account: address(account),
            start: start,
            end: end,
            period: period,
            permissions: permissions
        });

        bytes memory signature = _signSpendPermissionBatch(spendPermissionBatch, ownerPk, 0);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.ZeroAllowance.selector));
        mockSpendPermissionManager.approveBatchWithSignature(spendPermissionBatch, signature);
        _assertSpendPermissionBatchNotApproved(spendPermissionBatch, mockSpendPermissionManager);
    }

    function test_approveBatchWithSignature_revert_emptyBatch(uint48 start, uint48 end, uint48 period) public {
        vm.assume(start < end);
        vm.assume(period > 0);
        SpendPermissionManager.PermissionDetails[] memory permissions =
            new SpendPermissionManager.PermissionDetails[](0);
        SpendPermissionManager.SpendPermissionBatch memory spendPermissionBatch = SpendPermissionManager
            .SpendPermissionBatch({
            account: address(account),
            start: start,
            end: end,
            period: period,
            permissions: permissions
        });

        bytes memory stubSignature = abi.encodePacked("0x"); // can't get a valid signature for an empty batch because
            // getBatchHash reverts
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.EmptyBatch.selector));
        mockSpendPermissionManager.approveBatchWithSignature(spendPermissionBatch, stubSignature);
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
        vm.assume(spender != address(0));
        vm.assume(token != address(0));
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance1 > 0);
        vm.assume(allowance2 > 0);

        SpendPermissionManager.PermissionDetails memory permissionDetails1 = SpendPermissionManager.PermissionDetails({
            token: token,
            allowance: allowance1,
            spender: spender,
            salt: salt1,
            extraData: "0x"
        });
        SpendPermissionManager.PermissionDetails memory permissionDetails2 = SpendPermissionManager.PermissionDetails({
            token: token,
            allowance: allowance2,
            spender: spender,
            salt: salt2,
            extraData: "0x"
        });
        SpendPermissionManager.PermissionDetails[] memory permissions =
            new SpendPermissionManager.PermissionDetails[](2);
        permissions[0] = permissionDetails1;
        permissions[1] = permissionDetails2;
        SpendPermissionManager.SpendPermissionBatch memory spendPermissionBatch = SpendPermissionManager
            .SpendPermissionBatch({
            account: address(account),
            start: start,
            end: end,
            period: period,
            permissions: permissions
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
        vm.assume(spender != address(0));
        vm.assume(token != address(0));
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance1 > 0);
        vm.assume(allowance2 > 0);

        SpendPermissionManager.PermissionDetails memory permissionDetails1 = SpendPermissionManager.PermissionDetails({
            token: token,
            allowance: allowance1,
            spender: spender,
            salt: salt1,
            extraData: "0x01"
        });
        SpendPermissionManager.PermissionDetails memory permissionDetails2 = SpendPermissionManager.PermissionDetails({
            token: token,
            allowance: allowance2,
            spender: spender,
            salt: salt2,
            extraData: "0x01"
        });
        SpendPermissionManager.PermissionDetails[] memory permissions =
            new SpendPermissionManager.PermissionDetails[](2);
        permissions[0] = permissionDetails1;
        permissions[1] = permissionDetails2;
        SpendPermissionManager.SpendPermissionBatch memory spendPermissionBatch = SpendPermissionManager
            .SpendPermissionBatch({
            account: address(account),
            start: start,
            end: end,
            period: period,
            permissions: permissions
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

    function test_approveBatchWithSignature_success_erc6492SignaturePredeploy(
        uint128 ownerPk,
        address spender,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance
    ) public {
        vm.assume(spender != address(0));
        vm.assume(token != address(0));
        vm.assume(ownerPk != 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

        // generate the counterfactual address for the account
        address ownerAddress = vm.addr(ownerPk);
        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(ownerAddress);
        address counterfactualAccount = mockCoinbaseSmartWalletFactory.getAddress(owners, 0);

        SpendPermissionManager.PermissionDetails memory permissionDetails = SpendPermissionManager.PermissionDetails({
            token: token,
            allowance: allowance,
            spender: spender,
            salt: 0,
            extraData: "0x"
        });
        SpendPermissionManager.PermissionDetails[] memory permissions =
            new SpendPermissionManager.PermissionDetails[](1);
        permissions[0] = permissionDetails;
        SpendPermissionManager.SpendPermissionBatch memory spendPermissionBatch = SpendPermissionManager
            .SpendPermissionBatch({
            account: counterfactualAccount,
            start: start,
            end: end,
            period: period,
            permissions: permissions
        });

        // verify that the account isn't deployed yet
        vm.assertEq(counterfactualAccount.code.length, 0);

        bytes memory signature = _signSpendPermissionBatch6492(spendPermissionBatch, ownerPk, 0, owners);
        mockSpendPermissionManager.approveBatchWithSignature(spendPermissionBatch, signature);
        // verify that the account is now deployed (has code) and that a call to isValidSignature returns true
        vm.assertGt(counterfactualAccount.code.length, 0);
        _assertSpendPermissionBatchApproved(spendPermissionBatch, mockSpendPermissionManager);
    }

    function _generateSpendPermissionArrayFromBatch(
        SpendPermissionManager.SpendPermissionBatch memory spendPermissionBatch
    ) internal pure returns (SpendPermissionManager.SpendPermission[] memory) {
        SpendPermissionManager.SpendPermission[] memory spendPermissions =
            new SpendPermissionManager.SpendPermission[](spendPermissionBatch.permissions.length);
        for (uint256 i = 0; i < spendPermissionBatch.permissions.length; i++) {
            SpendPermissionManager.PermissionDetails memory permissionDetails = spendPermissionBatch.permissions[i];
            SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
                account: spendPermissionBatch.account,
                spender: permissionDetails.spender,
                token: permissionDetails.token,
                start: spendPermissionBatch.start,
                end: spendPermissionBatch.end,
                period: spendPermissionBatch.period,
                allowance: permissionDetails.allowance,
                salt: permissionDetails.salt,
                extraData: permissionDetails.extraData
            });
            spendPermissions[i] = spendPermission;
        }
        return spendPermissions;
    }

    function _assertSpendPermissionBatchApproved(
        SpendPermissionManager.SpendPermissionBatch memory spendPermissionBatch,
        SpendPermissionManager spendPermissionManager
    ) internal view {
        uint256 batchLength = spendPermissionBatch.permissions.length;
        for (uint256 i = 0; i < batchLength; i++) {
            SpendPermissionManager.PermissionDetails memory permissionDetails = spendPermissionBatch.permissions[i];
            SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
                account: spendPermissionBatch.account,
                spender: permissionDetails.spender,
                token: permissionDetails.token,
                start: spendPermissionBatch.start,
                end: spendPermissionBatch.end,
                period: spendPermissionBatch.period,
                allowance: permissionDetails.allowance,
                salt: permissionDetails.salt,
                extraData: permissionDetails.extraData
            });
            vm.assertTrue(spendPermissionManager.isApproved(spendPermission));
        }
    }

    function _assertSpendPermissionBatchNotApproved(
        SpendPermissionManager.SpendPermissionBatch memory spendPermissionBatch,
        SpendPermissionManager spendPermissionManager
    ) internal view {
        uint256 batchLength = spendPermissionBatch.permissions.length;
        for (uint256 i = 0; i < batchLength; i++) {
            SpendPermissionManager.PermissionDetails memory permissionDetails = spendPermissionBatch.permissions[i];
            SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
                account: spendPermissionBatch.account,
                spender: permissionDetails.spender,
                token: permissionDetails.token,
                start: spendPermissionBatch.start,
                end: spendPermissionBatch.end,
                period: spendPermissionBatch.period,
                allowance: permissionDetails.allowance,
                salt: permissionDetails.salt,
                extraData: permissionDetails.extraData
            });
            vm.assertFalse(spendPermissionManager.isApproved(spendPermission));
        }
    }
}
