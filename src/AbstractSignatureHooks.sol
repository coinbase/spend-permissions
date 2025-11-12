// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PublicERC6492Validator} from "./PublicERC6492Validator.sol";
import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";

/**
 * @title AbstractSignatureHooks
 * @notice Base contract for signature hooks that can only be validated after an array of calls has been executed
 * through the account first.
 * @dev Goal: Sign a hash that can only be validated after an array of calls has been executed through the account
 * first.
 * 1) signature only valid if calls applied
 * 2) calls only applied if verifying signature
 */
abstract contract AbstractSignatureHooks {
    PublicERC6492Validator immutable validator;

    bytes4 constant ERC1271_MAGIC_VALUE = 0x1626ba7e;
    bytes4 constant ERC1271_FAILED_VALUE = 0xffffffff;

    mapping(address => mapping(bytes32 => bool)) isSigned;

    constructor(address _validator) {
        validator = PublicERC6492Validator(_validator);
    }

    /**
     * @notice ERC-1271 signature validation
     * @param hash The hash to validate
     * @return bytes4 Magic value if signature is valid, failure value otherwise
     */
    function isValidSignature(bytes32 hash, bytes calldata) external view returns (bytes4) {
        return isSigned[msg.sender][hash] ? ERC1271_MAGIC_VALUE : ERC1271_FAILED_VALUE;
    }

    /**
     * @notice Execute signed calls with message validation
     * @param account The account that is executing the calls
     * @param calls The calls to execute (encoded as bytes for flexibility)
     * @param signature The signature that has been signed by the account across message(permit3Hash, verifyingContract,
     * calls)
     * @param verifyingContract The Permit3 contract that needs to have updated its hash in the validator
     * @param hash The hash of the Permit3 permit (or any arbitrary message being evaluated by the verifyingContract)
     */
    function executeSignedCallsWithMessage(
        address payable account,
        bytes calldata calls,
        bytes calldata signature,
        address verifyingContract,
        bytes32 hash
    ) external {
        if (msg.sender != address(validator)) revert();
        if (validator.currentHash(verifyingContract) != hash) revert();

        // construct hash including payload hash + calls
        // TODO: chainID + nonce? (the permit3 hash is the nonce)
        bytes32 message = keccak256(abi.encode(verifyingContract, calls, hash));

        // validate signature
        // TODO don't we need to check the return value here?
        SignatureCheckerLib.isValidSignatureNow(account, message, signature);

        // Calculate the hash that will be validated (may be transformed by wallet)
        bytes32 validationHash = _calculateValidationHash(account, hash);

        // set hash as signed (prevent replay)
        if (isSigned[account][validationHash]) revert();
        isSigned[account][validationHash] = true;

        // execute calls through wallet-specific implementation
        _executeCalls(account, calls);
    }

    /**
     * @notice Abstract function to execute calls on the specific wallet implementation
     * @param account The account to execute calls on
     * @param calls The encoded calls to execute
     */
    function _executeCalls(address payable account, bytes calldata calls) internal virtual;

    /**
     * @notice Calculate the hash that will be validated by the wallet's isValidSignature
     * @dev Some wallets (like CoinbaseSmartWallet) transform the original hash before validation
     * @param account The wallet account
     * @param originalHash The original hash being signed
     * @return The hash that will actually be validated
     */
    function _calculateValidationHash(address account, bytes32 originalHash) internal view virtual returns (bytes32) {
        // Default implementation: no transformation
        return originalHash;
    }
}
