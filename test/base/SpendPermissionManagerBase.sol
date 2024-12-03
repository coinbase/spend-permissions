// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {MagicSpend} from "magic-spend/MagicSpend.sol";
import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";
import {CoinbaseSmartWalletFactory} from "smart-wallet/CoinbaseSmartWalletFactory.sol";

import {PublicERC6492Validator} from "../../src/PublicERC6492Validator.sol";
import {SpendPermissionManager} from "../../src/SpendPermissionManager.sol";

import {MockSpendPermissionManager} from "../mocks/MockSpendPermissionManager.sol";
import {Base} from "./Base.sol";

contract SpendPermissionManagerBase is Base {
    address constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    bytes32 constant EIP6492_MAGIC_VALUE = 0x6492649264926492649264926492649264926492649264926492649264926492;
    bytes32 constant CBSW_MESSAGE_TYPEHASH = keccak256("CoinbaseSmartWalletMessage(bytes32 hash)");
    uint256 constant NONCE_HASH_BITS = 96;

    PublicERC6492Validator publicERC6492Validator;
    MagicSpend magicSpend;
    MockSpendPermissionManager mockSpendPermissionManager;
    CoinbaseSmartWalletFactory mockCoinbaseSmartWalletFactory;

    function _initializeSpendPermissionManager() internal {
        _initialize(); // Base
        mockCoinbaseSmartWalletFactory = new CoinbaseSmartWalletFactory(address(account));
        publicERC6492Validator = new PublicERC6492Validator();
        magicSpend = new MagicSpend(owner, 1);
        mockSpendPermissionManager = new MockSpendPermissionManager(publicERC6492Validator, address(magicSpend));
    }

    /**
     * @dev Helper function to create a SpendPermissionManager.SpendPermission struct with happy path defaults
     */
    function _createSpendPermission() internal view returns (SpendPermissionManager.SpendPermission memory) {
        return SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: spender,
            token: NATIVE_TOKEN,
            start: uint48(vm.getBlockTimestamp()),
            end: type(uint48).max,
            period: 604800,
            allowance: 1 ether,
            salt: 0,
            extraData: "0x"
        });
    }

    function _signSpendPermission(
        SpendPermissionManager.SpendPermission memory spendPermission,
        uint256 ownerPk,
        uint256 ownerIndex
    ) internal view returns (bytes memory) {
        bytes32 spendPermissionHash = mockSpendPermissionManager.getHash(spendPermission);
        bytes32 replaySafeHash =
            CoinbaseSmartWallet(payable(spendPermission.account)).replaySafeHash(spendPermissionHash);
        bytes memory signature = _sign(ownerPk, replaySafeHash);
        bytes memory wrappedSignature = _applySignatureWrapper(ownerIndex, signature);
        return wrappedSignature;
    }

    function _signSpendPermissionBatch(
        SpendPermissionManager.SpendPermissionBatch memory spendPermissionBatch,
        uint256 ownerPk,
        uint256 ownerIndex
    ) internal view returns (bytes memory) {
        bytes32 spendPermissionBatchHash = mockSpendPermissionManager.getBatchHash(spendPermissionBatch);
        bytes32 replaySafeHash =
            CoinbaseSmartWallet(payable(spendPermissionBatch.account)).replaySafeHash(spendPermissionBatchHash);
        bytes memory signature = _sign(ownerPk, replaySafeHash);
        bytes memory wrappedSignature = _applySignatureWrapper(ownerIndex, signature);
        return wrappedSignature;
    }

    function _signSpendPermission6492(
        SpendPermissionManager.SpendPermission memory spendPermission,
        uint256 ownerPk,
        uint256 ownerIndex,
        bytes[] memory allInitialOwners
    ) internal view returns (bytes memory) {
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
        bytes memory signature = _sign(ownerPk, replaySafeHash);
        bytes memory wrappedSignature = _applySignatureWrapper(ownerIndex, signature);

        // wrap inner sig in 6492 format ======================
        address factory = address(mockCoinbaseSmartWalletFactory);
        bytes memory factoryCallData = abi.encodeWithSignature("createAccount(bytes[],uint256)", allInitialOwners, 0);
        bytes memory eip6492Signature = abi.encode(factory, factoryCallData, wrappedSignature);
        eip6492Signature = abi.encodePacked(eip6492Signature, EIP6492_MAGIC_VALUE);
        return eip6492Signature;
    }

    function _signSpendPermissionBatch6492(
        SpendPermissionManager.SpendPermissionBatch memory spendPermissionBatch,
        uint256 ownerPk,
        uint256 ownerIndex,
        bytes[] memory allInitialOwners
    ) internal view returns (bytes memory) {
        bytes32 spendPermissionBatchHash = mockSpendPermissionManager.getBatchHash(spendPermissionBatch);
        // construct replaySafeHash without relying on the account contract being deployed
        bytes32 cbswDomainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Coinbase Smart Wallet")),
                keccak256(bytes("1")),
                block.chainid,
                spendPermissionBatch.account
            )
        );
        bytes32 replaySafeHash = keccak256(
            abi.encodePacked(
                "\x19\x01", cbswDomainSeparator, keccak256(abi.encode(CBSW_MESSAGE_TYPEHASH, spendPermissionBatchHash))
            )
        );
        bytes memory signature = _sign(ownerPk, replaySafeHash);
        bytes memory wrappedSignature = _applySignatureWrapper(ownerIndex, signature);

        // wrap inner sig in 6492 format ======================
        address factory = address(mockCoinbaseSmartWalletFactory);
        bytes memory factoryCallData = abi.encodeWithSignature("createAccount(bytes[],uint256)", allInitialOwners, 0);
        bytes memory eip6492Signature = abi.encode(factory, factoryCallData, wrappedSignature);
        eip6492Signature = abi.encodePacked(eip6492Signature, EIP6492_MAGIC_VALUE);
        return eip6492Signature;
    }

    function _createWithdrawRequest(SpendPermissionManager.SpendPermission memory spendPermission, uint256 nonceEntropy)
        internal
        view
        returns (MagicSpend.WithdrawRequest memory withdrawRequest)
    {
        // Get the hash and extract the portion we want
        bytes32 permissionHash = mockSpendPermissionManager.getHash(spendPermission);
        uint256 hashPortion = uint256(permissionHash) >> (256 - NONCE_HASH_BITS);

        // Use remaining bits for actual entropy
        uint256 entropyPortion = nonceEntropy & ((1 << (256 - NONCE_HASH_BITS)) - 1);

        // Combine hash portion and entropy portion
        uint256 nonce = (hashPortion << (256 - NONCE_HASH_BITS)) | entropyPortion;

        return MagicSpend.WithdrawRequest({
            asset: address(0),
            amount: 0,
            nonce: nonce,
            expiry: type(uint48).max,
            signature: hex""
        });
    }

    function _signWithdrawRequest(address account, MagicSpend.WithdrawRequest memory withdrawRequest)
        internal
        view
        returns (bytes memory signature)
    {
        bytes32 hash = magicSpend.getHash(account, withdrawRequest);
        return _sign(ownerPk, hash);
    }

    function _safeAddUint48(uint48 a, uint48 b, uint48 end) internal pure returns (uint48 c) {
        bool overflow = uint256(a) + uint256(b) > end;
        return overflow ? end : a + b;
    }

    function _safeAddUint160(uint160 a, uint160 b) internal pure returns (uint160 c) {
        bool overflow = uint256(a) + uint256(b) > type(uint160).max;
        return overflow ? type(uint160).max : a + b;
    }
}
