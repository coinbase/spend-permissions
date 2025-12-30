// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Shared types for SessionManager and session policies to avoid circular imports.
library SessionTypes {
    /// @notice Session policy installation parameters authorized by the account.
    struct Install {
        address account;
        address policy;
        bytes32 policyConfigHash;
        uint48 validAfter;
        uint48 validUntil;
        uint256 salt;
    }
}

