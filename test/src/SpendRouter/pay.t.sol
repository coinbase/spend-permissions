// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SpendPermissionManager} from "src/SpendPermissionManager.sol";
import {SpendRouter} from "src/SpendRouter.sol";
import {SpendRouterTestBase} from "test/src/SpendRouter/SpendRouterTestBase.sol";
import {MockERC20MissingReturn} from "test/mocks/MockERC20MissingReturn.sol";

contract PayTest is SpendRouterTestBase {
    function test_pay_nativeToken() public {
        // Create and approve permission
        uint160 allowance = 1 ether;
        uint48 period = 1 days;
        uint48 start = uint48(block.timestamp);
        uint48 end = start + period;
        SpendPermissionManager.SpendPermission memory permission =
            _createPermission(NATIVE_TOKEN, allowance, period, start, end, 0);
        _approvePermission(permission);

        // Fund account
        vm.deal(address(account), allowance);

        // Execute spend
        uint160 spendAmount = 0.5 ether;
        vm.prank(executor);
        router.spendAndRoute(permission, spendAmount);

        // Verify results
        assertEq(address(recipient).balance, spendAmount);
        assertEq(address(account).balance, allowance - spendAmount);
    }

    function test_pay_erc20() public {
        // Create and approve permission
        uint160 allowance = 1000e18;
        uint48 period = 1 days;
        uint48 start = uint48(block.timestamp);
        uint48 end = start + period;
        SpendPermissionManager.SpendPermission memory permission =
            _createPermission(address(token), allowance, period, start, end, 0);
        _approvePermission(permission);

        // Fund account
        token.mint(address(account), allowance);

        // Execute spend
        uint160 spendAmount = 500e18;
        vm.prank(executor);
        router.spendAndRoute(permission, spendAmount);

        // Verify results
        assertEq(token.balanceOf(recipient), spendAmount);
        assertEq(token.balanceOf(address(account)), allowance - spendAmount);
    }

    function test_pay_revert_unauthorizedSender() public {
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        _approvePermission(permission);

        address unauthorizedSender = makeAddr("unauthorized");
        vm.prank(unauthorizedSender);
        vm.expectRevert(abi.encodeWithSelector(SpendRouter.UnauthorizedSender.selector, unauthorizedSender, executor));
        router.spendAndRoute(permission, 0.5 ether);
    }

    // --- Edge-case tests ---

    function test_pay_revert_malformedExtraData(bytes memory extraData) public {
        vm.assume(extraData.length != 64);

        // Create permission with fuzzed malformed extraData
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        permission.extraData = extraData;

        // Execute spend — should revert before reaching SpendPermissionManager
        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(SpendRouter.MalformedExtraData.selector, extraData.length, extraData));
        router.spendAndRoute(permission, 0.5 ether);
    }

    function test_pay_revert_recipientIsZeroAddress() public {
        // Create permission with zero-address recipient in extraData
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        permission.extraData = abi.encode(executor, address(0));
        _approvePermission(permission);

        // Fund account
        vm.deal(address(account), 1 ether);

        // Execute spend — should revert with ZeroAddress
        vm.prank(executor);
        vm.expectRevert(SpendRouter.ZeroAddress.selector);
        router.spendAndRoute(permission, 0.5 ether);
    }

    function test_pay_revert_exceedsAllowance() public {
        // Create and approve permission with 1 ETH allowance
        uint160 allowance = 1 ether;
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, allowance, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        _approvePermission(permission);

        // Fund account with more than allowance
        vm.deal(address(account), 10 ether);

        // Execute spend for allowance + 1 — should revert
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                SpendPermissionManager.ExceededSpendPermission.selector,
                uint256(allowance) + 1,
                allowance
            )
        );
        router.spendAndRoute(permission, allowance + 1);
    }

    function test_pay_revert_zeroValue() public {
        // Create and approve permission
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        _approvePermission(permission);

        // Execute spend with zero value — should revert
        vm.prank(executor);
        vm.expectRevert(SpendPermissionManager.ZeroValue.selector);
        router.spendAndRoute(permission, 0);
    }

    function test_pay_revert_permissionNotApproved() public {
        // Create permission but do NOT approve it
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );

        // Execute spend — should revert as unapproved
        vm.prank(executor);
        vm.expectRevert(SpendPermissionManager.UnauthorizedSpendPermission.selector);
        router.spendAndRoute(permission, 0.5 ether);
    }

    function test_pay_revert_permissionExpired() public {
        // Create and approve permission
        uint48 start = uint48(block.timestamp);
        uint48 end = start + 1 days;
        SpendPermissionManager.SpendPermission memory permission =
            _createPermission(NATIVE_TOKEN, 1 ether, 1 days, start, end, 0);
        _approvePermission(permission);

        // Warp to expiration
        vm.warp(end);

        // Execute spend — should revert as expired
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(SpendPermissionManager.AfterSpendPermissionEnd.selector, uint48(block.timestamp), end)
        );
        router.spendAndRoute(permission, 0.5 ether);
    }

    function test_pay_revert_permissionNotStarted() public {
        // Create and approve permission with future start time
        uint48 start = uint48(block.timestamp) + 1 hours;
        uint48 end = start + 1 days;
        SpendPermissionManager.SpendPermission memory permission =
            _createPermission(NATIVE_TOKEN, 1 ether, 1 days, start, end, 0);
        _approvePermission(permission);

        // Execute spend before start — should revert
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                SpendPermissionManager.BeforeSpendPermissionStart.selector, uint48(block.timestamp), start
            )
        );
        router.spendAndRoute(permission, 0.5 ether);
    }

    function test_pay_revert_revokedPermission() public {
        // Create and approve permission
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        _approvePermission(permission);

        // Revoke permission
        vm.prank(address(account));
        permissionManager.revoke(permission);

        // Execute spend — should revert as revoked
        vm.prank(executor);
        vm.expectRevert(SpendPermissionManager.UnauthorizedSpendPermission.selector);
        router.spendAndRoute(permission, 0.5 ether);
    }

    function test_pay_multipleSpends_exceedsAllowanceCumulatively() public {
        // Create and approve permission with 1 ETH allowance
        uint160 allowance = 1 ether;
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, allowance, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        _approvePermission(permission);

        // Fund account
        vm.deal(address(account), 10 ether);

        // First spend succeeds (0.6 ETH)
        vm.startPrank(executor);
        router.spendAndRoute(permission, 0.6 ether);

        // Second spend reverts — cumulative 1.2 ETH exceeds 1 ETH allowance
        vm.expectRevert(
            abi.encodeWithSelector(
                SpendPermissionManager.ExceededSpendPermission.selector,
                uint256(0.6 ether) + uint256(0.6 ether),
                allowance
            )
        );
        router.spendAndRoute(permission, 0.6 ether);
        vm.stopPrank();
    }

    function test_pay_periodReset_allowsSpendingAgain() public {
        // Create and approve permission with multi-day end
        uint48 period = 1 days;
        uint160 allowance = 1 ether;
        uint48 start = uint48(block.timestamp);
        uint48 end = start + 10 days;
        SpendPermissionManager.SpendPermission memory permission =
            _createPermission(NATIVE_TOKEN, allowance, period, start, end, 0);
        _approvePermission(permission);

        // Fund account
        vm.deal(address(account), 10 ether);

        // Spend full allowance in first period
        vm.prank(executor);
        router.spendAndRoute(permission, allowance);
        assertEq(address(recipient).balance, allowance);

        // Warp to next period
        vm.warp(block.timestamp + period);

        // Spend full allowance again — period reset allows it
        vm.prank(executor);
        router.spendAndRoute(permission, allowance);
        assertEq(address(recipient).balance, allowance * 2);
    }

    function test_pay_emitsSpendRouted_nativeToken() public {
        // Create and approve permission
        uint160 spendAmount = 0.5 ether;
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        _approvePermission(permission);

        // Fund account
        vm.deal(address(account), 1 ether);

        // Execute spend — verify SpendRouted event
        bytes32 permHash = permissionManager.getHash(permission);
        vm.prank(executor);
        vm.expectEmit(true, true, true, true);
        emit SpendRouter.SpendRouted(address(account), executor, recipient, permHash, NATIVE_TOKEN, spendAmount);
        router.spendAndRoute(permission, spendAmount);
    }

    function test_pay_emitsSpendRouted_erc20() public {
        // Create and approve permission
        uint160 spendAmount = 500e18;
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            address(token), 1000e18, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        _approvePermission(permission);

        // Fund account
        token.mint(address(account), 1000e18);

        // Execute spend — verify SpendRouted event
        bytes32 permHash = permissionManager.getHash(permission);
        vm.prank(executor);
        vm.expectEmit(true, true, true, true);
        emit SpendRouter.SpendRouted(address(account), executor, recipient, permHash, address(token), spendAmount);
        router.spendAndRoute(permission, spendAmount);
    }

    function test_pay_erc20MissingReturn() public {
        // Deploy non-standard ERC-20 that omits return value on transfer
        MockERC20MissingReturn badToken = new MockERC20MissingReturn("Bad", "BAD", 18);
        uint160 allowance = 1000e18;
        uint160 spendAmount = 500e18;

        // Create and approve permission
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            address(badToken), allowance, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        _approvePermission(permission);

        // Fund account
        badToken.mint(address(account), allowance);

        // Execute spend — SafeTransferLib handles missing return
        vm.prank(executor);
        router.spendAndRoute(permission, spendAmount);

        // Verify results
        assertEq(badToken.balanceOf(recipient), spendAmount);
        assertEq(badToken.balanceOf(address(account)), allowance - spendAmount);
    }
}
