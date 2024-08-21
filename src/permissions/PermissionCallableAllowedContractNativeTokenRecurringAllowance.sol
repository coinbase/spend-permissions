// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";

import {PermissionManager} from "../PermissionManager.sol";
import {IMagicSpend} from "../interfaces/IMagicSpend.sol";
import {IPermissionCallable} from "../interfaces/IPermissionCallable.sol";
import {IPermissionContract} from "../interfaces/IPermissionContract.sol";
import {BytesLib} from "../utils/BytesLib.sol";
import {NativeTokenRecurringAllowance} from "../utils/NativeTokenRecurringAllowance.sol";
import {UserOperation, UserOperationLib} from "../utils/UserOperationLib.sol";

/// @title PermissionCallableAllowedContractNativeTokenRecurringAllowance
///
/// @notice Only allow custom external calls with IPermissionCallable.permissionedCall selector.
/// @notice Only allow custom external calls to a single allowed contract.
/// @notice Allow spending native token with recurring allowance.
/// @notice Allow withdrawing native token from MagicSpend both as paymaster and non-paymaster flows.
///
/// @dev Requires appending useRecurringAllowance call on every use.
///
/// @author Coinbase (https://github.com/coinbase/smart-wallet-permissions)
contract PermissionCallableAllowedContractNativeTokenRecurringAllowance is
    IPermissionContract,
    NativeTokenRecurringAllowance
{
    /// @notice Permission-specific values for this permission contract.
    struct PermissionValues {
        /// @dev Recurring native token allowance value (struct).
        RecurringAllowance recurringAllowance;
        /// @dev Single contract allowed to make custom external calls to.
        address allowedContract;
    }

    /// @notice Sender for intializePermission was not account or permission manager.
    error InvalidInitializePermissionSender();

    /// @notice MagicSpend withdraw asset is not native token.
    error InvalidWithdrawAsset();

    /// @notice Call to useRecurringAllowance not made on self or with invalid data.
    error InvalidUseRecurringAllowanceCall();

    /// @notice PermissionManager singleton.
    address public immutable permissionManager;

    /// @notice MagicSpend singleton.
    address public immutable magicSpend;

    /// @notice Constructor.
    ///
    /// @param permissionManager_ Contract address for PermissionManager.
    /// @param magicSpend_ Contract address for MagicSpend.
    constructor(address permissionManager_, address magicSpend_) {
        permissionManager = permissionManager_;
        magicSpend = magicSpend_;
    }

    /// @notice Validate the permission to execute a userOp.
    ///
    /// @dev Offchain userOp construction should append useRecurringAllowance call to calls array if spending value.
    /// @dev Rolling native token spend accounting does not protect against re-entrancy where an external call could
    ///      trigger an authorized call back to the account to spend more ETH.
    /// @dev Rolling native token spend accounting overestimates spend via gas when a paymaster is not used.
    ///
    /// @param permissionHash Hash of the permission.
    /// @param permissionValues Permission-specific values for this permission contract.
    /// @param userOp User operation to validate permission for.
    function validatePermission(bytes32 permissionHash, bytes calldata permissionValues, UserOperation calldata userOp)
        external
        view
    {
        (PermissionValues memory values) = abi.decode(permissionValues, (PermissionValues));

        // parse user operation call data as `executeBatch` arguments (call array)
        CoinbaseSmartWallet.Call[] memory calls = abi.decode(userOp.callData[4:], (CoinbaseSmartWallet.Call[]));
        uint256 callsLen = calls.length;

        // initialize loop accumulators
        uint256 callsSpend = 0;

        // loop over calls to validate native token spend and allowed contracts
        // start index at 1 to ignore beforeCalls call, enforced by PermissionManager as self-call
        // end index at callsLen - 2 to ignore useRecurringAllowance call, enforced after loop as self-call
        for (uint256 i = 1; i < callsLen - 1; i++) {
            CoinbaseSmartWallet.Call memory call = calls[i];
            bytes4 selector = bytes4(call.data);

            if (selector == IPermissionCallable.permissionedCall.selector) {
                // check call target is the allowed contract
                if (call.target != values.allowedContract) revert UserOperationLib.TargetNotAllowed();
                // assume PermissionManager already prevents account as target
            } else if (selector == IMagicSpend.withdraw.selector) {
                // parse MagicSpend withdraw request
                IMagicSpend.WithdrawRequest memory withdraw =
                    abi.decode(BytesLib.sliceCallArgs(calls[i].data), (IMagicSpend.WithdrawRequest));

                // check withdraw is native token
                if (withdraw.asset != address(0)) revert InvalidWithdrawAsset();
                // do not need to accrue callsSpend because withdrawn value will be spent in other calls
            } else if (selector == IMagicSpend.withdrawGasExcess.selector) {
                // ok
            } else {
                revert UserOperationLib.SelectorNotAllowed();
            }

            // accumulate spend value
            callsSpend += call.value;
        }

        // add gas cost if beared by the user
        uint256 totalSpend = callsSpend;
        address paymaster = UserOperationLib.getPaymaster(userOp.paymasterAndData);
        if (paymaster == address(0) || paymaster == magicSpend) {
            // gas spend is prefund required by entrypoint (ignores refund for unused gas)
            totalSpend += UserOperationLib.getRequiredPrefund(userOp);
            // recall MagicSpend enforces withdraw to be native token when used as a paymaster
        }

        // prepare expected call data for useRecurringAllowance
        bytes memory useRecurringAllowanceData = abi.encodeWithSelector(
            PermissionCallableAllowedContractNativeTokenRecurringAllowance.useRecurringAllowance.selector,
            permissionHash,
            totalSpend
        );

        // check last call is valid this.useRecurringAllowance
        CoinbaseSmartWallet.Call memory lastCall = calls[callsLen - 1];
        if (lastCall.target != address(this) || keccak256(lastCall.data) != keccak256(useRecurringAllowanceData)) {
            revert InvalidUseRecurringAllowanceCall();
        }
    }

    /// @notice Initialize the permission values.
    ///
    /// @dev Called by permission manager on approval transaction.
    ///
    /// @param account Account of the permission.
    /// @param permissionHash Hash of the permission.
    /// @param permissionValues Permission-specific values for this permission contract.
    function initializePermission(address account, bytes32 permissionHash, bytes calldata permissionValues) external {
        (PermissionValues memory values) = abi.decode(permissionValues, (PermissionValues));

        // check sender is permission manager
        if (msg.sender != address(permissionManager)) revert InvalidInitializePermissionSender();

        _initializeRecurringAllowance(account, permissionHash, values.recurringAllowance);
    }

    /// @notice Register a spend of native token for a given permission.
    ///
    /// @dev Accounts can call this even if they did not actually spend anything, so there is a self-DOS vector.
    /// @dev State read on Manager for adding paymaster gas to total spend must happen in execution phase.
    ///
    /// @param permissionHash Hash of the permission.
    /// @param spend Value of native token spent on calls and gas.
    function useRecurringAllowance(bytes32 permissionHash, uint256 spend) external {
        _useRecurringAllowance(msg.sender, permissionHash, spend);
    }
}