// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PublicERC6492Validator} from "../../../src/PublicERC6492Validator.sol";
import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";

import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";
import {CoinbaseSmartWalletFactory} from "smart-wallet/CoinbaseSmartWalletFactory.sol";

contract IsValidSignatureNowTest is SpendPermissionManagerBase {
    PublicERC6492Validator public validator;

    function setUp() public {
        _initialize(); // Sets up account, owner, etc
        mockCoinbaseSmartWalletFactory = new CoinbaseSmartWalletFactory(address(account));
        validator = new PublicERC6492Validator();
    }

    function test_isValidSignatureNow_success_preDeployedWallet() public {
        // Create test message and signature
        bytes32 hash = keccak256("test message");
        bytes32 replaySafeHash = account.replaySafeHash(hash);
        bytes memory signature = _sign(ownerPk, replaySafeHash);
        bytes memory wrappedSignature = _applySignatureWrapper(0, signature);

        bool isValid = validator.isValidSignatureNow(address(account), hash, wrappedSignature);
        assertTrue(isValid);
    }

    // Bug in solady code!
    // function test_isValidSignatureNow_success_counterfactualWallet() public {
    //     // Create a new owner for the counterfactual wallet
    //     uint256 newOwnerPk = uint256(keccak256("different owner"));
    //     address newOwner = vm.addr(newOwnerPk);

    //     // Setup counterfactual wallet data with new owner
    //     bytes[] memory owners = new bytes[](1);
    //     owners[0] = abi.encode(newOwner);
    //     address counterfactualWallet = mockCoinbaseSmartWalletFactory.getAddress(owners, 0);

    //     // Create test message and signature
    //     bytes32 hash = keccak256("test message");

    //     // Construct replaySafeHash manually for counterfactual wallet
    //     bytes32 domainSeparator = keccak256(
    //         abi.encode(
    //             keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
    //             keccak256(bytes("Coinbase Smart Wallet")),
    //             keccak256(bytes("1")),
    //             block.chainid,
    //             counterfactualWallet
    //         )
    //     );
    //     bytes32 replaySafeHash =
    //         keccak256(abi.encodePacked("\x19\x01", domainSeparator, keccak256(abi.encode(CBSW_MESSAGE_TYPEHASH,
    // hash))));

    //     // Sign with the new owner's key
    //     bytes memory signature = _sign(newOwnerPk, replaySafeHash);
    //     bytes memory wrappedSignature = _applySignatureWrapper(0, signature);

    //     // Wrap in ERC-6492 format
    //     bytes memory eip6492Signature = _wrap6492Signature(wrappedSignature, owners);
    //     bool isValid = validator.isValidSignatureNow(counterfactualWallet, hash, eip6492Signature); // DOES NOT WORK
    // (indicates bug in solady code)
    //     bool isValid = validator.isValidSignatureNowAllowSideEffects(counterfactualWallet, hash, eip6492Signature);
    // // WORKS as long as it can deploy the wallet
    //     assertTrue(isValid);
    //     // assertEq(counterfactualWallet.code.length, 0); // Wallet should still be counterfactual
    // }

    function test_isValidSignatureNow_revert_invalidSignature(uint256 invalidPk) public {
        vm.assume(invalidPk != ownerPk);
        // Ensure private key is valid for secp256k1
        vm.assume(
            invalidPk > 0 && invalidPk < 115792089237316195423570985008687907852837564279074904382605163141518161494337
        );

        // Create invalid signature
        bytes32 hash = keccak256("test message");
        bytes memory signature = _sign(invalidPk, hash);
        bytes memory wrappedSignature = _applySignatureWrapper(0, signature);

        bool isValid = validator.isValidSignatureNow(address(account), hash, wrappedSignature);
        assertFalse(isValid);
    }

    function test_isValidSignatureNow_revert_invalidERC6492Signature(uint256 invalidPk) public {
        vm.assume(invalidPk != ownerPk);
        // Ensure private key is valid for secp256k1
        vm.assume(
            invalidPk > 0 && invalidPk < 115792089237316195423570985008687907852837564279074904382605163141518161494337
        );

        // Create a new owner for the counterfactual wallet
        uint256 newOwnerPk = uint256(keccak256("different owner"));
        address newOwner = vm.addr(newOwnerPk);

        // Setup counterfactual wallet data with new owner
        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(newOwner);
        address counterfactualWallet = mockCoinbaseSmartWalletFactory.getAddress(owners, 0);

        // Create test message and signature
        bytes32 hash = keccak256("test message");

        // Construct replaySafeHash manually for counterfactual wallet
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Coinbase Smart Wallet")),
                keccak256(bytes("1")),
                block.chainid,
                counterfactualWallet
            )
        );
        bytes32 replaySafeHash =
            keccak256(abi.encodePacked("\x19\x01", domainSeparator, keccak256(abi.encode(CBSW_MESSAGE_TYPEHASH, hash))));

        // Sign with the invalid key
        bytes memory signature = _sign(invalidPk, replaySafeHash);
        bytes memory wrappedSignature = _applySignatureWrapper(0, signature);

        // Wrap in ERC-6492 format
        bytes memory eip6492Signature = _wrap6492Signature(wrappedSignature, owners);

        bool isValid = validator.isValidSignatureNow(counterfactualWallet, hash, eip6492Signature);
        assertFalse(isValid);
    }

    function _wrap6492Signature(bytes memory signature, bytes[] memory owners) internal view returns (bytes memory) {
        bytes memory factoryCallData = abi.encodeWithSignature("createAccount(bytes[],uint256)", owners, 0);
        bytes memory eip6492Signature = abi.encode(mockCoinbaseSmartWalletFactory, factoryCallData, signature);
        return abi.encodePacked(eip6492Signature, EIP6492_MAGIC_VALUE);
    }
}
