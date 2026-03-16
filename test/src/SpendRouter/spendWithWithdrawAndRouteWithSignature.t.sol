// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MagicSpend} from "magicspend/MagicSpend.sol";
import {SpendPermissionManager} from "src/SpendPermissionManager.sol";
import {SpendRouter} from "src/SpendRouter.sol";
import {SpendRouterTestBase} from "test/src/SpendRouter/SpendRouterTestBase.sol";

contract SpendWithWithdrawAndRouteWithSignatureTest is SpendRouterTestBase {
    /// @notice Successfully approves via signature, withdraws from MagicSpend, spends, and routes native ETH.
    function test_nativeToken() public {
        uint160 allowance = 1 ether;
        uint48 period = 1 days;
        uint48 start = uint48(block.timestamp);
        uint48 end = start + period;
        uint160 spendAmount = 0.5 ether;

        SpendPermissionManager.SpendPermission memory permission =
            _createPermission(NATIVE_TOKEN, allowance, period, start, end, 0);
        bytes memory sig = _signPermission(permission);

        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(permission, 0);
        withdrawRequest.amount = spendAmount;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        vm.deal(address(magicSpend), spendAmount);

        vm.prank(executor);
        router.spendWithWithdrawAndRouteWithSignature(permission, spendAmount, withdrawRequest, sig);

        assertEq(address(recipient).balance, spendAmount);
        assertEq(address(account).balance, 0);
    }

    /// @notice Successfully approves via signature, withdraws from MagicSpend, spends, and routes ERC-20.
    function test_erc20() public {
        uint160 allowance = 1000e18;
        uint48 period = 1 days;
        uint48 start = uint48(block.timestamp);
        uint48 end = start + period;
        uint160 spendAmount = 500e18;

        SpendPermissionManager.SpendPermission memory permission =
            _createPermission(address(token), allowance, period, start, end, 0);
        bytes memory sig = _signPermission(permission);

        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(permission, 0);
        withdrawRequest.asset = address(token);
        withdrawRequest.amount = spendAmount;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        token.mint(address(magicSpend), spendAmount);

        vm.prank(executor);
        router.spendWithWithdrawAndRouteWithSignature(permission, spendAmount, withdrawRequest, sig);

        assertEq(token.balanceOf(recipient), spendAmount);
        assertEq(token.balanceOf(address(account)), 0);
    }

    /// @notice Reverts with MalformedExtraData when extraData is not exactly 64 bytes.
    /// @param extraData Fuzzed bytes payload (excluded: length == 64).
    function test_revert_malformedExtraData(bytes memory extraData) public {
        vm.assume(extraData.length != 64);

        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        permission.extraData = extraData;
        bytes memory sig = _signPermission(permission);

        MagicSpend.WithdrawRequest memory withdrawRequest;

        vm.expectRevert(abi.encodeWithSelector(SpendRouter.MalformedExtraData.selector, extraData.length, extraData));
        router.spendWithWithdrawAndRouteWithSignature(permission, 0.5 ether, withdrawRequest, sig);
    }

    /// @notice Reverts with UnauthorizedSender when msg.sender does not match the executor.
    /// @param sender Fuzzed caller address (excluded: executor).
    function test_revert_unauthorizedSender(address sender) public {
        vm.assume(sender != executor);

        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        bytes memory sig = _signPermission(permission);

        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(permission, 0);
        withdrawRequest.amount = 0.5 ether;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        vm.prank(sender);
        vm.expectRevert(abi.encodeWithSelector(SpendRouter.UnauthorizedSender.selector, sender, executor));
        router.spendWithWithdrawAndRouteWithSignature(permission, 0.5 ether, withdrawRequest, sig);
    }

    /// @notice Reverts with ZeroAddress when the decoded recipient is address(0).
    function test_revert_recipientIsZeroAddress() public {
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        permission.extraData = abi.encode(executor, address(0));
        bytes memory sig = _signPermission(permission);

        MagicSpend.WithdrawRequest memory withdrawRequest;

        vm.prank(executor);
        vm.expectRevert(SpendRouter.ZeroAddress.selector);
        router.spendWithWithdrawAndRouteWithSignature(permission, 0.5 ether, withdrawRequest, sig);
    }

    /// @notice Reverts with InvalidSignature when the signature is from a non-owner key.
    function test_revert_invalidSignature() public {
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );

        uint256 wrongPk = uint256(keccak256("wrong_signer"));
        bytes32 permissionHash = permissionManager.getHash(permission);
        bytes32 replaySafeHash = account.replaySafeHash(permissionHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPk, replaySafeHash);
        bytes memory wrappedBadSig = _applySignatureWrapper(0, abi.encodePacked(r, s, v));

        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(permission, 0);
        withdrawRequest.amount = 0.5 ether;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        vm.prank(executor);
        vm.expectRevert(SpendPermissionManager.InvalidSignature.selector);
        router.spendWithWithdrawAndRouteWithSignature(permission, 0.5 ether, withdrawRequest, wrappedBadSig);
    }

    /// @notice Reverts with PermissionApprovalFailed when permission was previously revoked.
    function test_revert_permissionRevoked() public {
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        bytes memory sig = _signPermission(permission);

        // First approve and spend successfully
        MagicSpend.WithdrawRequest memory withdrawRequest1 = _createWithdrawRequest(permission, 0);
        withdrawRequest1.amount = 0.3 ether;
        withdrawRequest1.signature = _signWithdrawRequest(address(account), withdrawRequest1);
        vm.deal(address(magicSpend), 1 ether);

        vm.prank(executor);
        router.spendWithWithdrawAndRouteWithSignature(permission, 0.3 ether, withdrawRequest1, sig);

        // Account revokes the permission
        vm.prank(address(account));
        permissionManager.revoke(permission);

        // Second attempt fails — revoked permission cannot be re-approved
        MagicSpend.WithdrawRequest memory withdrawRequest2 = _createWithdrawRequest(permission, 1);
        withdrawRequest2.amount = 0.3 ether;
        withdrawRequest2.signature = _signWithdrawRequest(address(account), withdrawRequest2);

        vm.prank(executor);
        vm.expectRevert(SpendRouter.PermissionApprovalFailed.selector);
        router.spendWithWithdrawAndRouteWithSignature(permission, 0.3 ether, withdrawRequest2, sig);
    }

    /// @notice Successfully spends even when the permission is already approved (idempotent approval).
    function test_succeeds_whenPermissionAlreadyApproved() public {
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        _approvePermission(permission);
        bytes memory sig = _signPermission(permission);

        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(permission, 0);
        withdrawRequest.amount = 0.5 ether;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        vm.deal(address(magicSpend), 0.5 ether);

        vm.prank(executor);
        router.spendWithWithdrawAndRouteWithSignature(permission, 0.5 ether, withdrawRequest, sig);

        assertEq(address(recipient).balance, 0.5 ether);
        assertEq(address(account).balance, 0);
    }

    /// @notice Emits SpendRouted event with correct parameters.
    function test_emitsSpendRouted() public {
        uint160 spendAmount = 0.5 ether;
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        bytes memory sig = _signPermission(permission);

        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(permission, 0);
        withdrawRequest.amount = spendAmount;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        vm.deal(address(magicSpend), spendAmount);

        bytes32 permHash = permissionManager.getHash(permission);

        vm.prank(executor);
        vm.expectEmit(true, true, true, true);
        emit SpendRouter.SpendRouted(address(account), executor, recipient, permHash, NATIVE_TOKEN, spendAmount);
        router.spendWithWithdrawAndRouteWithSignature(permission, spendAmount, withdrawRequest, sig);
    }

    /// @notice Reverts with SpendTokenWithdrawAssetMismatch when token and withdraw asset differ.
    function test_revert_tokenWithdrawAssetMismatch() public {
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        bytes memory sig = _signPermission(permission);

        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(permission, 0);
        withdrawRequest.asset = address(token);
        withdrawRequest.amount = 0.5 ether;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                SpendPermissionManager.SpendTokenWithdrawAssetMismatch.selector, NATIVE_TOKEN, address(token)
            )
        );
        router.spendWithWithdrawAndRouteWithSignature(permission, 0.5 ether, withdrawRequest, sig);
    }

    /// @notice Reverts with ZeroValue when spend amount is zero.
    function test_revert_zeroValue() public {
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        bytes memory sig = _signPermission(permission);

        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(permission, 0);
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        vm.prank(executor);
        vm.expectRevert(SpendPermissionManager.ZeroValue.selector);
        router.spendWithWithdrawAndRouteWithSignature(permission, 0, withdrawRequest, sig);
    }

    /// @notice Successfully handles combined existing account balance and MagicSpend withdraw for native token.
    function test_combinedBalance_nativeToken() public {
        uint160 existingBalance = 0.3 ether;
        uint160 withdrawAmount = 0.7 ether;
        uint160 totalSpend = existingBalance + withdrawAmount;
        uint48 start = uint48(block.timestamp);

        SpendPermissionManager.SpendPermission memory permission =
            _createPermission(NATIVE_TOKEN, totalSpend, 1 days, start, start + 1 days, 0);
        bytes memory sig = _signPermission(permission);

        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(permission, 0);
        withdrawRequest.amount = withdrawAmount;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        vm.deal(address(magicSpend), withdrawAmount);
        vm.deal(address(account), existingBalance);

        vm.prank(executor);
        router.spendWithWithdrawAndRouteWithSignature(permission, totalSpend, withdrawRequest, sig);

        assertEq(address(recipient).balance, totalSpend);
        assertEq(address(account).balance, 0);
        assertEq(address(magicSpend).balance, 0);
    }
}
