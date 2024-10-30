// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";

/// @title PublicERC6492Validator
///
/// @notice Validate ERC-6492 signatures and perform contract deployment or preparation when necessary.
///
/// @dev Dedicated contract for validating ERC-6492 (and therefore also ERC-1271) signatures,
/// performing contract deployment or preparation when necessary from an unprivileged context.
/// (https://eips.ethereum.org/EIPS/eip-6492)
///
/// @author Coinbase (https://github.com/coinbase/spend-permissions)
contract PublicERC6492Validator {
    /// @dev Returns whether `signature` is valid for `hash`.
    /// If the signature is postfixed with the ERC6492 magic number, it will attempt to
    /// deploy / prepare the `signer` smart account before doing a regular ERC1271 check.
    /// Note: This function is NOT reentrancy safe.
    function isValidSignatureNowAllowSideEffects(address account, bytes32 hash, bytes memory signature)
        public
        returns (bool)
    {
        return SignatureCheckerLib.isValidERC6492SignatureNowAllowSideEffects(account, hash, signature);
    }

    /// @dev Returns whether `signature` is valid for `hash`.
    /// If the signature is postfixed with the ERC6492 magic number, it will attempt
    /// to use a reverting verifier to deploy / prepare the `signer` smart account
    /// and do a `isValidSignature` check via the reverting verifier.
    /// Note: This function is reentrancy safe.
    /// The reverting verifier must be deployed.
    /// Otherwise, the function will return false if `signer` is not yet deployed / prepared.
    /// See: https://gist.github.com/Vectorized/846a474c855eee9e441506676800a9ad
    function isValidSignatureNow(address account, bytes32 hash, bytes memory signature) public returns (bool) {
        return SignatureCheckerLib.isValidERC6492SignatureNow(account, hash, signature);
    }
}
