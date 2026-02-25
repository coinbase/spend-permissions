// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";
import {SpendRouter} from "../../../src/SpendRouter.sol";
import {SpendRouterTestBase} from "./SpendRouterTestBase.sol";

contract MulticallTest is SpendRouterTestBase {
    function test_multicall_batchSpend() public {
        // 1. Create permissions
        // Permission A: Native Token
        uint160 allowanceA = 1 ether;
        SpendPermissionManager.SpendPermission memory permissionA = _createPermission(
            NATIVE_TOKEN, allowanceA, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 1
        );
        _approvePermission(permissionA);

        // Permission B: ERC20 Token
        uint160 allowanceB = 1000e18;
        SpendPermissionManager.SpendPermission memory permissionB = _createPermission(
            address(token), allowanceB, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 2
        );
        _approvePermission(permissionB);

        // Fund account
        vm.deal(address(account), allowanceA);
        token.mint(address(account), allowanceB);

        // 2. Prepare calldata for multicall
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(SpendRouter.spendAndRoute.selector, permissionA, 0.5 ether);
        data[1] = abi.encodeWithSelector(SpendRouter.spendAndRoute.selector, permissionB, 500e18);

        // 3. Execute multicall
        vm.prank(executor);
        router.multicall(data);

        // 4. Verify results
        assertEq(address(recipient).balance, 0.5 ether);
        assertEq(token.balanceOf(recipient), 500e18);
        assertEq(address(account).balance, allowanceA - 0.5 ether);
        assertEq(token.balanceOf(address(account)), allowanceB - 500e18);
    }
}
