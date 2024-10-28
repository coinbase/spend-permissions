// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

import {Base} from "../../base/Base.sol";

contract DebugTest is Test, Base {
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    SpendPermissionManager spendPermissionManager;

    function setUp() public {
        _initialize();

        spendPermissionManager = new SpendPermissionManager();

        vm.prank(owner);
        account.addOwnerAddress(address(spendPermissionManager));
    }

    function test_approve() public {
        SpendPermissionManager.SpendPermission memory spendPermission = _createSpendPermission();

        vm.prank(address(account));
        spendPermissionManager.approve(spendPermission);
    }

    function test_withdraw(address recipient) public {
        assumePayable(recipient);
        SpendPermissionManager.SpendPermission memory spendPermission = _createSpendPermission();

        vm.prank(address(account));
        spendPermissionManager.approve(spendPermission);

        vm.deal(address(account), 1 ether);
        vm.prank(owner);
        spendPermissionManager.spend(spendPermission, 1 ether / 2);
    }

    function _createSpendPermission() internal view returns (SpendPermissionManager.SpendPermission memory) {
        return SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: owner,
            token: NATIVE_TOKEN,
            start: 0,
            end: 1758791693, // 1 year from now
            period: 86400, // 1 day
            allowance: 1 ether,
            salt: 0,
            extraData: "0x"
        });
    }
}
