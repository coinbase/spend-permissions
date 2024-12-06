// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PeriodSpend, SpendPermission, SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";

contract UseSpendPermissionTest is SpendPermissionManagerBase {
    function setUp() public {
        _initializeSpendPermissionManager();
    }

    function test_useSpendPermission_revert_unauthorizedSpendPermission(
        address account,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint160 spend,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(period > 0);
        vm.assume(allowance > 0);
        vm.assume(spend > 0); // spend of 0 would be caught as unauthorized in permit version of `spend`, caller of
            // `useSpendPermission`

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

        vm.expectRevert(SpendPermissionManager.UnauthorizedSpendPermission.selector);
        mockSpendPermissionManager.useSpendPermission(spendPermission, spend);
    }

    function test_useSpendPermission_revert_spendValueOverflow(
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
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

        uint256 spend = uint256(type(uint160).max) + 1; // spend as a fuzz param with assumption spend > type(160).max
            // rejects too many inputs
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
        vm.prank(account);
        mockSpendPermissionManager.approve(spendPermission);
        vm.warp(start);

        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.SpendValueOverflow.selector, spend));
        mockSpendPermissionManager.useSpendPermission(spendPermission, spend);
    }

    function test_useSpendPermission_revert_exceededSpendPermission(
        address account,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint160 spend,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);
        vm.assume(spend > allowance);

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
        vm.prank(account);
        mockSpendPermissionManager.approve(spendPermission);
        vm.warp(start);

        vm.expectRevert(
            abi.encodeWithSelector(SpendPermissionManager.ExceededSpendPermission.selector, spend, allowance)
        );
        mockSpendPermissionManager.useSpendPermission(spendPermission, spend);
    }

    function test_useSpendPermission_revert_exceededSpendPermission_accruedSpend(
        address account,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData,
        uint160 firstSpend,
        uint160 secondSpend
    ) public {
        vm.assume(spender != address(0));
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);
        vm.assume(firstSpend > 0);
        vm.assume(firstSpend < allowance);
        vm.assume(secondSpend > allowance - firstSpend);
        vm.assume(secondSpend < type(uint160).max - firstSpend);

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
        vm.prank(account);
        mockSpendPermissionManager.approve(spendPermission);
        vm.warp(start);
        // make the first spend without using the full allowance
        mockSpendPermissionManager.useSpendPermission(spendPermission, firstSpend);

        // exceed the allowance with the second spend
        vm.expectRevert(
            abi.encodeWithSelector(
                SpendPermissionManager.ExceededSpendPermission.selector,
                _safeAddUint160(firstSpend, secondSpend),
                allowance
            )
        );
        mockSpendPermissionManager.useSpendPermission(spendPermission, secondSpend);
    }

    function test_useSpendPermission_revert_zeroValue() public {
        SpendPermission memory spendPermission = _createSpendPermission();
        vm.prank(spendPermission.account);
        mockSpendPermissionManager.approve(spendPermission);
        vm.expectRevert(SpendPermissionManager.ZeroValue.selector);
        mockSpendPermissionManager.useSpendPermission(spendPermission, 0);
    }

    function test_useSpendPermission_success_emitsEvent(SpendPermission memory spendPermission, uint160 spend) public {
        vm.assume(spendPermission.spender != address(0));
        vm.assume(spendPermission.start > 0);
        vm.assume(spendPermission.end > 0);
        vm.assume(spendPermission.start < spendPermission.end);
        vm.assume(spendPermission.period > 0);
        vm.assume(spendPermission.allowance > 0);
        vm.assume(spend > 0);
        vm.assume(spend < spendPermission.allowance);

        spendPermission.token = NATIVE_TOKEN;

        vm.prank(spendPermission.account);
        mockSpendPermissionManager.approve(spendPermission);
        vm.warp(spendPermission.start);
        vm.expectEmit(address(mockSpendPermissionManager));
        emit SpendPermissionManager.SpendPermissionUsed({
            hash: mockSpendPermissionManager.getHash(spendPermission),
            account: spendPermission.account,
            spender: spendPermission.spender,
            token: NATIVE_TOKEN,
            periodSpend: PeriodSpend({
                start: spendPermission.start,
                end: _safeAddUint48(spendPermission.start, spendPermission.period, spendPermission.end),
                spend: spend
            })
        });
        mockSpendPermissionManager.useSpendPermission(spendPermission, spend);
    }

    function test_useSpendPermission_success_setsState(
        address account,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint160 spend,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(spender != address(0));
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);
        vm.assume(spend > 0);
        vm.assume(spend < allowance);

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

        vm.prank(account);
        mockSpendPermissionManager.approve(spendPermission);
        vm.warp(start);
        mockSpendPermissionManager.useSpendPermission(spendPermission, spend);
        PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period, end));
        assertEq(usage.spend, spend);
    }

    function test_useSpendPermission_success_maxAllowance(
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
        vm.assume(start > 0);
        vm.assume(end > 0);
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

        vm.prank(account);
        mockSpendPermissionManager.approve(spendPermission);
        vm.warp(start);
        mockSpendPermissionManager.useSpendPermission(spendPermission, allowance); // spend full allowance
        PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period, end));
        assertEq(usage.spend, allowance);
    }

    function test_useSpendPermission_success_incrementalSpends(
        address account,
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData,
        uint8 numberOfSpends
    ) public {
        vm.assume(spender != address(0));
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(numberOfSpends > 1);
        vm.assume(allowance >= numberOfSpends);

        uint160 spend = allowance / numberOfSpends;

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

        vm.prank(account);
        mockSpendPermissionManager.approve(spendPermission);
        vm.warp(start);
        uint256 expectedTotalSpend = 0;
        for (uint256 i; i < numberOfSpends; i++) {
            mockSpendPermissionManager.useSpendPermission(spendPermission, spend);
            expectedTotalSpend += spend;
            PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
            assertEq(usage.start, start);
            assertEq(usage.end, _safeAddUint48(start, period, end));
            assertEq(usage.spend, expectedTotalSpend);
        }
    }
}
