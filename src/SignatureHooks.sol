// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AbstractSignatureHooks} from "./AbstractSignatureHooks.sol";
import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";

contract SignatureHooks is AbstractSignatureHooks {
    constructor(address _validator) AbstractSignatureHooks(_validator) {}

    /**
     * @notice Internal function to execute calls on CoinbaseSmartWallet
     */
    function _executeCalls(address payable account, bytes calldata calls) internal override {
        CoinbaseSmartWallet.Call[] memory decodedCalls = abi.decode(calls, (CoinbaseSmartWallet.Call[]));
        CoinbaseSmartWallet(account).executeBatch(decodedCalls);
    }

    /**
     * @notice Calculate the exact replaySafeHash that CoinbaseSmartWallet will validate
     */
    function _calculateValidationHash(address account, bytes32 originalHash) internal view override returns (bytes32) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("Coinbase Smart Wallet"), // name from _domainNameAndVersion()
                keccak256("1"), // version from _domainNameAndVersion()
                block.chainid,
                account // verifyingContract = wallet address
            )
        );
        bytes32 MESSAGE_TYPEHASH = keccak256("CoinbaseSmartWalletMessage(bytes32 hash)");
        bytes32 structHash = keccak256(abi.encode(MESSAGE_TYPEHASH, originalHash));
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}
