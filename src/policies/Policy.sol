// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PermissionTypes} from "../PermissionTypes.sol";

/// @notice A policy defines an authority identity and returns a wallet call plan.
interface Policy {
    /// @notice Return the expected authority for this policy instance.
    function authority(bytes calldata policyConfig) external view returns (address);

    /// @notice Build the account call and optional post-call (executed on the policy).
    function onExecute(
        PermissionTypes.Install calldata install,
        uint256 execNonce,
        bytes calldata policyConfig,
        bytes calldata policyData
    ) external returns (bytes memory accountCallData, bytes memory postCallData);
}


