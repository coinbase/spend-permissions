// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SpendPermissionManager} from "./SpendPermissionManager.sol";
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
    function isValidERC6492SignatureNowAllowSideEffects(address account, bytes32 hash, bytes memory signature)
        public
        returns (bool)
    {
        return SignatureCheckerLib.isValidERC6492SignatureNowAllowSideEffects(account, hash, signature);
    }
}
