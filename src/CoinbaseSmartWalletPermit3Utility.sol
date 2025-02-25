// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IWalletPermit3Utility.sol";
import "./Permit3.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";

/// @title CoinbaseSmartWalletPermit3Utility
/// @notice Utility contract for handling Permit3 integrations with Coinbase Smart Wallet
contract CoinbaseSmartWalletPermit3Utility is IWalletPermit3Utility {
    /// @notice The Permit3 contract instance
    Permit3 public immutable permit3;

    /// @notice Only allows the Permit3 contract to call the function
    error OnlyPermit3();

    /// @notice Constructor to set the Permit3 contract address
    /// @param _permit3 Address of the Permit3 contract
    constructor(address _permit3) {
        permit3 = Permit3(payable(_permit3));
    }

    /// @notice Ensures only the Permit3 contract can call the function
    modifier onlyPermit3() {
        if (msg.sender != address(permit3)) revert OnlyPermit3();
        _;
    }

    /// @notice Approves an ERC20 token for infinite spending by Permit3
    /// @dev Calls execute on the CoinbaseSmartWallet to approve Permit3 for infinite spending
    /// @param token The ERC20 token to approve
    /// @param account The CoinbaseSmartWallet account granting the approval
    function approveERC20(address token, address account) external onlyPermit3 {
        // Create the approval calldata for the ERC20 token
        bytes memory approvalCalldata =
            abi.encodeWithSelector(IERC20.approve.selector, address(permit3), type(uint256).max);

        // Call execute on the CoinbaseSmartWallet
        CoinbaseSmartWallet(payable(account)).execute(
            token, // target (the ERC20 token contract)
            0, // value (no ETH needed for approve)
            approvalCalldata
        );
    }

    /// @notice Registers this utility contract with Permit3
    /// @param account The CoinbaseSmartWallet account to register this utility for
    function registerPermit3Utility(address account) external onlyPermit3 {
        bytes memory registerCalldata =
            abi.encodeWithSelector(Permit3.registerPermit3Utility.selector, account, address(this));

        CoinbaseSmartWallet(payable(account)).execute(address(permit3), 0, registerCalldata);
    }

    /// @notice Sends native tokens (ETH) from the account to Permit3
    /// @dev Calls execute on the CoinbaseSmartWallet to send ETH to Permit3
    /// @inheritdoc IWalletPermit3Utility
    function spendNativeToken(address account, uint256 value) external override onlyPermit3 {
        CoinbaseSmartWallet(payable(account)).execute(
            address(permit3), // target (the Permit3 contract)
            value, // value (amount of ETH to send)
            "" // data (empty since we're just sending ETH)
        );
    }
}
