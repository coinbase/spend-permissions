// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";
import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";

import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";

contract DrainWalletTest is SpendPermissionManagerBase {
    function setUp() public {
        _initializeSpendPermissionManager();
        vm.prank(owner);
        account.addOwnerAddress(address(mockSpendPermissionManager));
    }

    function test_exploitSpendWithSignature_erc6492(
        address spender,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance
    ) public {
        vm.assume(spender != address(0));
        vm.assume(token != address(0));
        vm.assume(spender != address(account));
        assumePayable(spender);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);
        vm.assume(allowance <= type(uint160).max / 2);

        assertTrue(account.isOwnerAddress(address(owner)));
        assertTrue(account.isOwnerAddress(address(mockSpendPermissionManager)));

        vm.deal(address(account), allowance * 2);
        vm.deal(spender, 0);
        assertEq(address(account).balance, allowance * 2, "account balance should be allowance * 2 before exploit");
        assertEq(spender.balance, 0, "spender balance should be 0 before exploit");

        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: spender,
            token: token,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: 0,
            extraData: "0x"
        });

        bytes memory wrappedSignature = _signSpendPermission(spendPermission, ownerPk, 0);
        // in the normal course of events this wrapped approval signature will be delivered to the app/spender
        CoinbaseSmartWallet.SignatureWrapper memory wrapper =
            abi.decode(wrappedSignature, (CoinbaseSmartWallet.SignatureWrapper));
        // the spender unwraps the signature and changes the owner index to the next owner index
        wrapper.ownerIndex = account.nextOwnerIndex();
        wrappedSignature = _applySignatureWrapper(wrapper.ownerIndex, wrapper.signatureData);
        // this will cause the signature to fail sending the transaction down the ERC-6492 path
        address prepareTo = address(account);
        // bytes memory prepareData = abi.encodeWithSignature("removeAddOwner(uint256,bytes)", 0, abi.encode(owner));
        CoinbaseSmartWallet.Call[] memory calls = new CoinbaseSmartWallet.Call[](3);
        calls[0].target = address(spender);
        calls[0].value = address(account).balance;
        calls[0].data = hex"";
        calls[1].target = address(account);
        calls[1].value = 0;
        calls[1].data = abi.encodeWithSignature("removeOwnerAtIndex(uint256,bytes)", 0, abi.encode(owner));
        calls[2].target = address(account);
        calls[2].value = 0;
        calls[2].data = abi.encodeWithSignature("addOwnerAddress(address)", address(owner));
        bytes memory prepareData = abi.encodeWithSignature("executeBatch((address,uint256,bytes)[])", calls);

        bytes memory eip6492Signature = abi.encode(prepareTo, prepareData, wrappedSignature);
        eip6492Signature = abi.encodePacked(eip6492Signature, EIP6492_MAGIC_VALUE);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.InvalidSignature.selector));
        mockSpendPermissionManager.approveWithSignature(spendPermission, eip6492Signature);
    }

    function test_exploitSpendWithSignature_erc6492_factory() public {
        // From the test setup, we have:
        // - an owner
        // - a Smart Wallet that the owner owns
        // - A SpendPermissionManager that the owner has added as an owner to their Smart Wallet

        // This address will be used to sign the approval and will be the owner of the counterfactual account
        // Since the CoinbaseSmartWalletFactory uses this for CREATE2, the counterfactual account will be deterministic
        // The attacker would have to use a new signer for each exploit in this case.
        uint256 attackerSignerPk = uint256(64926492);
        address attackerAddress = vm.addr(attackerSignerPk);

        // Address attacker will use to submit the exploit and receive the funds
        address attacker = vm.addr(6492);
        assumePayable(attacker);

        uint160 allowance = 1 ether;
        // Ensure there are no address collisions
        require(attacker != address(account));
        require(attacker != owner);
        require(attackerAddress != address(account));
        require(attackerAddress != address(owner));
        assertTrue(account.isOwnerAddress(address(owner)));
        assertTrue(account.isOwnerAddress(address(mockSpendPermissionManager)));

        // Give some funds to the victim and make sure the attacker has none
        vm.deal(address(account), allowance * 2);
        vm.deal(attacker, 0);

        // Get the address of the counterfactual account that will be deployed
        bytes[] memory attackerOwners = new bytes[](1);
        attackerOwners[0] = abi.encode(attackerAddress);
        address counterfactualAccount = mockCoinbaseSmartWalletFactory.getAddress(attackerOwners, 0);
        assertTrue(counterfactualAccount != address(account), "counterfactual account is not the victims wallet");

        // check that the counterfactual account is not deployed (no code) and is empty
        {
            // stack too deep
            uint256 codeSize;
            assembly {
                codeSize := extcodesize(counterfactualAccount)
            }
            assertEq(codeSize, 0, "counterfactual account should not be deployed yet");
            assertEq(counterfactualAccount.balance, 0, "counterfactual account should have 0 balance");
        }

        // Setup a permission for the counterfactual account
        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: counterfactualAccount,
            spender: attacker,
            token: NATIVE_TOKEN,
            start: uint48(block.timestamp),
            end: uint48(block.timestamp + 1 days),
            period: 604800,
            allowance: allowance,
            salt: 0,
            extraData: "0x"
        });
        bytes memory wrappedSignature;
        {
            // stack too deep
            bytes32 spendPermissionHash = mockSpendPermissionManager.getHash(spendPermission);
            // construct replaySafeHash without relying on the account contract being deployed
            bytes32 cbswDomainSeparator = keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes("Coinbase Smart Wallet")),
                    keccak256(bytes("1")),
                    block.chainid,
                    spendPermission.account
                )
            );
            bytes32 replaySafeHash = keccak256(
                abi.encodePacked(
                    "\x19\x01", cbswDomainSeparator, keccak256(abi.encode(CBSW_MESSAGE_TYPEHASH, spendPermissionHash))
                )
            );
            bytes memory signature = _sign(attackerSignerPk, replaySafeHash);
            wrappedSignature = _applySignatureWrapper(0, signature);
        }

        // set the victims account as the prepareTo
        address prepareTo = address(account);
        // This will first drain the victims account and then deploy the counterfactual account so the signature passes
        CoinbaseSmartWallet.Call[] memory calls = new CoinbaseSmartWallet.Call[](2);
        {
            calls[0].target = address(attacker);
            calls[0].value = address(account).balance;
            calls[0].data = hex"";
        }
        {
            calls[1].target = address(mockCoinbaseSmartWalletFactory);
            calls[1].value = 0;
            calls[1].data = abi.encodeWithSignature("createAccount(bytes[],uint256)", attackerOwners, 0);
        }
        bytes memory prepareData = abi.encodeWithSignature("executeBatch((address,uint256,bytes)[])", calls);
        // Construct the EIP-6492 signature
        bytes memory eip6492Signature = abi.encode(prepareTo, prepareData, wrappedSignature);
        eip6492Signature = abi.encodePacked(eip6492Signature, EIP6492_MAGIC_VALUE);

        vm.startPrank(attacker);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.InvalidSignature.selector));
        mockSpendPermissionManager.approveWithSignature(spendPermission, eip6492Signature);
        vm.stopPrank();
    }
}
