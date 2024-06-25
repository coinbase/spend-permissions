// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {UserOperationUtils} from "../utils/UserOperationUtils.sol";

abstract contract NativeTokenLimitPolicy is UserOperationUtils {
    /// @notice Total value sent in userOp exceeds session's spending limit
    error SpendingLimitExceeded();

    /// @notice Spend in user operation not registered at end of execution.
    error MissingRegisterSpend();

    /// @notice Register native token spend for a session
    event SpendRegistered(address indexed account, bytes32 indexed sessionHash, uint256 value);

    /// @notice accumulated spend of native asset per session per account.
    ///
    /// @dev last mapping key must be account address for 4337 slot access.
    mapping(bytes32 sessionHash => mapping(address account => uint256 spend)) private _sessionSpend;

    /// @notice Register a spend of native token for a given session.
    ///
    /// @dev Accounts can call this even if they did not actually spend anything, so there is a self-DOS risk.
    function registerSpend(bytes32 sessionHash, uint256 value) external {
        _sessionSpend[sessionHash][msg.sender] += value;
        emit SpendRegistered(msg.sender, sessionHash, value);
    }

    function _validateAttemptSpend(address account, bytes32 sessionHash, uint256 attemptSpend, uint256 approvedSpend) internal view {
        if (_sessionSpend[sessionHash][account] + attemptSpend > approvedSpend) revert SpendingLimitExceeded();
    }

    function _validateRegisterSpendCall(bytes32 sessionHash, uint256 attemptSpend, Call memory lastCall) internal view {
        bytes memory registerSpendData = abi.encodeWithSelector(NativeTokenLimitPolicy.registerSpend.selector, sessionHash, attemptSpend);
        if (lastCall.target != address(this) || keccak256(lastCall.data) != keccak256(registerSpendData)) {
            revert MissingRegisterSpend();
        }
    }
}