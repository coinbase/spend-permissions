// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";

contract DebugTest is Test, SpendPermissionManagerBase {
    SpendPermissionManager spendPermissionManager;

    function setUp() public {
        _initialize();

        spendPermissionManager = new SpendPermissionManager(mockCoinbaseSmartWalletFactory);

        vm.prank(owner);
        account.addOwnerAddress(address(spendPermissionManager));
    }

    function test_approve() public {
        SpendPermissionManager.SpendPermission memory spendPermission = _createSpendPermissionDebug();

        vm.prank(address(account));
        spendPermissionManager.approve(spendPermission);
    }

    function test_withdraw(address recipient) public {
        assumePayable(recipient);
        SpendPermissionManager.SpendPermission memory spendPermission = _createSpendPermissionDebug();

        vm.prank(address(account));
        spendPermissionManager.approve(spendPermission);

        vm.deal(address(account), 1 ether);
        vm.prank(owner);
        spendPermissionManager.spend(spendPermission, recipient, 1 ether / 2);
    }

    function _createSpendPermissionDebug() internal view returns (SpendPermissionManager.SpendPermission memory) {
        return SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: owner,
            token: NATIVE_TOKEN,
            start: 0,
            end: 1758791693, // 1 year from now
            period: 86400, // 1 day
            allowance: 1 ether
        });
    }
}
