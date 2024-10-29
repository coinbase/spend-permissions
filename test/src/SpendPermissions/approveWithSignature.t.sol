// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";

contract ApproveWithSignatureTest is SpendPermissionManagerBase {
    function setUp() public {
        _initializeSpendPermissionManager();
        vm.prank(owner);
        account.addOwnerAddress(address(mockSpendPermissionManager));
    }

    function test_approveWithSignature_revert_invalidSignature(
        uint128 invalidPk,
        address spender,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(invalidPk != 0);

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

        bytes memory invalidSignature = _signSpendPermission(spendPermission, invalidPk, 0);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.InvalidSignature.selector));
        mockSpendPermissionManager.approveWithSignature(spendPermission, invalidSignature);
    }

    function test_approveWithSignature_revert_invalidStartEnd(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(start >= end);

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

        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.InvalidStartEnd.selector, start, end));
        mockSpendPermissionManager.approveWithSignature(spendPermission, signature);
    }

    function test_approveWithSignature_revert_zeroPeriod(
        address spender,
        uint48 start,
        uint48 end,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(start < end);

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: spender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: 0,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });

        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.ZeroPeriod.selector));
        mockSpendPermissionManager.approveWithSignature(spendPermission, signature);
    }

    function test_approveWithSignature_revert_zeroAllowance(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(start < end);
        vm.assume(period > 0);

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: spender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: period,
            allowance: 0,
            salt: salt,
            extraData: extraData
        });

        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.ZeroAllowance.selector));
        mockSpendPermissionManager.approveWithSignature(spendPermission, signature);
    }

    function test_approveWithSignature_revert_existingSpendPermission(
        address spender,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

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

        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);
        mockSpendPermissionManager.approveWithSignature(spendPermission, signature);
        vm.assertTrue(mockSpendPermissionManager.isApproved(spendPermission));

        vm.expectRevert(
            abi.encodeWithSelector(
                SpendPermissionManager.ExistingSpendPermission.selector,
                mockSpendPermissionManager.getHash(spendPermission)
            )
        );
        mockSpendPermissionManager.approveWithSignature(spendPermission, signature);
    }

    function test_approveWithSignature_success_isApproved(
        address spender,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

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

        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);
        mockSpendPermissionManager.approveWithSignature(spendPermission, signature);
        vm.assertTrue(mockSpendPermissionManager.isApproved(spendPermission));
    }

    function test_approveWithSignature_success_emitsEvent(
        address spender,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

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

        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);
        vm.expectEmit(address(mockSpendPermissionManager));
        emit SpendPermissionManager.SpendPermissionApproved({
            hash: mockSpendPermissionManager.getHash(spendPermission),
            account: address(account),
            spendPermission: spendPermission
        });
        mockSpendPermissionManager.approveWithSignature(spendPermission, signature);
    }
}
