// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";
import {CoinbaseSmartWalletFactory} from "smart-wallet/CoinbaseSmartWalletFactory.sol";

import {CoinbaseSmartWalletPermit3Utility} from "../../../src/CoinbaseSmartWalletPermit3Utility.sol";
import {Permit3} from "../../../src/Permit3.sol";
import {PublicERC6492Validator} from "../../../src/PublicERC6492Validator.sol";
import "../../../src/SpendPermission.sol";

import {Base} from "../../base/Base.sol";

contract Permit3Base is Base {
    // Constants
    address constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    bytes32 constant EIP6492_MAGIC_VALUE = 0x6492649264926492649264926492649264926492649264926492649264926492;
    bytes32 constant CBSW_MESSAGE_TYPEHASH = keccak256("CoinbaseSmartWalletMessage(bytes32 hash)");

    // Contract instances
    PublicERC6492Validator public publicERC6492Validator;
    Permit3 public permit3;
    CoinbaseSmartWalletPermit3Utility public permit3Utility;
    CoinbaseSmartWalletFactory public mockCoinbaseSmartWalletFactory;

    function _initializePermit3Base() internal {
        _initialize(); // Initialize from Base

        // Deploy core contracts
        publicERC6492Validator = new PublicERC6492Validator();
        permit3 = new Permit3(publicERC6492Validator);
        permit3Utility = new CoinbaseSmartWalletPermit3Utility(permit3);
        mockCoinbaseSmartWalletFactory = new CoinbaseSmartWalletFactory(address(account));

        // Fund the test account with some ETH
        vm.deal(address(account), 100 ether);
    }

    /// @notice Helper to create a SpendPermission with default values
    function _createSpendPermission() internal view returns (SpendPermission memory) {
        return SpendPermission({
            account: address(account),
            spender: spender,
            token: NATIVE_TOKEN,
            allowance: 1 ether,
            period: 604800, // 1 week
            start: uint48(block.timestamp),
            end: type(uint48).max,
            salt: 0,
            extraData: ""
        });
    }

    /// @notice Helper to sign a spend permission with ERC6492 wrapper for utility registration
    /// @param spendPermission The spend permission to sign
    /// @param ownerPk Private key of the signer
    /// @param ownerIndex Index of the signer in the wallet's owner list
    /// @param utility Address of the utility contract to register
    /// @param utilityOwnerIndex Index of the utility contract in the wallet's owner list
    function _signSpendPermissionWithUtilityRegistration(
        SpendPermission memory spendPermission,
        uint256 ownerPk,
        uint256 ownerIndex,
        address utility,
        uint256 utilityOwnerIndex
    ) internal view returns (bytes memory) {
        bytes32 spendPermissionHash = permit3.getHash(spendPermission);

        // Construct replaySafeHash without relying on the account contract being deployed
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
        bytes memory signature = _sign(ownerPk, replaySafeHash);
        bytes memory wrappedSignature = _applySignatureWrapper(ownerIndex, signature);

        // Add utility owner index to the front of the wrapped signature
        wrappedSignature = abi.encode(CoinbaseSmartWallet.SignatureWrapper(utilityOwnerIndex, wrappedSignature));

        // Create the prepare data for registering the utility
        bytes memory registerCalldata =
            abi.encodeWithSelector(CoinbaseSmartWalletPermit3Utility.registerPermit3Utility.selector);

        // Wrap inner sig in 6492 format with utility registration as prepare data
        bytes memory eip6492Signature = abi.encode(
            utility, // factory (the utility contract that will execute prepare data)
            registerCalldata, // prepare data (utility registration)
            wrappedSignature
        );
        eip6492Signature = abi.encodePacked(eip6492Signature, EIP6492_MAGIC_VALUE);
        return eip6492Signature;
    }
}
