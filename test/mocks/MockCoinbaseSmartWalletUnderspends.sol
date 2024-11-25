// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {MockCoinbaseSmartWallet} from "./MockCoinbaseSmartWallet.sol";

/// @title Mock Coinbase Smart Wallet that Underspends
/// @notice Test mock that deliberately sends half the requested amount for testing revert conditions
contract MockCoinbaseSmartWalletUnderspends is MockCoinbaseSmartWallet {
    /// @notice Executes calls but sends half the requested value for ETH transfers
    /// @dev Only modifies ETH transfer amounts, passes through all other calls normally
    function execute(address target, uint256 value, bytes calldata data)
        external
        payable
        override
        onlyEntryPointOrOwner
    {
        // If it's a plain ETH transfer (empty data), send half the value
        if (data.length == 0) {
            (bool success,) = target.call{value: value / 2}("");
            require(success, "ETH transfer failed");
            return;
        }

        // For non-ETH transfers, proceed normally
        _call(target, value, data);
    }
}
