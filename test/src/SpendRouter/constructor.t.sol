// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SpendPermissionManager} from "src/SpendPermissionManager.sol";
import {SpendRouter} from "src/SpendRouter.sol";
import {SpendRouterTestBase} from "test/src/SpendRouter/SpendRouterTestBase.sol";

contract ConstructorTest is SpendRouterTestBase {
    /// @notice PERMISSION_MANAGER is set to the SpendPermissionManager passed to the constructor.
    function test_setsPermissionManager() public view {
        assertEq(address(router.PERMISSION_MANAGER()), address(permissionManager));
    }

    /// @notice NATIVE_TOKEN_ADDRESS equals the ERC-7528 sentinel address.
    function test_setsNativeTokenAddress() public view {
        assertEq(router.NATIVE_TOKEN_ADDRESS(), NATIVE_TOKEN);
    }

    /// @notice Reverts with NotPersistentCode when the SpendPermissionManager address has no deployed code.
    function test_revert_noCode() public {
        address noCode = makeAddr("noCode");
        vm.expectRevert(abi.encodeWithSelector(SpendRouter.NotPersistentCode.selector, noCode));
        new SpendRouter(SpendPermissionManager(payable(noCode)));
    }

    /// @notice Reverts with NotPersistentCode when the SpendPermissionManager address has an EIP-7702 delegation
    ///         indicator (exactly 23 bytes starting with 0xef0100).
    function test_revert_eip7702DelegationIndicator() public {
        address delegated = makeAddr("delegated");

        // EIP-7702 delegation indicator: 0xef0100 followed by a 20-byte address
        bytes memory delegationCode = abi.encodePacked(hex"ef0100", address(0xdead));
        vm.etch(delegated, delegationCode);

        vm.expectRevert(abi.encodeWithSelector(SpendRouter.NotPersistentCode.selector, delegated));
        new SpendRouter(SpendPermissionManager(payable(delegated)));
    }

    /// @notice Does not revert when the SpendPermissionManager address has normal deployed code.
    function test_succeeds_withDeployedContract() public {
        // The base setUp already deployed permissionManager and router successfully;
        // verify a fresh deployment also works.
        SpendRouter freshRouter = new SpendRouter(permissionManager);
        assertEq(address(freshRouter.PERMISSION_MANAGER()), address(permissionManager));
    }
}

contract ReceiveTest is SpendRouterTestBase {
    /// @notice Router accepts native ETH from SpendPermissionManager.
    /// @param amount Fuzzed ETH amount to send (excluded: 0).
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
    /// @param sender Fuzzed sender address (excluded: permissionManager).
    /// @param amount Fuzzed ETH amount to send (excluded: 0).
    function test_rejectsETH_fromNonPermissionManager(address sender, uint96 amount) public {
        vm.assume(sender != address(permissionManager));
        vm.assume(amount > 0);
        vm.deal(sender, amount);

        vm.prank(sender);
        (bool success,) = address(router).call{value: amount}("");
        assertFalse(success);
    }
}
