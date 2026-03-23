// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SpendPermissionManager} from "src/SpendPermissionManager.sol";
import {SpendRouter} from "src/SpendRouter.sol";
import {MockERC20MissingReturn} from "test/mocks/MockERC20MissingReturn.sol";
import {SpendRouterTestBase} from "test/src/SpendRouter/SpendRouterTestBase.sol";

contract PayWithSignatureTest is SpendRouterTestBase {
    /// @notice Reverts with MalformedExtraData when permission.extraData is not exactly 64 bytes.
    /// @dev First check in spendAndRouteWithSignature() via decodeExtraData. Fuzz extraData to any length != 64.
    /// @param extraData Fuzzed bytes payload (excluded: length == 64).
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
    /// @dev Second check in spendAndRouteWithSignature(). Fuzz the unauthorized sender, excluding the actual executor
    /// address. @param sender Fuzzed caller address (excluded: executor).
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
    /// @dev Third check in spendAndRouteWithSignature(). Uses manually crafted extraData with abi.encode(executor,
    /// address(0)).
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
    /// @param spendAmount Fuzzed spend value (bounded: 1 to allowance).
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
    /// @param spendAmount Fuzzed spend value (bounded: 1 to allowance).
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

    // --- Edge-case tests ---

    /// @notice Reverts with InvalidSignature when the signature is from a non-owner key.
    /// @dev Signs with a key that is not an owner of the account. approveWithSignature should reject.
    function test_reverts_whenSignatureInvalid() public {
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );

        uint256 wrongPk = uint256(keccak256("wrong_signer"));
        bytes32 permissionHash = permissionManager.getHash(permission);
        bytes32 replaySafeHash = account.replaySafeHash(permissionHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPk, replaySafeHash);
        bytes memory wrappedBadSig = _applySignatureWrapper(0, abi.encodePacked(r, s, v));

        vm.prank(executor);
        vm.expectRevert(SpendPermissionManager.InvalidSignature.selector);
        router.spendAndRouteWithSignature(permission, 0.5 ether, wrappedBadSig);
    }

    /// @notice Reverts with ZeroValue when spend amount is zero.
    /// @dev Permission approves successfully, but SpendPermissionManager._useSpendPermission reverts on zero value.
    function test_reverts_whenSpendAmountIsZero() public {
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        bytes memory signature = _signPermission(permission);

        vm.prank(executor);
        vm.expectRevert(SpendPermissionManager.ZeroValue.selector);
        router.spendAndRouteWithSignature(permission, 0, signature);
    }

    /// @notice Reverts with ExceededSpendPermission when spend amount exceeds the period allowance.
    /// @dev Attempts to spend allowance + 1 wei in a single call.
    function test_reverts_whenExceedsAllowance() public {
        uint160 allowance = 1 ether;
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, allowance, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        bytes memory signature = _signPermission(permission);
        vm.deal(address(account), 10 ether);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                SpendPermissionManager.ExceededSpendPermission.selector, uint256(allowance) + 1, allowance
            )
        );
        router.spendAndRouteWithSignature(permission, allowance + 1, signature);
    }

    /// @notice Reverts with BeforeSpendPermissionStart when permission has not started yet.
    /// @dev Sets start 1 hour in the future, attempts to spend at current timestamp.
    function test_reverts_whenPermissionNotStarted() public {
        uint48 start = uint48(block.timestamp) + 1 hours;
        uint48 end = start + 1 days;
        SpendPermissionManager.SpendPermission memory permission =
            _createPermission(NATIVE_TOKEN, 1 ether, 1 days, start, end, 0);
        bytes memory signature = _signPermission(permission);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                SpendPermissionManager.BeforeSpendPermissionStart.selector, uint48(block.timestamp), start
            )
        );
        router.spendAndRouteWithSignature(permission, 0.5 ether, signature);
    }

    /// @notice Reverts with AfterSpendPermissionEnd when permission has expired.
    /// @dev Warps to exactly the end timestamp (exclusive), so the permission is no longer valid.
    function test_reverts_whenPermissionExpired() public {
        uint48 start = uint48(block.timestamp);
        uint48 end = start + 1 days;
        SpendPermissionManager.SpendPermission memory permission =
            _createPermission(NATIVE_TOKEN, 1 ether, 1 days, start, end, 0);
        bytes memory signature = _signPermission(permission);

        vm.warp(end);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                SpendPermissionManager.AfterSpendPermissionEnd.selector, uint48(block.timestamp), end
            )
        );
        router.spendAndRouteWithSignature(permission, 0.5 ether, signature);
    }

    /// @notice Reverts with PermissionApprovalFailed when permission was revoked after first use.
    /// @dev Spends once successfully, revokes via account, then a second spendAndRouteWithSignature
    ///      fails because approveWithSignature returns false for revoked permissions.
    function test_reverts_whenPermissionRevoked() public {
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        bytes memory signature = _signPermission(permission);
        vm.deal(address(account), 1 ether);

        // First spend succeeds
        vm.prank(executor);
        router.spendAndRouteWithSignature(permission, 0.5 ether, signature);

        // Account revokes the permission
        vm.prank(address(account));
        permissionManager.revoke(permission);

        // Second spend fails — revoked permission cannot be re-approved
        vm.prank(executor);
        vm.expectRevert(SpendRouter.PermissionApprovalFailed.selector);
        router.spendAndRouteWithSignature(permission, 0.5 ether, signature);
    }

    /// @notice Emits SpendRouted event with correct indexed and non-indexed parameters.
    /// @dev Verifies all four indexed topics plus the non-indexed value field.
    function test_emitsSpendRouted() public {
        uint160 spendAmount = 0.5 ether;
        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        bytes memory signature = _signPermission(permission);
        vm.deal(address(account), 1 ether);

        bytes32 permHash = permissionManager.getHash(permission);

        vm.prank(executor);
        vm.expectEmit(true, true, true, true);
        emit SpendRouter.SpendRouted(address(account), executor, recipient, permHash, NATIVE_TOKEN, spendAmount);
        router.spendAndRouteWithSignature(permission, spendAmount, signature);
    }

    /// @notice ERC-20 tokens with missing return values still transfer correctly via SafeTransferLib.
    /// @dev Uses MockERC20MissingReturn which returns no data from transfer/transferFrom.
    ///      Verifies SafeTransferLib handles the non-standard behavior gracefully.
    function test_erc20MissingReturn() public {
        MockERC20MissingReturn badToken = new MockERC20MissingReturn("Bad", "BAD", 18);
        uint160 allowance = 1000e18;
        uint160 spendAmount = 500e18;

        SpendPermissionManager.SpendPermission memory permission = _createPermission(
            address(badToken), allowance, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0
        );
        bytes memory signature = _signPermission(permission);
        badToken.mint(address(account), allowance);

        vm.prank(executor);
        router.spendAndRouteWithSignature(permission, spendAmount, signature);

        assertEq(badToken.balanceOf(recipient), spendAmount);
        assertEq(badToken.balanceOf(address(account)), allowance - spendAmount);
    }
}
