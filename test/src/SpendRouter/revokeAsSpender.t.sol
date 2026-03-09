// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SpendPermissionManager} from "src/SpendPermissionManager.sol";
import {SpendRouter} from "src/SpendRouter.sol";
import {SpendRouterTestBase} from "test/src/SpendRouter/SpendRouterTestBase.sol";

contract RevokeAsSpenderTest is SpendRouterTestBase {
    /// @notice Executor can revoke an approved permission via SpendRouter.
    function test_revokesApprovedPermission() public {
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        _approvePermission(permission);

        assertTrue(permissionManager.isValid(permission));

        vm.prank(executor);
        router.revokeAsSpender(permission);

        assertTrue(permissionManager.isRevoked(permission));
        assertFalse(permissionManager.isValid(permission));
    }

    /// @notice Revoked permission cannot be used for spending.
    function test_revokedPermission_preventsSpend() public {
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        _approvePermission(permission);
        vm.deal(address(account), 1 ether);

        vm.prank(executor);
        router.revokeAsSpender(permission);

        vm.prank(executor);
        vm.expectRevert(SpendPermissionManager.UnauthorizedSpendPermission.selector);
        router.spendAndRoute(permission, 0.5 ether);
    }

    /// @notice Reverts when msg.sender is not the executor encoded in extraData.
    function test_reverts_whenSenderUnauthorized(address sender) public {
        vm.assume(sender != executor);

        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        _approvePermission(permission);

        vm.prank(sender);
        vm.expectRevert(abi.encodeWithSelector(SpendRouter.UnauthorizedSender.selector, sender, executor));
        router.revokeAsSpender(permission);
    }

    /// @notice Reverts when extraData is malformed.
    function test_reverts_whenExtraDataMalformed(bytes memory extraData) public {
        vm.assume(extraData.length != 64);

        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        permission.extraData = extraData;

        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(SpendRouter.MalformedExtraData.selector, extraData.length, extraData));
        router.revokeAsSpender(permission);
    }

    /// @notice Revoking an already-revoked permission does not revert (idempotent at SPM level).
    function test_doubleRevoke_doesNotRevert() public {
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        _approvePermission(permission);

        vm.startPrank(executor);
        router.revokeAsSpender(permission);
        router.revokeAsSpender(permission);
        vm.stopPrank();

        assertTrue(permissionManager.isRevoked(permission));
    }

    /// @notice Executor can revoke after a partial spend; remaining allowance is no longer usable.
    function test_revokeAfterPartialSpend() public {
        uint160 allowance = 1 ether;
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, allowance, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        _approvePermission(permission);
        vm.deal(address(account), allowance);

        vm.startPrank(executor);
        router.spendAndRoute(permission, 0.3 ether);
        router.revokeAsSpender(permission);
        vm.stopPrank();

        assertEq(address(recipient).balance, 0.3 ether);

        vm.prank(executor);
        vm.expectRevert(SpendPermissionManager.UnauthorizedSpendPermission.selector);
        router.spendAndRoute(permission, 0.1 ether);
    }
}
