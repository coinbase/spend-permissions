// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SpendPermission, SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";

import {Vm, console2} from "forge-std/Test.sol";

import {IERC165} from "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import {MockERC20} from "solady/../test/utils/mocks/MockERC20.sol";
import {MockERC721} from "solady/../test/utils/mocks/MockERC721.sol";

contract ApproveWithNullAccountTest is SpendPermissionManagerBase {
    MockERC721 mockERC721;
    bytes4 public constant ERC721_INTERFACE_ID = 0x80ac58cd;

    function setUp() public {
        _initializeSpendPermissionManager();
        mockERC721 = new MockERC721();
    }

    function test_approveWithSenderAsAccount_revert_nonZeroAccount(
        address sender,
        address account,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(sender != address(0));
        vm.assume(account != address(0));
        vm.assume(sender != account);

        SpendPermission memory spendPermission = SpendPermission({
            account: account,
            spender: spender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });

        vm.startPrank(sender);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.NonZeroAccount.selector, account));
        mockSpendPermissionManager.approveWithSenderAsAccount(spendPermission);
        vm.stopPrank();
    }

    function test_approveWithSenderAsAccount_revert_invalidStartEnd(
        address account,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(period > 0);
        vm.assume(allowance > 0);
        vm.assume(start >= end);

        SpendPermission memory spendPermission = SpendPermission({
            account: account,
            spender: spender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        spendPermission.account = address(0);

        vm.startPrank(account);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.InvalidStartEnd.selector, start, end));
        mockSpendPermissionManager.approveWithSenderAsAccount(spendPermission);
        vm.stopPrank();
    }

    function test_approveWithSenderAsAccount_revert_invalidTokenZeroAddress(
        address account,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(start < end);

        SpendPermission memory spendPermission = SpendPermission({
            account: account,
            spender: spender,
            token: address(0),
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        spendPermission.account = address(0);

        vm.startPrank(account);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.ZeroToken.selector));
        mockSpendPermissionManager.approveWithSenderAsAccount(spendPermission);
        vm.stopPrank();
    }

    function test_approveWithSenderAsAccount_revert_invalidSpenderZeroAddress(
        address account,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        assumeNotPrecompile(token);
        vm.assume(token != address(0));
        vm.assume(start < end);
        vm.assume(allowance > 0);

        SpendPermission memory spendPermission = SpendPermission({
            account: account,
            spender: address(0),
            token: token,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        spendPermission.account = address(0);

        vm.startPrank(account);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.ZeroSpender.selector));
        mockSpendPermissionManager.approveWithSenderAsAccount(spendPermission);
        vm.stopPrank();
    }

    function test_approveWithSenderAsAccount_revert_zeroPeriod(
        address account,
        address spender,
        uint48 start,
        uint48 end,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(start < end);

        SpendPermission memory spendPermission = SpendPermission({
            account: account,
            spender: spender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: 0,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        spendPermission.account = address(0);

        vm.startPrank(account);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.ZeroPeriod.selector));
        mockSpendPermissionManager.approveWithSenderAsAccount(spendPermission);
        vm.stopPrank();
    }

    function test_approveWithSenderAsAccount_revert_zeroAllowance(
        address account,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(start < end);
        vm.assume(period > 0);

        SpendPermission memory spendPermission = SpendPermission({
            account: account,
            spender: spender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: period,
            allowance: 0,
            salt: salt,
            extraData: extraData
        });
        spendPermission.account = address(0);

        vm.startPrank(account);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.ZeroAllowance.selector));
        mockSpendPermissionManager.approveWithSenderAsAccount(spendPermission);
        vm.stopPrank();
    }

    function test_approveWithSenderAsAccount_success_isAuthorized(
        address account,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(account != address(0));
        vm.assume(spender != address(0));
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

        SpendPermission memory spendPermission = SpendPermission({
            account: account,
            spender: spender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        spendPermission.account = address(0);

        vm.prank(account);
        mockSpendPermissionManager.approveWithSenderAsAccount(spendPermission);
        spendPermission.account = account;
        vm.assertTrue(mockSpendPermissionManager.isValid(spendPermission));
    }

    function test_approveWithSenderAsAccount_success_emitsEvent(
        address account,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(account != address(0));
        vm.assume(spender != address(0));
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

        SpendPermission memory spendPermission = SpendPermission({
            account: account,
            spender: spender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });

        vm.startPrank(account);
        vm.expectEmit(address(mockSpendPermissionManager));
        emit SpendPermissionManager.SpendPermissionApproved({
            hash: mockSpendPermissionManager.getHash(spendPermission),
            spendPermission: spendPermission
        });
        spendPermission.account = address(0);
        mockSpendPermissionManager.approveWithSenderAsAccount(spendPermission);
    }

    function test_approveWithSenderAsAccount_success_returnsTrue(
        address account,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(account != address(0));
        vm.assume(spender != address(0));
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

        SpendPermission memory spendPermission = SpendPermission({
            account: account,
            spender: spender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        spendPermission.account = address(0);

        vm.prank(account);
        bool approved = mockSpendPermissionManager.approveWithSenderAsAccount(spendPermission);
        vm.assertTrue(approved);

        spendPermission.account = account;
        vm.assertTrue(mockSpendPermissionManager.isValid(spendPermission));
    }

    function test_approveWithSenderAsAccount_success_returnsTrueNoEventEmittedIfAlreadyApproved(
        address account,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(account != address(0));
        vm.assume(spender != address(0));
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

        SpendPermission memory spendPermission = SpendPermission({
            account: account,
            spender: spender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        spendPermission.account = address(0);

        vm.startPrank(account);
        mockSpendPermissionManager.approveWithSenderAsAccount(spendPermission); // approve permission before second
            // approval
        vm.recordLogs();
        bool approved = mockSpendPermissionManager.approveWithSenderAsAccount(spendPermission);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.assertEq(logs.length, 0); // no event emitted
        vm.assertTrue(approved);

        spendPermission.account = account;
        vm.assertTrue(mockSpendPermissionManager.isValid(spendPermission));
    }

    function test_approveWithSenderAsAccount_success_returnsFalseIfPermissionRevoked(
        address account,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(account != address(0));
        vm.assume(spender != address(0));
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

        SpendPermission memory spendPermission = SpendPermission({
            account: account,
            spender: spender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        vm.startPrank(account);
        mockSpendPermissionManager.revoke(spendPermission); // revoke permission before approval

        spendPermission.account = address(0);
        vm.recordLogs();
        bool approved = mockSpendPermissionManager.approveWithSenderAsAccount(spendPermission);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.assertEq(logs.length, 0); // no event emitted
        vm.assertFalse(approved); // returns false

        spendPermission.account = account;
        vm.assertFalse(mockSpendPermissionManager.isValid(spendPermission)); // permission is not approved
    }

    function test_approveWithSenderAsAccount_revert_erc721Token(
        address account,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(account != address(0));
        vm.assume(spender != address(0));
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

        // First verify our mock ERC721 actually supports the interface
        bool supported = IERC165(address(mockERC721)).supportsInterface(ERC721_INTERFACE_ID);

        SpendPermission memory spendPermission = SpendPermission({
            account: account,
            spender: spender,
            token: address(mockERC721),
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        spendPermission.account = address(0);

        vm.startPrank(account);
        vm.expectRevert(
            abi.encodeWithSelector(SpendPermissionManager.ERC721TokenNotSupported.selector, address(mockERC721))
        );
        mockSpendPermissionManager.approveWithSenderAsAccount(spendPermission);
        vm.stopPrank();
    }
}
