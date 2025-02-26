// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./Permit3Base.sol";
import {console2} from "forge-std/console2.sol";

contract Permit3E2ETest is Permit3Base {
    function setUp() public {
        _initializePermit3Base();

        // Add the permit3Utility as an owner of the smart wallet
        vm.prank(address(account));
        account.addOwnerAddress(address(permit3Utility));

        // Verify utility is properly registered as owner at index 1
        require(account.isOwnerAddress(address(permit3Utility)), "Utility not registered as owner");
        bytes memory ownerAtIndex1 = account.ownerAtIndex(1);
        require(address(uint160(uint256(bytes32(ownerAtIndex1)))) == address(permit3Utility), "Utility not at index 1");

        console2.log("Utility owner bytes at index 1:", address(uint160(uint256(bytes32(ownerAtIndex1)))));
        console2.log("Expected utility address:", address(permit3Utility));
    }

    /*
    Steps for a native token transfer with CBSW:
    - create a spend permission
    - sign the spend permission but include prepareData in a 6492 wrapper
    - The prepareData should include the calldata for the registerPermit3Utility function 
    - call approveWithSignature on Permit3 with the 6492 wrapped-signature
    - attempt to spend the native tokens by calling spend on Permit3 with the permission and amount
    - Spend will execute on the CBSW and will notice that the account has a registered utility, which means that
    before attempting to transfer the ETH to the spender, the CBSW will call the utility contract's spendNativeToken
    function
    - spend should succeed*/
    function test_permit3_e2e_nativeTokenTransfer() public {
        // Create a spend permission
        SpendPermission memory permission = _createSpendPermission();

        // Sign the spend permission with ERC6492 wrapper that includes utility registration
        bytes memory signature = _signSpendPermissionWithUtilityRegistration(
            permission,
            ownerPk,
            0, // owner index
            address(permit3Utility),
            1 // utility owner index (since we added it as the second owner in setUp)
        );

        // Approve the spend permission with the wrapped signature
        vm.prank(spender);
        permit3.approveWithSignature(permission, signature);

        // Verify utility registration
        address registeredUtility = permit3.accountToUtility(address(account));
        console2.log("Registered utility: ", registeredUtility);
        console2.log("Expected utility: ", address(permit3Utility));
        require(registeredUtility == address(permit3Utility), "Utility not registered");

        // Record balances before
        uint256 accountBalanceBefore = address(account).balance;
        uint256 spenderBalanceBefore = spender.balance;

        // Spend the native tokens
        vm.prank(spender);
        permit3.spend(permission, 0.5 ether);

        // Verify balances after
        assertEq(address(account).balance, accountBalanceBefore - 0.5 ether, "Account balance not decreased correctly");
        assertEq(spender.balance, spenderBalanceBefore + 0.5 ether, "Spender balance not increased correctly");
    }
}
