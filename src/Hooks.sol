// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";
import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";

/**
 * Balance abstraction:
 * MagicSpend
 * Withdraw from subaccount
 * Swap from other tokens
 * Withdraw from cross-chain balance
 *
 * Goal: Sign a hash that can only be validated after an array of calls has been executed through the account first.
 * 1) signature only valid if calls applied
 * 2) calls only applied if verifying signature
 */
contract ERC6492Validator {
    mapping(address verifyingContract => bytes32 hash) currentHash;

    function isValidSignatureNowAllowSideEffects(address account, bytes32 hash, bytes calldata signature)
        external
        returns (bool)
    {
        currentHash[msg.sender] = hash;
        return SignatureCheckerLib.isValidERC6492SignatureNowAllowSideEffects(account, hash, signature);
    }
}

/// signature: 0x{prepareTarget}{prepareData}{actualSig}{6492}
/// prepareData.signature: {passkey ownerIndex}{passkey signature over message(hash, calls)}
/// actualSig: {hooks ownerIndex}{empty}
contract SignatureHooks {
    ERC6492Validator immutable validator;

    mapping(address => mapping(bytes32 => bool)) isSigned;

    function isValidSignature(bytes32 hash, bytes calldata) external view returns (bool) {
        return isSigned[msg.sender][hash];
    }

    function executeSignedCallsWithMessage(
        address account,
        CoinbaseSmartWallet.Call[] calls,
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

        // set hash as signed
        if (isSigned[account][hash]) revert();
        isSigned[account][hash] = true;

        // execute calls
        CoinbaseSmartWallet(account).executeBatch(calls);
    }
}

contract SignedCallManager {
    struct Batch {
        address executor;
        CoinbaseSmartWallet.Call[] calls; // { target, value, data }[]
        uint256 nonce;
    }

    bytes32 SIGNED_CALLS_TYPEHASH = keccak256("SignedCalls()");
    bytes32 SIGNED_CALLS_WITH_MESSAGE_TYPEHASH = keccak256("SignedCallsWithMessage()");

    mapping(uint256 nonce => bool) nonceUsed;

    function executeSignedCalls(address account, CoinbaseSmartWallet.Call[] calls, uint256 nonce, bytes signature)
        external
    {
        bytes32 hash = keccak256(abi.encode(msg.sender, calls, nonce));

        // validate signature
        SignatureCheckerLib.isValidSignatureNow(account, hash, signature);

        // use nonce
        if (nonceUsed[nonce]) revert();
        nonceUsed[nonce] = true;

        // execute calls
        CoinbaseSmartWallet(account).executeBatch(calls);
    }

    function executeSignedCallsPublic(address account, CoinbaseSmartWallet.Call[] calls, uint256 nonce, bytes signature)
        external
    {
        bytes32 hash = keccak256(abi.encode(address(0), calls, nonce));

        // validate signature
        SignatureCheckerLib.isValidSignatureNow(account, hash, signature);

        // use nonce
        if (nonceUsed[nonce]) revert();
        nonceUsed[nonce] = true;

        // execute calls
        CoinbaseSmartWallet(account).executeBatch(calls);
    }
}

contract HooksPaymentCollector {
    function collectTokens(address payer, bytes calldata collectorData) {
        (address callManager, CoinbaseSmartWallet.Call[] memory calls, uint256 nonce, bytes memory signature) =
            abi.decode(collectorData, (address, CoinbaseSmartWallet.Call[], uint256, bytes));

        // validate account signed the calls
        SignedCallManager(callManager).executeSignedCalls(calls, nonce, signature);
    }
}
