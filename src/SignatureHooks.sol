// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PublicERC6492Validator} from "./PublicERC6492Validator.sol";
import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";
import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";

/**
 * Goal: Sign a hash that can only be validated after an array of calls has been executed through the account first.
 * 1) signature only valid if calls applied
 * 2) calls only applied if verifying signature
 */

/// signature: 0x{prepareTarget}{prepareData}{actualSig}{6492}
/// prepareData.signature: {passkey ownerIndex}{passkey signature over message(hash, calls)}
/// actualSig: {hooks ownerIndex}{empty}
contract SignatureHooks {
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
    /// @param signature The signature that has been signed by the account across message(permit3Hash,
    /// verifyingContract, calls)
    /// @param verifyingContract The Permit3 contract that needs to have updated its hash in the validator
    /// @param hash The hash of the Permit3 permit (or any arbitrary message being evaluated by the verifyingContract)
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
        // TODO: chainID + nonce? (the permit3 hash is the nonce)
        bytes32 message = keccak256(abi.encode(verifyingContract, calls, hash));

        // validate signature
        SignatureCheckerLib.isValidSignatureNow(account, message, signature);

        // set hash as signed (prevent replay)
        if (isSigned[account][hash]) revert();
        isSigned[account][hash] = true;

        // execute calls
        CoinbaseSmartWallet(account).executeBatch(calls);
    }
}

// contract SignedCallManager {
//     struct Batch {
//         address executor;
//         CoinbaseSmartWallet.Call[] calls; // { target, value, data }[]
//         uint256 nonce;
//     }

//     bytes32 SIGNED_CALLS_TYPEHASH = keccak256("SignedCalls()");
//     bytes32 SIGNED_CALLS_WITH_MESSAGE_TYPEHASH = keccak256("SignedCallsWithMessage()");

//     mapping(uint256 nonce => bool) nonceUsed;

//     function executeSignedCalls(address account, CoinbaseSmartWallet.Call[] calls, uint256 nonce, bytes signature)
//         external
//     {
//         bytes32 hash = keccak256(abi.encode(msg.sender, calls, nonce));

//         // validate signature
//         SignatureCheckerLib.isValidSignatureNow(account, hash, signature);

//         // use nonce
//         if (nonceUsed[nonce]) revert();
//         nonceUsed[nonce] = true;

//         // execute calls
//         CoinbaseSmartWallet(account).executeBatch(calls);
//     }

//     function executeSignedCallsPublic(address account, CoinbaseSmartWallet.Call[] calls, uint256 nonce, bytes
// signature)
//         external
//     {
//         bytes32 hash = keccak256(abi.encode(address(0), calls, nonce));

//         // validate signature
//         SignatureCheckerLib.isValidSignatureNow(account, hash, signature);

//         // use nonce
//         if (nonceUsed[nonce]) revert();
//         nonceUsed[nonce] = true;

//         // execute calls
//         CoinbaseSmartWallet(account).executeBatch(calls);
//     }
// }

// contract HooksPaymentCollector {
//     function collectTokens(address payer, bytes calldata collectorData) {
//         (address callManager, CoinbaseSmartWallet.Call[] memory calls, uint256 nonce, bytes memory signature) =
//             abi.decode(collectorData, (address, CoinbaseSmartWallet.Call[], uint256, bytes));

//         // validate account signed the calls
//         SignedCallManager(callManager).executeSignedCalls(calls, nonce, signature);
//     }
// }
