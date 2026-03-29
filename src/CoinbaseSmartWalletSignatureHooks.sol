// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PublicERC6492Validator} from "./PublicERC6492Validator.sol";
import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";
import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";

/**
 * @title CoinbaseSmartWallet-Specific SignatureHooks
 *
 * @notice Signature hooks implementation that knows CoinbaseSmartWallet's exact ERC1271 transformation.
 * This allows us to predict and store the exact hash that will be validated.
 *
 * Flow:
 * 1) executeSignedCallsWithMessage receives originalHash
 * 2) We calculate the replaySafeHash using CoinbaseSmartWallet's transformation
 * 3) We store isSigned[account][replaySafeHash] = true
 * 4) When isValidSignature is called with replaySafeHash, we return true
 */
contract CoinbaseSmartWalletSignatureHooks {
    PublicERC6492Validator immutable validator;

    bytes4 constant ERC1271_MAGIC_VALUE = 0x1626ba7e;
    bytes4 constant ERC1271_FAILED_VALUE = 0xffffffff;

    mapping(address => mapping(bytes32 => bool)) isSigned;

    constructor(address _validator) {
        validator = PublicERC6492Validator(_validator);
    }

    function isValidSignature(bytes32 hash, bytes calldata) external view returns (bytes4) {
        return isSigned[msg.sender][hash] ? ERC1271_MAGIC_VALUE : ERC1271_FAILED_VALUE;
    }

    /// @param account The account that is executing the calls
    /// @param calls The calls to execute
    /// @param signature The signature that has been signed by the account
    /// @param verifyingContract The Permit3 contract
    /// @param hash The hash of the Permit3 permit (original hash)
    function executeSignedCallsWithMessage(
        address payable account,
        CoinbaseSmartWallet.Call[] memory calls,
        bytes calldata signature,
        address verifyingContract,
        bytes32 hash
    ) external {
        if (msg.sender != address(validator)) revert();
        if (validator.currentHash(verifyingContract) != hash) revert();

        // construct hash including payload hash + calls
        bytes32 message = keccak256(abi.encode(verifyingContract, calls, hash));

        // validate signature
        SignatureCheckerLib.isValidSignatureNow(account, message, signature);

        // Calculate the replaySafeHash that CoinbaseSmartWallet will actually validate
        bytes32 replaySafeHash = _calculateReplaySafeHash(account, hash);

        // prevent replay
        if (isSigned[account][replaySafeHash]) revert();
        isSigned[account][replaySafeHash] = true;

        // execute calls
        CoinbaseSmartWallet(account).executeBatch(calls);
    }

    /// @notice Calculate the exact replaySafeHash that CoinbaseSmartWallet will validate
    /// @dev Replicates CoinbaseSmartWallet's ERC1271.replaySafeHash() transformation
    function _calculateReplaySafeHash(address wallet, bytes32 originalHash) internal view returns (bytes32) {
        // Replicate CoinbaseSmartWallet's domain separator
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("Coinbase Smart Wallet"), // name from _domainNameAndVersion()
                keccak256("1"), // version from _domainNameAndVersion()
                block.chainid,
                wallet // verifyingContract = wallet address
            )
        );

        // Replicate CoinbaseSmartWallet's message typehash and struct hash
        bytes32 MESSAGE_TYPEHASH = keccak256("CoinbaseSmartWalletMessage(bytes32 hash)");
        bytes32 structHash = keccak256(abi.encode(MESSAGE_TYPEHASH, originalHash));

        // Apply EIP-712 encoding (replicates _eip712Hash)
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}
