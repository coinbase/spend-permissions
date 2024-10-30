// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";

contract GetCurrentPeriodTest is SpendPermissionManagerBase {
    function setUp() public {
        _initializeSpendPermissionManager();
    }

    function test_getCurrentPeriod_revert_beforeSpendPermissionStart(uint48 start) public {
        vm.assume(start > 0);

        SpendPermissionManager.SpendPermission memory spendPermission = _createSpendPermission();
        spendPermission.start = start;
        vm.warp(start - 1);
        vm.expectRevert(
            abi.encodeWithSelector(SpendPermissionManager.BeforeSpendPermissionStart.selector, start - 1, start)
        );
        mockSpendPermissionManager.getCurrentPeriod(spendPermission);
    }

    function test_getCurrentPeriod_revert_equalSpendPermissionEnd(uint48 end) public {
        vm.assume(end > 0);
        vm.assume(end < type(uint48).max);

        SpendPermissionManager.SpendPermission memory spendPermission = _createSpendPermission();
        spendPermission.end = end;
        vm.warp(end);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.AfterSpendPermissionEnd.selector, end, end));
        mockSpendPermissionManager.getCurrentPeriod(spendPermission);
    }

    function test_getCurrentPeriod_revert_afterSpendPermissionEnd(uint48 end) public {
        vm.assume(end > 0);
        vm.assume(end < type(uint48).max);

        SpendPermissionManager.SpendPermission memory spendPermission = _createSpendPermission();
        spendPermission.end = end;
        vm.warp(end + 1);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.AfterSpendPermissionEnd.selector, end + 1, end));
        mockSpendPermissionManager.getCurrentPeriod(spendPermission);
    }

    function test_getCurrentPeriod_success_unusedAllowance(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);

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
        vm.warp(start);
        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);

        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period, end));
        assertEq(usage.spend, 0);
    }

    function test_getCurrentPeriod_success_startOfPeriod(
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
        vm.assume(spend <= allowance);

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

        vm.prank(address(account));
        mockSpendPermissionManager.approve(spendPermission);

        vm.warp(start);
        mockSpendPermissionManager.useSpendPermission(spendPermission, spend);
        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period, end));
        assertEq(usage.spend, spend);
    }

    function test_getCurrentPeriod_success_endOfPeriod(
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
        vm.assume(period <= end - start);
        vm.assume(allowance > 0);
        vm.assume(spend > 0);
        vm.assume(spend <= allowance);

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

        vm.prank(address(account));
        mockSpendPermissionManager.approve(spendPermission);

        vm.warp(start);
        mockSpendPermissionManager.useSpendPermission(spendPermission, spend);

        vm.warp(_safeAddUint48(start, period, end) - 1);
        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period, end));
        assertEq(usage.spend, spend);
    }

    function test_getCurrentPeriod_succes_resetsAfterPeriod(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData,
        uint160 spend
    ) public {
        vm.assume(spender != address(0));
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(period < end - start);
        vm.assume(allowance > 0);
        vm.assume(spend > 0);
        vm.assume(spend <= allowance);

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

        vm.prank(address(account));
        mockSpendPermissionManager.approve(spendPermission);

        vm.warp(start);
        mockSpendPermissionManager.useSpendPermission(spendPermission, spend);

        vm.warp(_safeAddUint48(start, period, end));
        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, _safeAddUint48(start, period, end));
        assertEq(usage.end, _safeAddUint48(_safeAddUint48(start, period, end), period, end));
        assertEq(usage.spend, 0);
    }

    function test_getCurrentPeriod_success_periodEndWithinPermissionEnd(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        vm.assume(end > 0 && end < type(uint48).max);
        vm.assume(period > 0);
        vm.assume(start < end);
        vm.assume(uint256(start) + uint256(period) > end);
        vm.assume(allowance > 0);

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

        vm.warp(start);
        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, end);
        assertEq(usage.spend, 0);
    }

    function test_getCurrentPeriod_success_periodEndWithinPermissionEnd_maxValue(
        address spender,
        uint48 start,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        uint48 end = type(uint48).max;
        vm.assume(period > 0);
        vm.assume(start < end);
        vm.assume(uint256(start) + uint256(period) > end); // force overflow
        vm.assume(allowance > 0);

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

        vm.warp(start);
        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, end);
        assertEq(usage.spend, 0);
    }
}
