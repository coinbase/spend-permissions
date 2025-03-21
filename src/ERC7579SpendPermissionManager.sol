// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {PublicERC6492Validator} from "./PublicERC6492Validator.sol";
import {SpendPermissionManager} from "./SpendPermissionManager.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

interface IERC7579Execution {
    function execute(bytes32 mode, bytes calldata executionCalldata) external;
}

/**
 * @title ERC7579SpendPermissionManager
 * @notice A spend permission manager that supports ERC7579 modular smart accounts
 * @dev Implements token transfers through ERC7579's execution interface
 */
contract ERC7579SpendPermissionManager is SpendPermissionManager {
    using SafeERC20 for IERC20;

    // Constant for ERC7579 execution mode (single call, revert on failure)
    bytes32 public constant SINGLE_CALL_MODE = bytes32(uint256(0x00));

    constructor(PublicERC6492Validator publicERC6492Validator, address magicSpend)
        SpendPermissionManager(publicERC6492Validator, magicSpend)
    {}

    /// @inheritdoc SpendPermissionManager
    function _transferFrom(address token, address account, address recipient, uint256 value) internal override {
        if (token == NATIVE_TOKEN) {
            // For native token transfers, we need to encode a call to transfer ETH
            bytes memory callData = abi.encodePacked(recipient);
            bytes memory executionCalldata = abi.encodePacked(account, value, callData);
            
            // Execute the transfer through the ERC7579 account
            IERC7579Execution(account).execute(SINGLE_CALL_MODE, executionCalldata);
        } else {
            // For ERC20 transfers, we encode a call to transferFrom
            bytes memory callData = abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                account,
                recipient,
                value
            );
            
            // Pack the execution data according to ERC7579 spec:
            // target (token address), value (0), and callData
            bytes memory executionCalldata = abi.encodePacked(token, uint256(0), callData);
            
            // Execute the transfer through the ERC7579 account
            IERC7579Execution(account).execute(SINGLE_CALL_MODE, executionCalldata);
        }
    }
}
