// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SpendPermissionManager} from "./SpendPermissionManager.sol";
import {MagicSpend} from "magicspend/MagicSpend.sol";
import {Multicallable} from "solady/utils/Multicallable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @title SpendRouter
/// @author Coinbase
/// @notice A singleton router contract that spends and routes funds to designated recipients.
///
/// @dev Decodes routing metadata (authorized executor, recipient) from a SpendPermission's extraData field,
///      pulls tokens from a user's account via SpendPermissionManager, and forwards them to the recipient.
///      Supports both native ETH (ERC-7528) and ERC-20 tokens.
///
/// @dev Fee-on-transfer ERC-20 tokens are unsupported. Routing forwards exactly `value`, so if the inbound
///      transfer credits less than `value`, the outbound transfer reverts. Rebasing or shares-based tokens
///      (e.g. stETH) may deliver up to a few wei less than `value` due to rounding in the two-hop transfer path.
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

    /// @notice Thrown when the contract receives ETH from an address other than PERMISSION_MANAGER.
    error UnauthorizedETHSender();

    /// @notice Thrown when the SpendPermissionManager address has no deployed code or has an EIP-7702 delegation
    ///         indicator, meaning it is not a persistently deployed contract.
    ///
    /// @param permissionManager The address that failed the persistent code check.
    error NotPersistentCode(address permissionManager);

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

    /// @notice Deploys a new SpendRouter bound to the given SpendPermissionManager.
    ///
    /// @dev Reverts if the SpendPermissionManager address has no code or has an EIP-7702 delegation indicator,
    ///      as such addresses are not persistently deployed contracts.
    ///
    /// @param spendPermissionManager The SpendPermissionManager instance this router will use
    ///        for all permission approvals and spend executions.
    constructor(SpendPermissionManager spendPermissionManager) {
        address addr = address(spendPermissionManager);
        bytes memory code = addr.code;
        if (code.length == 0 || (code.length == 23 && code[0] == 0xef && code[1] == 0x01 && code[2] == 0x00)) {
            revert NotPersistentCode(addr);
        }

        PERMISSION_MANAGER = spendPermissionManager;
    }

    /// @notice Accepts native ETH from SpendPermissionManager during spend-and-forward flows.
    ///
    /// @dev Restricts to PERMISSION_MANAGER to prevent accidental ETH loss from direct sends.
    receive() external payable {
        if (msg.sender != address(PERMISSION_MANAGER)) revert UnauthorizedETHSender();
    }

    /// @notice Spends tokens from the user's account via an already-approved permission and forwards them
    ///         to the recipient encoded in `permission.extraData`.
    ///
    /// @dev Decodes `(executor, recipient)` from `permission.extraData`, verifies `msg.sender == executor`,
    ///      calls `SpendPermissionManager.spend` to pull tokens into this contract, then transfers
    ///      them to `recipient`. The permission must already be approved onchain.
    ///
    /// @param permission The spend permission containing account, spender, token, allowance, period,
    ///        start, end, salt, and extraData fields.
    /// @param value The amount of tokens to spend and forward.
    function spendAndRoute(SpendPermissionManager.SpendPermission calldata permission, uint160 value) external {
        (address executor, address recipient) = _validateAndDecodeExtraData(permission.extraData);

        PERMISSION_MANAGER.spend(permission, value);

        emit SpendRouted(
            permission.account, executor, recipient, PERMISSION_MANAGER.getHash(permission), permission.token, value
        );

        _routeTokens(permission.token, recipient, value);
    }

    /// @notice Approves a permission with the user's signature, spends tokens, and forwards them to the
    ///         recipient — all in a single transaction.
    ///
    /// @dev Same flow as `spendAndRoute`, but first calls `SpendPermissionManager.approveWithSignature` to approve
    ///      the permission onchain using the user's EIP-712 signature before spending.
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
        (address executor, address recipient) = _validateAndDecodeExtraData(permission.extraData);

        bool approved = PERMISSION_MANAGER.approveWithSignature(permission, signature);
        if (!approved) revert PermissionApprovalFailed();

        PERMISSION_MANAGER.spend(permission, value);

        emit SpendRouted(
            permission.account, executor, recipient, PERMISSION_MANAGER.getHash(permission), permission.token, value
        );

        _routeTokens(permission.token, recipient, value);
    }

    /// @notice Spends tokens from the user's account via an already-approved permission, atomically funding the
    ///         account from MagicSpend, and forwards the tokens to the recipient encoded in `permission.extraData`.
    ///
    /// @dev Decodes `(executor, recipient)` from `permission.extraData`, verifies `msg.sender == executor`,
    ///      calls `SpendPermissionManager.spendWithWithdraw` to atomically withdraw from MagicSpend and pull tokens
    ///      into this contract, then transfers them to `recipient`. The permission must already be approved onchain.
    ///
    /// @param permission The spend permission containing account, spender, token, allowance, period,
    ///        start, end, salt, and extraData fields.
    /// @param value The amount of tokens to spend and forward.
    /// @param withdrawRequest The MagicSpend withdraw request to fund the account.
    function spendWithWithdrawAndRoute(
        SpendPermissionManager.SpendPermission calldata permission,
        uint160 value,
        MagicSpend.WithdrawRequest memory withdrawRequest
    ) external {
        (address executor, address recipient) = _validateAndDecodeExtraData(permission.extraData);

        PERMISSION_MANAGER.spendWithWithdraw(permission, value, withdrawRequest);

        emit SpendRouted(
            permission.account, executor, recipient, PERMISSION_MANAGER.getHash(permission), permission.token, value
        );

        _routeTokens(permission.token, recipient, value);
    }

    /// @notice Approves a permission with the user's signature, spends tokens with an atomic MagicSpend withdraw,
    ///         and forwards them to the recipient — all in a single transaction.
    ///
    /// @dev Same flow as `spendWithWithdrawAndRoute`, but first calls `SpendPermissionManager.approveWithSignature`
    ///      to approve the permission onchain using the user's EIP-712 signature before spending.
    ///
    /// @param permission The spend permission containing account, spender, token, allowance, period,
    ///        start, end, salt, and extraData fields.
    /// @param value The amount of tokens to spend and forward.
    /// @param withdrawRequest The MagicSpend withdraw request to fund the account.
    /// @param signature The user's EIP-712 signature authorizing the permission.
    function spendWithWithdrawAndRouteWithSignature(
        SpendPermissionManager.SpendPermission calldata permission,
        uint160 value,
        MagicSpend.WithdrawRequest memory withdrawRequest,
        bytes calldata signature
    ) external {
        (address executor, address recipient) = _validateAndDecodeExtraData(permission.extraData);

        bool approved = PERMISSION_MANAGER.approveWithSignature(permission, signature);
        if (!approved) revert PermissionApprovalFailed();

        PERMISSION_MANAGER.spendWithWithdraw(permission, value, withdrawRequest);

        emit SpendRouted(
            permission.account, executor, recipient, PERMISSION_MANAGER.getHash(permission), permission.token, value
        );

        _routeTokens(permission.token, recipient, value);
    }

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

    /// @notice Decodes and validates the executor and recipient from `extraData`.
    ///
    /// @dev Reverts if `msg.sender` does not match the decoded executor or if the recipient is the zero address.
    ///
    /// @param extraData The raw `extraData` bytes from a `SpendPermission`.
    ///
    /// @return executor The authorized executor address.
    /// @return recipient The address that will receive the forwarded tokens.
    function _validateAndDecodeExtraData(bytes memory extraData)
        internal
        view
        returns (address executor, address recipient)
    {
        (executor, recipient) = decodeExtraData(extraData);
        if (msg.sender != executor) revert UnauthorizedSender(msg.sender, executor);
        if (recipient == address(0)) revert ZeroAddress();
    }

    /// @notice Transfers tokens to the recipient, branching on native ETH vs ERC-20.
    ///
    /// @param token The token address (ERC-7528 sentinel for native ETH).
    /// @param recipient The address to forward tokens to.
    /// @param value The amount to transfer.
    function _routeTokens(address token, address recipient, uint256 value) internal {
        if (token == NATIVE_TOKEN_ADDRESS) {
            SafeTransferLib.safeTransferETH(payable(recipient), value);
        } else {
            SafeTransferLib.safeTransfer(token, recipient, value);
        }
    }

    /// @notice Constructs a properly formatted `SpendPermission.extraData` payload.
    ///
    /// @dev ABI-encodes two addresses into a 64-byte payload. Reverts if either address is zero.
    ///
    /// @param executor The authorized executor address that will call routing or revocation functions on this contract.
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
