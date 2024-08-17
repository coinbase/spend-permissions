// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IPermissionCallable} from "../PermissionCallable/IPermissionCallable.sol";
import {PermissionManager} from "../PermissionManager.sol";
import {NativeTokenRollingAllowance} from "../stores/NativeTokenRollingAllowance.sol";
import {Bytes} from "../utils/Bytes.sol";
import {ICoinbaseSmartWallet} from "../utils/ICoinbaseSmartWallet.sol";
import {IMagicSpend} from "../utils/IMagicSpend.sol";
import {UserOperation, UserOperationUtils} from "../utils/UserOperationUtils.sol";
import {IPermissionContract} from "./IPermissionContract.sol";

/// @title PermissionCallableNativeTokenRollingAllowance
///
/// @notice Supports spending native token with rolling limits.
/// @notice Only allow calls to a single allowed contract using IPermissionCallable.permissionedCall selector.
///
/// @dev Called by PermissionManager at end of its validation flow.
///
/// @author Coinbase (https://github.com/coinbase/smart-wallet-permissions)
contract PermissionCallableNativeTokenRollingAllowance is IPermissionContract, NativeTokenRollingAllowance {
    /// @notice MagicSpend withdraw asset is not native token.
    error InvalidWithdrawAsset();

    /// @notice Call to assertSpend not made on self or with invalid data.
    error InvalidAssertSpendCall();

    /// @param manager Contract address for PermissionManager.
    constructor(address manager) NativeTokenRollingAllowance(manager) {}

    /// @notice Validate the permission to execute a userOp.
    ///
    /// @dev Offchain userOp construction should append assertSpend call to calls array if spending value.
    /// @dev Rolling native token spend accounting does not protect against re-entrancy where an external call could
    ///      trigger an authorized call back to the account to spend more ETH.
    /// @dev Rolling native token spend accounting overestimates spend via gas when a paymaster is not used.
    ///
    /// @param permissionHash Hash of the permission.
    /// @param permissionFields Additional arguments for validation.
    /// @param userOp User operation to validate permission for.
    function validatePermission(bytes32 permissionHash, bytes calldata permissionFields, UserOperation calldata userOp)
        external
        view
    {
        // parse permission fields
        (uint256 spendLimit, uint256 rollingPeriod, address allowedContract) =
            abi.decode(permissionFields, (uint256, uint256, address));

        // parse user operation call data as `executeBatch` arguments (call array)
        ICoinbaseSmartWallet.Call[] memory calls = abi.decode(userOp.callData[4:], (ICoinbaseSmartWallet.Call[]));
        uint256 callsLen = calls.length;

        // initialize loop accumulators
        uint256 callsSpend = 0;

        // loop over calls to validate native token spend and allowed contracts
        // start index at 1 to ignore first call, enforced by PermissionManager as validation call on itself
        // end index at callsLen - 2 to ignore assertSpend call, enforced after loop as validation call on self
        for (uint256 i = 1; i < callsLen - 1; i++) {
            ICoinbaseSmartWallet.Call memory call = calls[i];
            bytes4 selector = bytes4(call.data);

            if (selector == IPermissionCallable.permissionedCall.selector) {
                // check call target is the allowed contract
                if (call.target != allowedContract) revert UserOperationUtils.TargetNotAllowed();
                // assume PermissionManager already prevents account as target
            } else if (selector == IMagicSpend.withdraw.selector) {
                // parse MagicSpend withdraw request
                IMagicSpend.WithdrawRequest memory withdraw =
                    abi.decode(Bytes.sliceCallArgs(calls[i].data), (IMagicSpend.WithdrawRequest));

                // check withdraw is native token
                if (withdraw.asset != address(0)) revert InvalidWithdrawAsset();
                // do not need to accrue callsSpend because withdrawn value will be spent in other calls
            } else if (selector == IMagicSpend.withdrawGasExcess.selector) {
                // ok
            } else {
                revert UserOperationUtils.SelectorNotAllowed();
            }

            // accumulate spend value
            callsSpend += call.value;
        }

        // prepare expected call data for assertSpend
        bytes memory assertSpendData = abi.encodeWithSelector(
            NativeTokenRollingAllowance.assertSpend.selector,
            permissionHash,
            spendLimit,
            rollingPeriod,
            callsSpend,
            // gasSpend is prefund required by entrypoint (ignores refund for unused gas)
            UserOperationUtils.getRequiredPrefund(userOp),
            // paymaster data is empty or first 20 bytes are contract address
            userOp.paymasterAndData.length == 0 ? address(0) : address(bytes20(userOp.paymasterAndData[:20]))
        );

        // check that last call is assertSpend
        if (
            (
                calls[callsLen - 1].target != address(this)
                    || keccak256(calls[callsLen - 1].data) != keccak256(assertSpendData)
            )
        ) {
            revert InvalidAssertSpendCall();
        }
    }
}