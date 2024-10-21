// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";
import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";

contract ValidateSignatureTest is SpendPermissionManagerBase {
    function setUp() public {
        _initializeSpendPermissionManager();
        vm.prank(owner);
        account.addOwnerAddress(address(mockSpendPermissionManager));
    }

    function test_validateSignature_revert_invalidSignature_ERC1271(
        uint128 invalidPk,
        address spender,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance
    ) public {
        vm.assume(invalidPk != 0);

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: spender,
            token: token,
            start: start,
            end: end,
            period: period,
            allowance: allowance
        });

        bytes memory invalidSignature = _signSpendPermission(spendPermission, invalidPk, 0);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.InvalidSignature.selector));
        mockSpendPermissionManager.validateSignature(spendPermission, invalidSignature);
    }

    function test_validateSignature_revert_invalidFactory(
        uint128 invalidPk,
        address invalidFactory,
        address spender,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance
    ) public {
        vm.assume(invalidPk != 0);
        vm.assume(invalidFactory != address(mockCoinbaseSmartWalletFactory));

        address ownerAddress = vm.addr(ownerPk);
        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(ownerAddress);

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: spender,
            token: token,
            start: start,
            end: end,
            period: period,
            allowance: allowance
        });

        bytes memory signature = _signSpendPermission6492(spendPermission, invalidFactory, ownerPk, 0, owners);
        vm.expectRevert(
            abi.encodeWithSelector(
                SpendPermissionManager.InvalidFactory.selector, invalidFactory, address(mockCoinbaseSmartWalletFactory)
            )
        );
        mockSpendPermissionManager.validateSignature(spendPermission, signature);
    }

    function test_validateSignature_revert_deploymentFailedWithWrongDeployedAddress(
        uint128 undeployedOwnerPk,
        address arbitrarySecondOwner,
        address spender,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance
    ) public {
        vm.assume(undeployedOwnerPk != 0);
        vm.assume(undeployedOwnerPk != ownerPk);
        vm.assume(arbitrarySecondOwner != address(0));

        address undeployedOwnerAddress = vm.addr(undeployedOwnerPk);
        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(undeployedOwnerAddress);
        address counterfactualAccount = mockCoinbaseSmartWalletFactory.getAddress(owners, 0);

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: counterfactualAccount,
            spender: spender,
            token: token,
            start: start,
            end: end,
            period: period,
            allowance: allowance
        });

        bytes[] memory tooManyOwners = new bytes[](2);
        tooManyOwners[0] = abi.encode(undeployedOwnerAddress);
        tooManyOwners[1] = abi.encode(arbitrarySecondOwner);

        // creating an ERC6492 signature with init data that will lead to a different account address
        bytes memory signature = _signSpendPermission6492(
            spendPermission, address(mockCoinbaseSmartWalletFactory), ownerPk, 0, tooManyOwners
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                SpendPermissionManager.ERC6492DeployFailed.selector, "Deployed account does not match expected account"
            )
        );
        mockSpendPermissionManager.validateSignature(spendPermission, signature);
    }

    function test_validateSignature_success_erc6492SignaturePreDeploy(
        uint128 ownerPk,
        address spender,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance
    ) public {
        vm.assume(start > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);
        vm.assume(ownerPk != 0);
        // generate the counterfactual address for the account
        address ownerAddress = vm.addr(ownerPk);
        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(ownerAddress);
        address counterfactualAccount = mockCoinbaseSmartWalletFactory.getAddress(owners, 0);

        // create a 6492-compliant signature for the spend permission
        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: counterfactualAccount,
            spender: spender,
            token: token,
            start: start,
            end: end,
            period: period,
            allowance: allowance
        });
        bytes memory signature = _signSpendPermission6492(spendPermission, ownerPk, 0, owners);
        // verify that the account is not yet deployed
        vm.assertEq(counterfactualAccount.code.length, 0);

        // submit the spend permission with the signature, see permit succeed
        mockSpendPermissionManager.validateSignature(spendPermission, signature);

        // verify that the account is now deployed (has code) and that a call to isValidSignature returns true
        vm.assertGt(counterfactualAccount.code.length, 0);
    }

    function test_approveWithSignature_success_erc6492SignatureAlreadyDeployed(
        uint128 ownerPk,
        address spender,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance
    ) public {
        vm.assume(start > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);
        vm.assume(ownerPk != 0);
        // generate the counterfactual address for the account
        address ownerAddress = vm.addr(ownerPk);
        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(ownerAddress);
        address counterfactualAccount = mockCoinbaseSmartWalletFactory.getAddress(owners, 0);
        // deploy the account already
        mockCoinbaseSmartWalletFactory.createAccount(owners, 0);
        // create a 6492-compliant signature for the spend permission
        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: counterfactualAccount,
            spender: spender,
            token: token,
            start: start,
            end: end,
            period: period,
            allowance: allowance
        });
        bytes memory signature = _signSpendPermission6492(spendPermission, ownerPk, 0, owners);
        // verify that the account is already deployed
        vm.assertGt(counterfactualAccount.code.length, 0);
        mockSpendPermissionManager.validateSignature(spendPermission, signature);
    }
}
