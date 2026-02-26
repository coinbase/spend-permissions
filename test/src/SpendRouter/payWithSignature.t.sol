// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SpendPermissionManager} from "src/SpendPermissionManager.sol";
import {SpendRouter} from "src/SpendRouter.sol";
import {SpendRouterTestBase} from "test/src/SpendRouter/SpendRouterTestBase.sol";

contract PayWithSignatureTest is SpendRouterTestBase {
    /// @notice Reverts with MalformedExtraData when permission.extraData is not exactly 64 bytes.
    /// @dev First check in payWithSignature() via decodeExtraData. Fuzz extraData to any length != 64.
    function test_reverts_whenExtraDataMalformed(bytes memory extraData) public {
        vm.assume(extraData.length != 64);

        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        permission.extraData = extraData;
        bytes memory signature = _signPermission(permission);

        vm.expectRevert(abi.encodeWithSelector(SpendRouter.MalformedExtraData.selector, extraData.length, extraData));
        router.spendAndRouteWithSignature(permission, 0.5 ether, signature);
    }

    /// @notice Reverts with UnauthorizedSender when msg.sender does not match the executor decoded from extraData.
    /// @dev Second check in payWithSignature(). Fuzz the unauthorized sender, excluding the actual executor address.
    function test_reverts_whenSenderUnauthorized(address sender) public {
        vm.assume(sender != executor);

        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        bytes memory signature = _signPermission(permission);

        vm.prank(sender);
        vm.expectRevert(abi.encodeWithSelector(SpendRouter.UnauthorizedSender.selector, sender, executor));
        router.spendAndRouteWithSignature(permission, 0.5 ether, signature);
    }

    /// @notice Reverts with ZeroAddress when the decoded recipient is address(0).
    /// @dev Third check in payWithSignature(). Uses manually crafted extraData with abi.encode(executor, address(0)).
    function test_reverts_whenRecipientIsZeroAddress() public {
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        permission.extraData = abi.encode(executor, address(0));
        bytes memory signature = _signPermission(permission);

        vm.prank(executor);
        vm.expectRevert(SpendRouter.ZeroAddress.selector);
        router.spendAndRouteWithSignature(permission, 0.5 ether, signature);
    }

    /// @notice Successfully spends and forwards tokens even if the permission has already been approved.
    /// @dev Pre-approves the permission via _approvePermission(), then calls spendAndRouteWithSignature().
    ///      SpendPermissionManager.approveWithSignature() returns true for already approved permissions (idempotent).
    function test_succeeds_whenPermissionAlreadyApproved() public {
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        _approvePermission(permission);
        bytes memory signature = _signPermission(permission);

        vm.deal(address(account), 1 ether);

        vm.prank(executor);
        router.spendAndRouteWithSignature(permission, 0.5 ether, signature);

        assertEq(address(recipient).balance, 0.5 ether);
        assertEq(address(account).balance, 0.5 ether);
    }

    /// @notice Successfully approves, spends, and forwards native ETH from account to recipient in one tx.
    /// @dev Fuzz spendAmount within [1, allowance]. Signs permission but does NOT pre-approve.
    ///      Asserts recipient credited and account debited.
    function test_transfersNativeToken(uint160 spendAmount) public {
        uint160 allowance = 100 ether;
        vm.assume(spendAmount > 0 && spendAmount <= allowance);

        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, allowance, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        bytes memory signature = _signPermission(permission);

        vm.deal(address(account), allowance);

        vm.prank(executor);
        router.spendAndRouteWithSignature(permission, spendAmount, signature);

        assertEq(address(recipient).balance, spendAmount);
        assertEq(address(account).balance, allowance - spendAmount);
    }

    /// @notice Successfully approves, spends, and forwards ERC-20 tokens from account to recipient in one tx.
    /// @dev Fuzz spendAmount within [1, allowance]. Signs permission but does NOT pre-approve.
    ///      Asserts recipient credited and account debited.
    function test_transfersERC20(uint160 spendAmount) public {
        uint160 allowance = 1000e18;
        vm.assume(spendAmount > 0 && spendAmount <= allowance);

        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            address(token), allowance, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        bytes memory signature = _signPermission(permission);

        token.mint(address(account), allowance);

        vm.prank(executor);
        router.spendAndRouteWithSignature(permission, spendAmount, signature);

        assertEq(token.balanceOf(recipient), spendAmount);
        assertEq(token.balanceOf(address(account)), allowance - spendAmount);
    }
}
