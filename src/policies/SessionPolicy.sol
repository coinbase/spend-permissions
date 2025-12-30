// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SessionTypes} from "../SessionTypes.sol";

/// @notice A session policy defines the session signer identity and returns a wallet call plan.
interface SessionPolicy {
    /// @notice Return the expected session signer for this policy instance.
    function sessionSigner(bytes calldata policyConfig) external view returns (address);

    /// @notice Build the account call and optional post-call (executed on the policy).
    function onExecute(
        SessionTypes.Install calldata install,
        uint256 execNonce,
        bytes calldata policyConfig,
        bytes calldata policyData
    ) external returns (bytes memory accountCallData, bytes memory postCallData);
}

