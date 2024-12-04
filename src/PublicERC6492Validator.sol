// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";

/// @title PublicERC6492Validator
///
/// @notice Validate ERC-6492 signatures and perform contract deployment or preparation when necessary
///         (https://eips.ethereum.org/EIPS/eip-6492).
///
/// @dev Anyone can make arbitrary calls from this contract, so it should never have priviledged access control.
///
/// @author Coinbase (https://github.com/coinbase/spend-permissions)
contract PublicERC6492Validator {
    /// @notice Validate contract signature and execute side effects if provided.
    ///
    /// @dev If the signature is postfixed with the ERC-6492 magic value, an external call to deploy/prepare the account
    ///      is made before calling ERC-1271 `isValidSignature`.
    /// @dev This function is NOT reentrancy safe.
    ///
    /// @return isValid True if signature is valid.
    function isValidSignatureNowAllowSideEffects(address account, bytes32 hash, bytes calldata signature)
        external
        returns (bool)
    {
        return SignatureCheckerLib.isValidERC6492SignatureNowAllowSideEffects(account, hash, signature);
    }
}
