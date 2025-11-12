// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SpendPermissionManager} from "../SpendPermissionManager.sol";
import {ERC20TokenHook} from "../hooks/ERC20TokenHook.sol";
import {SpendPermissionManagerBaseHookTest} from "./SpendPermissionManagerBaseHookTest.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract TestERC20 is ERC20 {
    constructor() ERC20("Mock", "MCK") {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract ERC20TokenHook_HappyPath_Test is SpendPermissionManagerBaseHookTest {
    ERC20TokenHook erc20TokenHook;
    TestERC20 mockERC20;

    function setUp() public {
        _initializeSpendPermissionManager();
        erc20TokenHook = new ERC20TokenHook(address(mockSpendPermissionManager));
        mockERC20 = new TestERC20();

        vm.startPrank(owner);
        account.addOwnerAddress(address(mockSpendPermissionManager));
        vm.stopPrank();
    }

    function test_erc20TokenHook_spend_success(
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        uint160 spend
    ) public {
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);
        vm.assume(spend > 0);
        vm.assume(allowance >= spend);

        SpendPermissionManager.SpendPermission memory spendPermission = _createSpendPermission();
        spendPermission.token = address(mockERC20);
        spendPermission.start = start;
        spendPermission.end = end;
        spendPermission.period = period;
        spendPermission.allowance = allowance;
        spendPermission.salt = salt;
        spendPermission.hook = address(erc20TokenHook);

        // fund account with ERC20
        mockERC20.mint(address(account), allowance);
        assertEq(mockERC20.balanceOf(address(account)), allowance);

        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);

        vm.warp(start);

        vm.startPrank(spender);
        mockSpendPermissionManager.approveWithSignature(spendPermission, signature);
        mockSpendPermissionManager.spend(spendPermission, spend, hex"");
        vm.stopPrank();

        assertEq(mockERC20.balanceOf(address(account)), allowance - spend);
        assertEq(mockERC20.balanceOf(spender), spend);

        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period, end));
        assertEq(usage.spend, spend);
    }
}


