// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Multicallable} from "solady/utils/Multicallable.sol";
import {SpendPermissionManager} from "./SpendPermissionManager.sol";

/// @title SpendRouter
/// @author Coinbase
/// @notice A singleton router contract that spends and routes funds to designated recipients.
///
/// @dev Decodes routing metadata (authorized executor, recipient) from a SpendPermission's extraData field,
///      pulls tokens from a user's account via SpendPermissionManager, and forwards them to the recipient.
///      Supports both native ETH (ERC-7528) and ERC-20 tokens.
contract SpendRouter is Multicallable {
    /// @notice The SpendPermissionManager used for all permission approvals and spend executions.
    SpendPermissionManager public immutable PERMISSION_MANAGER;

    /// @notice ERC-7528 native token address used by SpendPermissionManager.
    address public constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice Thrown when `msg.sender` does not match the authorized executor decoded from `extraData`.
    ///
    /// @param caller The actual `msg.sender`.
    /// @param expected The authorized executor address decoded from the permission's `extraData`.
    error UnauthorizedSender(address caller, address expected);

    /// @notice Thrown when `extraData` is not exactly 64 bytes (two ABI-encoded addresses).
    ///
    /// @param length The actual byte length of the provided `extraData`.
    /// @param extraData The malformed `extraData` payload.
    error MalformedExtraData(uint256 length, bytes extraData);

    /// @notice Thrown when a required address argument is the zero address.
    error ZeroAddress();

    /// @notice Thrown when `SpendPermissionManager.approveWithSignature` returns false.
    error PermissionApprovalFailed();

    /// @notice Emitted when a spend operation is successfully routed.
    ///
    /// @param account The account from which tokens were spent.
    /// @param executor The authorized executor address.
    /// @param recipient The recipient address.
    /// @param permissionHash The hash of the spend permission used.
    /// @param token The token address.
    /// @param value The amount of tokens routed.
    event SpendRouted(
        address indexed account,
        address indexed executor,
        address indexed recipient,
        bytes32 permissionHash,
        address token,
        uint256 value
    );

    /// @notice Revokes a spend permission where this contract is the spender.
    ///
    /// @dev Decodes `executor` from `permission.extraData` and verifies `msg.sender == executor`.
    ///      Delegates to `SpendPermissionManager.revokeAsSpender` to permanently revoke the permission.
    ///
    /// @param permission The spend permission to revoke.
    function revokeAsSpender(SpendPermissionManager.SpendPermission calldata permission) external {
        (address executor,) = decodeExtraData(permission.extraData);
        if (msg.sender != executor) revert UnauthorizedSender(msg.sender, executor);
        PERMISSION_MANAGER.revokeAsSpender(permission);
    }

    /// @notice Deploys a new SpendRouter bound to the given SpendPermissionManager.
    ///
    /// @param spendPermissionManager The SpendPermissionManager instance this router will use
    ///        for all permission approvals and spend executions.
    constructor(SpendPermissionManager spendPermissionManager) {
        PERMISSION_MANAGER = spendPermissionManager;
    }

    /// @notice Accepts native ETH so the contract can receive funds from SpendPermissionManager before forwarding.
    receive() external payable {}

    /// @notice Spends tokens from the user's account via an already-approved permission and forwards them
    ///         to the recipient encoded in `permission.extraData`.
    ///
    /// @dev Decodes `(executor, recipient)` from `permission.extraData`, verifies `msg.sender == executor`,
    ///      calls `SpendPermissionManager.spend` to pull tokens into this contract, then transfers
    ///      them to `recipient`. The permission must already be approved on-chain.
    ///
    /// @param permission The spend permission containing account, spender, token, allowance, period,
    ///        start, end, salt, and extraData fields.
    /// @param value The amount of tokens to spend and forward.
    function spendAndRoute(SpendPermissionManager.SpendPermission calldata permission, uint160 value) external {
        (address executor, address recipient) = decodeExtraData(permission.extraData);
        if (msg.sender != executor) revert UnauthorizedSender(msg.sender, executor);
        if (recipient == address(0)) revert ZeroAddress();

        PERMISSION_MANAGER.spend(permission, value);

        emit SpendRouted(
            permission.account, executor, recipient, PERMISSION_MANAGER.getHash(permission), permission.token, value
        );

        if (permission.token == NATIVE_TOKEN_ADDRESS) {
            SafeTransferLib.safeTransferETH(payable(recipient), value);
        } else {
            SafeTransferLib.safeTransfer(permission.token, recipient, value);
        }
    }

    /// @notice Approves a permission with the user's signature, spends tokens, and forwards them to the
    ///         recipient — all in a single transaction.
    ///
    /// @dev Same flow as `spendAndRoute`, but first calls `SpendPermissionManager.approveWithSignature` to approve
    ///      the permission on-chain using the user's EIP-712 signature before spending.
    ///
    /// @param permission The spend permission containing account, spender, token, allowance, period,
    ///        start, end, salt, and extraData fields.
    /// @param value The amount of tokens to spend and forward.
    /// @param signature The user's EIP-712 signature authorizing the permission.
    function spendAndRouteWithSignature(
        SpendPermissionManager.SpendPermission calldata permission,
        uint160 value,
        bytes calldata signature
    ) external {
        (address executor, address recipient) = decodeExtraData(permission.extraData);
        if (msg.sender != executor) revert UnauthorizedSender(msg.sender, executor);
        if (recipient == address(0)) revert ZeroAddress();

        bool approved = PERMISSION_MANAGER.approveWithSignature(permission, signature);
        if (!approved) revert PermissionApprovalFailed();

        PERMISSION_MANAGER.spend(permission, value);

        emit SpendRouted(
            permission.account, executor, recipient, PERMISSION_MANAGER.getHash(permission), permission.token, value
        );

        if (permission.token == NATIVE_TOKEN_ADDRESS) {
            SafeTransferLib.safeTransferETH(payable(recipient), value);
        } else {
            SafeTransferLib.safeTransfer(permission.token, recipient, value);
        }
    }

    /// @notice Constructs a properly formatted `SpendPermission.extraData` payload.
    ///
    /// @dev ABI-encodes two addresses into a 64-byte payload. Reverts if either address is zero.
    ///
    /// @param executor The authorized executor address that will call `spendAndRoute` or `spendAndRouteWithSignature`.
    /// @param recipient The address that will receive the forwarded tokens.
    ///
    /// @return extraData The 64-byte ABI-encoded payload to set as `SpendPermission.extraData`.
    function encodeExtraData(address executor, address recipient) public pure returns (bytes memory extraData) {
        if (executor == address(0)) revert ZeroAddress();
        if (recipient == address(0)) revert ZeroAddress();

        return abi.encode(executor, recipient);
    }

    /// @notice Decodes the authorized executor and recipient addresses from a permission's `extraData`.
    ///
    /// @dev Reverts if `extraData` is not exactly 64 bytes.
    ///
    /// @param extraData The raw `extraData` bytes from a `SpendPermission`.
    ///
    /// @return executor The authorized executor address.
    /// @return recipient The address that will receive the forwarded tokens.
    function decodeExtraData(bytes memory extraData) public pure returns (address executor, address recipient) {
        if (extraData.length != 64) revert MalformedExtraData(extraData.length, extraData);
        (executor, recipient) = abi.decode(extraData, (address, address));
    }
}
