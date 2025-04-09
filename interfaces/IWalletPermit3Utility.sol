// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IWalletPermit3Utility
/// @notice Interface for wallet permit3 utility functionality
interface IWalletPermit3Utility {
    /// @notice Sends native tokens (ETH) from the account to Permit3
    /// @dev Implementation must handle native token spending logic
    /// @param account Address of the account to spend from
    /// @param value Amount of native tokens to spend
    function spendNativeToken(address account, uint256 value) external;
}
