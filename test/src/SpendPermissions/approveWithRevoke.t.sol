// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";

import {Vm} from "forge-std/Test.sol";

contract ApproveWithRevokeTest is SpendPermissionManagerBase {
    SpendPermissionManager.SpendPermission existingSpendPermission;
    SpendPermissionManager.PeriodSpend lastValidUpdatedPeriod;

    function setUp() public {
        _initializeSpendPermissionManager();
        vm.prank(owner);
        account.addOwnerAddress(address(mockSpendPermissionManager));

        // establish an existing spend permission and capture the last valid updated period
        existingSpendPermission = _createSpendPermission();
        vm.prank(address(account));
        mockSpendPermissionManager.approve(existingSpendPermission);
        lastValidUpdatedPeriod = mockSpendPermissionManager.getLastUpdatedPeriod(existingSpendPermission);
    }

    function test_approveWithRevoke_revert_invalidSender(
        address sender,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(sender != address(0));
        vm.assume(sender != address(account));
        SpendPermissionManager.SpendPermission memory newSpendPermission = SpendPermissionManager.SpendPermission({
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
        vm.startPrank(sender);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.InvalidSender.selector, sender, account));
        mockSpendPermissionManager.approveWithRevoke(
            newSpendPermission, existingSpendPermission, lastValidUpdatedPeriod
        );
        vm.stopPrank();
    }

    function test_approveWithRevoke_revert_mismatchedAccounts(
        address newAccount,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(newAccount != address(0));
        vm.assume(newAccount != address(account));
        SpendPermissionManager.SpendPermission memory newSpendPermission = SpendPermissionManager.SpendPermission({
            account: newAccount,
            spender: spender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        vm.startPrank(newAccount);
        vm.expectRevert(
            abi.encodeWithSelector(SpendPermissionManager.MismatchedAccounts.selector, newAccount, address(account))
        );
        mockSpendPermissionManager.approveWithRevoke(
            newSpendPermission, existingSpendPermission, lastValidUpdatedPeriod
        );
        vm.stopPrank();
    }

    function test_approveWithRevoke_revert_invalidLastUpdatedPeriod_moreSpendSamePeriod(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(spender != address(account));
        vm.assume(start > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);
        vm.deal(address(account), 1 ether);

        SpendPermissionManager.SpendPermission memory newSpendPermission = SpendPermissionManager.SpendPermission({
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
        // spend after having calculated the `lastValidUpdatedPeriod`
        vm.prank(existingSpendPermission.spender);
        mockSpendPermissionManager.spend(existingSpendPermission, 1 wei);
        // this will be the actual last updated period onchain
        SpendPermissionManager.PeriodSpend memory invalidLastUpdatedPeriod =
            mockSpendPermissionManager.getLastUpdatedPeriod(existingSpendPermission);
        vm.startPrank(address(account));
        vm.expectRevert(
            abi.encodeWithSelector(
                SpendPermissionManager.InvalidLastUpdatedPeriod.selector,
                invalidLastUpdatedPeriod,
                lastValidUpdatedPeriod
            )
        );
        mockSpendPermissionManager.approveWithRevoke(
            newSpendPermission, existingSpendPermission, lastValidUpdatedPeriod
        );
        vm.stopPrank();
    }

    function test_approveWithRevoke_revert_invalidLastUpdatedPeriod_sameSpendNewPeriod(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(spender != address(account));
        vm.assume(start > 0);
        vm.assume(uint256(start) + uint256(period) * 2 < end); // make sure we have room for at least two periods
        vm.assume(period > 0);
        vm.assume(period <= (end - start) / 2);
        vm.assume(allowance > 0);
        vm.deal(address(account), 1 ether);

        SpendPermissionManager.SpendPermission memory newSpendPermission = SpendPermissionManager.SpendPermission({
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
        // spend a little
        vm.startPrank(existingSpendPermission.spender);
        mockSpendPermissionManager.spend(existingSpendPermission, 1 wei);
        lastValidUpdatedPeriod = mockSpendPermissionManager.getLastUpdatedPeriod(existingSpendPermission);

        // jump forward one period and spend same amount again
        vm.warp(existingSpendPermission.start + existingSpendPermission.period);
        mockSpendPermissionManager.spend(existingSpendPermission, 1 wei);

        // this will now be the last updated period onchain
        SpendPermissionManager.PeriodSpend memory invalidLastUpdatedPeriod =
            mockSpendPermissionManager.getLastUpdatedPeriod(existingSpendPermission);
        vm.startPrank(address(account));
        vm.expectRevert(
            abi.encodeWithSelector(
                SpendPermissionManager.InvalidLastUpdatedPeriod.selector,
                invalidLastUpdatedPeriod,
                lastValidUpdatedPeriod
            )
        );
        mockSpendPermissionManager.approveWithRevoke(
            newSpendPermission, existingSpendPermission, lastValidUpdatedPeriod
        );
        vm.stopPrank();
    }

    function test_approveWithRevoke_revert_invalidLastUpdatedPeriod_sameSpendSeveralElapsedPeriods(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(spender != address(account));
        vm.assume(start > 0);
        vm.assume(uint256(start) + uint256(period) * 4 < end); // make sure we have room for at least two periods
        vm.assume(period > 0);
        vm.assume(period <= (end - start) / 4);
        vm.assume(allowance > 0);
        vm.deal(address(account), 1 ether);

        SpendPermissionManager.SpendPermission memory newSpendPermission = SpendPermissionManager.SpendPermission({
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
        // spend a little
        vm.startPrank(existingSpendPermission.spender);
        mockSpendPermissionManager.spend(existingSpendPermission, 1 wei);
        lastValidUpdatedPeriod = mockSpendPermissionManager.getLastUpdatedPeriod(existingSpendPermission);

        // jump forward several periods and spend same amount again
        vm.warp(existingSpendPermission.start + existingSpendPermission.period * 4);
        mockSpendPermissionManager.spend(existingSpendPermission, 1 wei);

        // this will now be the last updated period onchain
        SpendPermissionManager.PeriodSpend memory invalidLastUpdatedPeriod =
            mockSpendPermissionManager.getLastUpdatedPeriod(existingSpendPermission);
        vm.startPrank(address(account));
        vm.expectRevert(
            abi.encodeWithSelector(
                SpendPermissionManager.InvalidLastUpdatedPeriod.selector,
                invalidLastUpdatedPeriod,
                lastValidUpdatedPeriod
            )
        );
        mockSpendPermissionManager.approveWithRevoke(
            newSpendPermission, existingSpendPermission, lastValidUpdatedPeriod
        );
        vm.stopPrank();
    }

    function test_approveWithRevoke_success_oldRevokedNewApproved(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(spender != address(account));
        vm.assume(start > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

        SpendPermissionManager.SpendPermission memory newSpendPermission = SpendPermissionManager.SpendPermission({
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
        vm.startPrank(address(account));
        mockSpendPermissionManager.approveWithRevoke(
            newSpendPermission, existingSpendPermission, lastValidUpdatedPeriod
        );
        vm.stopPrank();
        vm.assertFalse(mockSpendPermissionManager.isValid(existingSpendPermission));
        vm.assertTrue(mockSpendPermissionManager.isValid(newSpendPermission));
    }

    function test_approveWithRevoke_success_returnsTrueOldRevokedNewApproved(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(spender != address(account));
        vm.assume(start > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

        SpendPermissionManager.SpendPermission memory newSpendPermission = SpendPermissionManager.SpendPermission({
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
        vm.startPrank(address(account));
        bool isApproved = mockSpendPermissionManager.approveWithRevoke(
            newSpendPermission, existingSpendPermission, lastValidUpdatedPeriod
        );
        vm.stopPrank();
        vm.assertTrue(isApproved);
        vm.assertFalse(mockSpendPermissionManager.isValid(existingSpendPermission));
        vm.assertTrue(mockSpendPermissionManager.isValid(newSpendPermission));
    }

    function test_approveWithRevoke_success_returnsFalseIfOldRevokedNewApprovedAfterBeingRevoked(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(spender != address(account));
        vm.assume(start > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

        SpendPermissionManager.SpendPermission memory newSpendPermission = SpendPermissionManager.SpendPermission({
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
        vm.startPrank(address(account));
        mockSpendPermissionManager.revoke(newSpendPermission); // preemptively revoke the new spend permission
        vm.expectEmit(address(mockSpendPermissionManager));
        emit SpendPermissionManager.SpendPermissionRevoked({
            hash: mockSpendPermissionManager.getHash(existingSpendPermission),
            spendPermission: existingSpendPermission
        });
        vm.recordLogs();
        bool isApproved = mockSpendPermissionManager.approveWithRevoke(
            newSpendPermission, existingSpendPermission, lastValidUpdatedPeriod
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1); // only the revoke log emitted
        vm.stopPrank();
        vm.assertFalse(isApproved);
        vm.assertFalse(mockSpendPermissionManager.isValid(existingSpendPermission));
        vm.assertFalse(mockSpendPermissionManager.isValid(newSpendPermission));
    }

    function test_approveWithRevoke_success_emitsEvents(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(spender != address(account));
        vm.assume(start > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

        SpendPermissionManager.SpendPermission memory newSpendPermission = SpendPermissionManager.SpendPermission({
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
        vm.startPrank(address(account));
        vm.expectEmit(address(mockSpendPermissionManager));
        emit SpendPermissionManager.SpendPermissionRevoked({
            hash: mockSpendPermissionManager.getHash(existingSpendPermission),
            spendPermission: existingSpendPermission
        });
        vm.expectEmit(address(mockSpendPermissionManager));
        emit SpendPermissionManager.SpendPermissionApproved({
            hash: mockSpendPermissionManager.getHash(newSpendPermission),
            spendPermission: newSpendPermission
        });
        mockSpendPermissionManager.approveWithRevoke(
            newSpendPermission, existingSpendPermission, lastValidUpdatedPeriod
        );
        vm.stopPrank();
    }

    function test_approveWithRevoke_success_severalPeriodsTimeElapsed(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(spender != address(account));
        vm.assume(start > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

        SpendPermissionManager.SpendPermission memory newSpendPermission = SpendPermissionManager.SpendPermission({
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
        vm.warp(existingSpendPermission.start + existingSpendPermission.period * 4);
        vm.startPrank(address(account));
        mockSpendPermissionManager.approveWithRevoke(
            newSpendPermission, existingSpendPermission, lastValidUpdatedPeriod
        );
        vm.stopPrank();
        vm.assertFalse(mockSpendPermissionManager.isValid(existingSpendPermission));
        vm.assertTrue(mockSpendPermissionManager.isValid(newSpendPermission));
    }

    function test_approveWithRevoke_success_nonZeroSpend(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(spender != address(account));
        vm.assume(start > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

        vm.deal(address(account), 1 ether);
        vm.prank(existingSpendPermission.spender);
        mockSpendPermissionManager.spend(existingSpendPermission, 1 wei);

        SpendPermissionManager.PeriodSpend memory latestPeriodSpend =
            mockSpendPermissionManager.getLastUpdatedPeriod(existingSpendPermission);
        SpendPermissionManager.SpendPermission memory newSpendPermission = SpendPermissionManager.SpendPermission({
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
        vm.warp(existingSpendPermission.start + existingSpendPermission.period * 4);
        vm.startPrank(address(account));
        mockSpendPermissionManager.approveWithRevoke(newSpendPermission, existingSpendPermission, latestPeriodSpend);
        vm.stopPrank();
        vm.assertFalse(mockSpendPermissionManager.isValid(existingSpendPermission));
        vm.assertTrue(mockSpendPermissionManager.isValid(newSpendPermission));
    }
}
