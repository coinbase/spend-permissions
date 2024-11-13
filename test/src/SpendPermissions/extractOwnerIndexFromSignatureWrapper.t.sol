// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";

contract UseSpendPermissionTest is SpendPermissionManagerBase {
    function setUp() public {
        _initializeSpendPermissionManager();
    }

    function test_success_erc6492_signature(uint8 numberOwners, uint8 ownerIndex, uint128 ownerPk) public {
        vm.assume(numberOwners > 0);
        vm.assume(ownerIndex < numberOwners);
        vm.assume(ownerPk != 0);

        bytes[] memory owners = new bytes[](numberOwners);
        for (uint8 i = 0; i < numberOwners; i++) {
            address ownerAddress = vm.addr(vm.randomUint());
            owners[i] = abi.encode(ownerAddress);
        }
        SpendPermissionManager.SpendPermission memory spendPermission = _createSpendPermission();
        bytes memory signature = _signSpendPermission6492(spendPermission, ownerPk, ownerIndex, owners);
        uint256 ownerIndexFromSignature = mockSpendPermissionManager.extractOwnerIndexFromSignatureWrapper(signature);
        vm.assertEq(ownerIndexFromSignature, ownerIndex);
    }

    function test_success_erc1271_signature(uint256 ownerIndex, uint128 ownerPk) public {
        vm.assume(ownerPk != 0);

        SpendPermissionManager.SpendPermission memory spendPermission = _createSpendPermission();
        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, ownerIndex);
        uint256 ownerIndexFromSignature = mockSpendPermissionManager.extractOwnerIndexFromSignatureWrapper(signature);
        vm.assertEq(ownerIndexFromSignature, ownerIndex);
    }
}
