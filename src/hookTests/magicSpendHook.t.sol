// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SpendPermissionManager} from "../SpendPermissionManager.sol";
import {MagicSpendHook} from "../hooks/MagicSpendHook.sol";
import {SpendPermissionManagerBaseHookTest} from "./SpendPermissionManagerBaseHookTest.sol";
import {MagicSpend} from "magicspend/MagicSpend.sol";

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract TestERC20_MSH is ERC20 {
    constructor() ERC20("MSH", "MSH") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MagicSpendHook_HappyPath_Test is SpendPermissionManagerBaseHookTest {
    MagicSpendHook magicSpendHook;
    TestERC20_MSH erc20;

    function setUp() public {
        _initializeSpendPermissionManager();
        magicSpendHook = new MagicSpendHook(address(mockSpendPermissionManager), address(magicSpend));
        erc20 = new TestERC20_MSH();

        vm.startPrank(owner);
        account.addOwnerAddress(address(mockSpendPermissionManager));
        vm.stopPrank();
    }

    function test_magicSpendHook_spend_success(
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        uint160 spend,
        uint128 nonceEntropy
    ) public {
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);
        vm.assume(spend > 0);
        vm.assume(allowance >= spend);

        SpendPermissionManager.SpendPermission memory spendPermission = _createSpendPermission();
        // native token pathway for MagicSpend
        spendPermission.token = NATIVE_TOKEN;
        spendPermission.start = start;
        spendPermission.end = end;
        spendPermission.period = period;
        spendPermission.allowance = allowance;
        spendPermission.salt = salt;
        spendPermission.hook = address(magicSpendHook);

        // craft withdraw request with matching nonce postfix and amount
        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(spendPermission, nonceEntropy);
        withdrawRequest.amount = spend;
        // sign withdraw request as the MagicSpend owner
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        // fund MagicSpend so it can withdraw to the account during hook execution
        vm.deal(address(magicSpend), spend);

        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);

        vm.warp(start);

        vm.startPrank(spender);
        mockSpendPermissionManager.approveWithSignature(spendPermission, signature);
        mockSpendPermissionManager.spend(spendPermission, spend, abi.encode(withdrawRequest));
        vm.stopPrank();

        assertEq(address(magicSpend).balance, 0);
        assertEq(spender.balance, spend);

        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period, end));
        assertEq(usage.spend, spend);
    }

    function test_magicSpendHook_erc20_spend_success(
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        uint160 spend,
        uint128 nonceEntropy
    ) public {
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);
        vm.assume(spend > 0);
        vm.assume(allowance >= spend);

        SpendPermissionManager.SpendPermission memory spendPermission = _createSpendPermission();
        // ERC20 pathway for MagicSpend
        spendPermission.token = address(erc20);
        spendPermission.start = start;
        spendPermission.end = end;
        spendPermission.period = period;
        spendPermission.allowance = allowance;
        spendPermission.salt = salt;
        spendPermission.hook = address(magicSpendHook);

        // craft withdraw request with matching nonce postfix and amount
        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(spendPermission, nonceEntropy);
        withdrawRequest.asset = address(erc20);
        withdrawRequest.amount = spend;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        // fund MagicSpend with ERC20 so it can withdraw to account during hook execution
        erc20.mint(address(magicSpend), spend);
        assertEq(erc20.balanceOf(address(magicSpend)), spend);

        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);

        vm.warp(start);

        vm.startPrank(spender);
        mockSpendPermissionManager.approveWithSignature(spendPermission, signature);
        mockSpendPermissionManager.spend(spendPermission, spend, abi.encode(withdrawRequest));
        vm.stopPrank();

        // magic spend funds moved to spender via account->permit3 transferFrom
        assertEq(erc20.balanceOf(address(magicSpend)), 0);
        assertEq(erc20.balanceOf(spender), spend);

        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period, end));
        assertEq(usage.spend, spend);
    }
}

