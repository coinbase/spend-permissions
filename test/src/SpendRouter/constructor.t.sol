// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";
import {SpendRouter} from "../../../src/SpendRouter.sol";
import {SpendRouterTestBase} from "./SpendRouterTestBase.sol";

contract ConstructorTest is SpendRouterTestBase {
    /// @notice PERMISSION_MANAGER is set to the SpendPermissionManager passed to the constructor.
    function test_setsPermissionManager() public view {
        assertEq(address(router.PERMISSION_MANAGER()), address(permissionManager));
    }

    /// @notice NATIVE_TOKEN_ADDRESS equals the ERC-7528 sentinel address.
    function test_setsNativeTokenAddress() public view {
        assertEq(router.NATIVE_TOKEN_ADDRESS(), NATIVE_TOKEN);
    }
}

contract ReceiveTest is SpendRouterTestBase {
    /// @notice Router accepts native ETH from SpendPermissionManager.
    function test_acceptsETH_fromPermissionManager(uint96 amount) public {
        vm.assume(amount > 0);
        vm.deal(address(permissionManager), amount);

        uint256 preBalance = address(router).balance;
        vm.prank(address(permissionManager));
        (bool success,) = address(router).call{value: amount}("");
        assertTrue(success);
        assertEq(address(router).balance, preBalance + amount);
    }

    /// @notice Router rejects native ETH from arbitrary senders.
    function test_rejectsETH_fromNonPermissionManager(address sender, uint96 amount) public {
        vm.assume(sender != address(permissionManager));
        vm.assume(amount > 0);
        vm.deal(sender, amount);

        vm.prank(sender);
        (bool success,) = address(router).call{value: amount}("");
        assertFalse(success);
    }
}
