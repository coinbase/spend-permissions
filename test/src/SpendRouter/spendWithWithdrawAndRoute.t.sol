// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MagicSpend} from "magicspend/MagicSpend.sol";
import {SpendPermissionManager} from "src/SpendPermissionManager.sol";
import {SpendRouter} from "src/SpendRouter.sol";
import {SpendRouterTestBase} from "test/src/SpendRouter/SpendRouterTestBase.sol";

contract SpendWithWithdrawAndRouteTest is SpendRouterTestBase {
    /// @notice Successfully withdraws from MagicSpend, spends, and routes native ETH to the recipient.
    function test_nativeToken() public {
        uint160 allowance = 1 ether;
        uint48 period = 1 days;
        uint48 start = uint48(block.timestamp);
        uint48 end = start + period;
        uint160 spendAmount = 0.5 ether;

        SpendPermissionManager.SpendPermission memory permission =
            _createPermission(NATIVE_TOKEN, allowance, period, start, end, 0);
        _approvePermission(permission);

        // Create and sign withdraw request
        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(permission, 0);
        withdrawRequest.amount = spendAmount;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        // Fund MagicSpend
        vm.deal(address(magicSpend), spendAmount);

        vm.prank(executor);
        router.spendWithWithdrawAndRoute(permission, spendAmount, withdrawRequest);

        assertEq(address(recipient).balance, spendAmount);
        assertEq(address(account).balance, 0);
    }

    /// @notice Successfully withdraws from MagicSpend, spends, and routes ERC-20 tokens to the recipient.
    function test_erc20() public {
        uint160 allowance = 1000e18;
        uint48 period = 1 days;
        uint48 start = uint48(block.timestamp);
        uint48 end = start + period;
        uint160 spendAmount = 500e18;

        SpendPermissionManager.SpendPermission memory permission =
            _createPermission(address(token), allowance, period, start, end, 0);
        _approvePermission(permission);

        // Create and sign withdraw request for ERC-20
        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(permission, 0);
        withdrawRequest.asset = address(token);
        withdrawRequest.amount = spendAmount;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        // Fund MagicSpend with ERC-20
        token.mint(address(magicSpend), spendAmount);

        vm.prank(executor);
        router.spendWithWithdrawAndRoute(permission, spendAmount, withdrawRequest);

        assertEq(token.balanceOf(recipient), spendAmount);
        assertEq(token.balanceOf(address(account)), 0);
    }

    /// @notice Reverts with UnauthorizedSender when msg.sender does not match the executor.
    function test_revert_unauthorizedSender() public {
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        _approvePermission(permission);

        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(permission, 0);
        withdrawRequest.amount = 0.5 ether;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        address unauthorizedSender = makeAddr("unauthorized");
        vm.prank(unauthorizedSender);
        vm.expectRevert(abi.encodeWithSelector(SpendRouter.UnauthorizedSender.selector, unauthorizedSender, executor));
        router.spendWithWithdrawAndRoute(permission, 0.5 ether, withdrawRequest);
    }

    /// @notice Reverts with MalformedExtraData when extraData is not exactly 64 bytes.
    /// @param extraData Fuzzed bytes payload (excluded: length == 64).
    function test_revert_malformedExtraData(bytes memory extraData) public {
        vm.assume(extraData.length != 64);

        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        permission.extraData = extraData;

        MagicSpend.WithdrawRequest memory withdrawRequest;

        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(SpendRouter.MalformedExtraData.selector, extraData.length, extraData));
        router.spendWithWithdrawAndRoute(permission, 0.5 ether, withdrawRequest);
    }

    /// @notice Reverts with ZeroAddress when the decoded recipient is address(0).
    function test_revert_recipientIsZeroAddress() public {
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        permission.extraData = abi.encode(executor, address(0));
        _approvePermission(permission);

        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(permission, 0);
        withdrawRequest.amount = 0.5 ether;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        vm.prank(executor);
        vm.expectRevert(SpendRouter.ZeroAddress.selector);
        router.spendWithWithdrawAndRoute(permission, 0.5 ether, withdrawRequest);
    }

    /// @notice Reverts when the spend permission is not approved.
    function test_revert_permissionNotApproved() public {
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );

        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(permission, 0);
        withdrawRequest.amount = 0.5 ether;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        vm.prank(executor);
        vm.expectRevert(SpendPermissionManager.UnauthorizedSpendPermission.selector);
        router.spendWithWithdrawAndRoute(permission, 0.5 ether, withdrawRequest);
    }

    /// @notice Reverts when the spend amount exceeds the allowance.
    function test_revert_exceedsAllowance() public {
        uint160 allowance = 1 ether;
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, allowance, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        _approvePermission(permission);

        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(permission, 0);
        withdrawRequest.amount = allowance + 1;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        vm.deal(address(magicSpend), 10 ether);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                SpendPermissionManager.ExceededSpendPermission.selector, uint256(allowance) + 1, allowance
            )
        );
        router.spendWithWithdrawAndRoute(permission, allowance + 1, withdrawRequest);
    }

    /// @notice Emits SpendRouted event with correct parameters for native token.
    function test_emitsSpendRouted_nativeToken() public {
        uint160 spendAmount = 0.5 ether;
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        _approvePermission(permission);

        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(permission, 0);
        withdrawRequest.amount = spendAmount;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        vm.deal(address(magicSpend), spendAmount);

        bytes32 permHash = permissionManager.getHash(permission);
        vm.prank(executor);
        vm.expectEmit(true, true, true, true);
        emit SpendRouter.SpendRouted(address(account), executor, recipient, permHash, NATIVE_TOKEN, spendAmount);
        router.spendWithWithdrawAndRoute(permission, spendAmount, withdrawRequest);
    }

    /// @notice Emits SpendRouted event with correct parameters for ERC-20 token.
    function test_emitsSpendRouted_erc20() public {
        uint160 spendAmount = 500e18;
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            address(token), 1000e18, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        _approvePermission(permission);

        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(permission, 0);
        withdrawRequest.asset = address(token);
        withdrawRequest.amount = spendAmount;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        token.mint(address(magicSpend), spendAmount);

        bytes32 permHash = permissionManager.getHash(permission);
        vm.prank(executor);
        vm.expectEmit(true, true, true, true);
        emit SpendRouter.SpendRouted(address(account), executor, recipient, permHash, address(token), spendAmount);
        router.spendWithWithdrawAndRoute(permission, spendAmount, withdrawRequest);
    }

    /// @notice Successfully spends with combined existing balance and MagicSpend withdraw for native token.
    function test_combinedBalance_nativeToken() public {
        uint160 existingBalance = 0.3 ether;
        uint160 withdrawAmount = 0.7 ether;
        uint160 totalSpend = existingBalance + withdrawAmount;
        uint48 start = uint48(block.timestamp);

        SpendPermissionManager.SpendPermission memory permission =
            _createPermission(NATIVE_TOKEN, totalSpend, 1 days, start, start + 1 days, 0);
        _approvePermission(permission);

        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(permission, 0);
        withdrawRequest.amount = withdrawAmount;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        vm.deal(address(magicSpend), withdrawAmount);
        vm.deal(address(account), existingBalance);

        vm.prank(executor);
        router.spendWithWithdrawAndRoute(permission, totalSpend, withdrawRequest);

        assertEq(address(recipient).balance, totalSpend);
        assertEq(address(account).balance, 0);
        assertEq(address(magicSpend).balance, 0);
    }

    /// @notice Successfully spends with combined existing balance and MagicSpend withdraw for ERC-20.
    function test_combinedBalance_erc20() public {
        uint160 existingBalance = 300e18;
        uint160 withdrawAmount = 700e18;
        uint160 totalSpend = existingBalance + withdrawAmount;
        uint48 start = uint48(block.timestamp);

        SpendPermissionManager.SpendPermission memory permission =
            _createPermission(address(token), totalSpend, 1 days, start, start + 1 days, 0);
        _approvePermission(permission);

        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(permission, 0);
        withdrawRequest.asset = address(token);
        withdrawRequest.amount = withdrawAmount;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        token.mint(address(magicSpend), withdrawAmount);
        token.mint(address(account), existingBalance);

        vm.prank(executor);
        router.spendWithWithdrawAndRoute(permission, totalSpend, withdrawRequest);

        assertEq(token.balanceOf(recipient), totalSpend);
        assertEq(token.balanceOf(address(account)), 0);
        assertEq(token.balanceOf(address(magicSpend)), 0);
    }

    /// @notice Reverts when the permission is revoked.
    function test_revert_revokedPermission() public {
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        _approvePermission(permission);

        // Revoke permission
        vm.prank(address(account));
        permissionManager.revoke(permission);

        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(permission, 0);
        withdrawRequest.amount = 0.5 ether;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        vm.prank(executor);
        vm.expectRevert(SpendPermissionManager.UnauthorizedSpendPermission.selector);
        router.spendWithWithdrawAndRoute(permission, 0.5 ether, withdrawRequest);
    }

    /// @notice Reverts with SpendTokenWithdrawAssetMismatch when token and withdraw asset differ.
    function test_revert_tokenWithdrawAssetMismatch() public {
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        _approvePermission(permission);

        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(permission, 0);
        withdrawRequest.asset = address(token); // mismatch: permission is NATIVE_TOKEN, withdraw is ERC-20
        withdrawRequest.amount = 0.5 ether;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                SpendPermissionManager.SpendTokenWithdrawAssetMismatch.selector, NATIVE_TOKEN, address(token)
            )
        );
        router.spendWithWithdrawAndRoute(permission, 0.5 ether, withdrawRequest);
    }

    /// @notice Reverts with SpendValueWithdrawAmountMismatch when withdraw amount exceeds spend value.
    function test_revert_spendLessThanWithdrawAmount() public {
        uint160 spendValue = 0.3 ether;
        uint160 withdrawAmount = 0.5 ether;

        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        _approvePermission(permission);

        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(permission, 0);
        withdrawRequest.amount = withdrawAmount;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                SpendPermissionManager.SpendValueWithdrawAmountMismatch.selector, spendValue, withdrawAmount
            )
        );
        router.spendWithWithdrawAndRoute(permission, spendValue, withdrawRequest);
    }
}
