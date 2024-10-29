// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SpendPermissionManager} from "solady/SpendPermissionManager.sol";
import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";

/// @title ERC6492Deployer
///
/// @notice Validate ERC-6492 signatures and perform contract deployment or preparation when necessary.
///
/// @dev Dedicated contract for validating ERC-6492 (and therefore also ERC-1271) signatures,
/// performing contract deployment or preparation when necessary from an unprivileged context.
///
/// @author Coinbase (https://github.com/coinbase/spend-permissions)
contract ERC6492Deployer {
    function isValidERC6492SignatureNowAllowSideEffects(address account, bytes32 hash, bytes memory signature) public {
        return SignatureCheckerLib.isValidERC6492SignatureNowAllowSideEffects(account, hash, signature);
    }
}
