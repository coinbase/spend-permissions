// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SpendPermissionManager} from "src/SpendPermissionManager.sol";
import {SpendRouter} from "src/SpendRouter.sol";
import {SpendRouterTestBase} from "test/src/SpendRouter/SpendRouterTestBase.sol";

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

    // --- Edge-case tests ---

    function test_multicall_batchSpendWithSignature() public {
        // 1. Create permissions and sign them
        // Permission A: Native Token
        SpendPermissionManager.SpendPermission memory permissionA = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 1
        );
        bytes memory sigA = _signPermission(permissionA);

        // Permission B: ERC20 Token
        SpendPermissionManager.SpendPermission memory permissionB = _createPermission(
            address(token), 1000e18, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 2
        );
        bytes memory sigB = _signPermission(permissionB);

        // 2. Fund account
        vm.deal(address(account), 1 ether);
        token.mint(address(account), 1000e18);

        // 3. Prepare calldata for multicall
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(
            SpendRouter.spendAndRouteWithSignature.selector, permissionA, uint160(0.5 ether), sigA
        );
        data[1] =
            abi.encodeWithSelector(SpendRouter.spendAndRouteWithSignature.selector, permissionB, uint160(500e18), sigB);

        // 4. Execute multicall
        vm.prank(executor);
        router.multicall(data);

        // 5. Verify results
        assertEq(address(recipient).balance, 0.5 ether);
        assertEq(token.balanceOf(recipient), 500e18);
    }

    function test_multicall_partialRevert_revertsAll() public {
        // 1. Create permissions
        // Permission A: approved
        SpendPermissionManager.SpendPermission memory permissionA = _createPermission(
            NATIVE_TOKEN, 1 ether, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 1
        );
        _approvePermission(permissionA);

        // Permission B: intentionally NOT approved
        SpendPermissionManager.SpendPermission memory permissionB = _createPermission(
            address(token), 1000e18, 1 days, uint48(block.timestamp), uint48(block.timestamp + 1 days), 2
        );

        // 2. Fund account
        vm.deal(address(account), 1 ether);

        // 3. Prepare calldata for multicall
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(SpendRouter.spendAndRoute.selector, permissionA, 0.5 ether);
        data[1] = abi.encodeWithSelector(SpendRouter.spendAndRoute.selector, permissionB, 500e18);

        // 4. Execute multicall — entire batch reverts atomically
        vm.prank(executor);
        vm.expectRevert();
        router.multicall(data);

        // 5. Verify no state changes from permissionA either
        assertEq(address(recipient).balance, 0);
    }
}
