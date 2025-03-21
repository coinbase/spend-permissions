// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MagicSpend} from "magic-spend/MagicSpend.sol";

/**
 * @title ISpendPermissionManager
 * @notice Interface for spend permission managers that handle token spending permissions
 * @dev All spend permission managers must implement these core functions
 */
interface ISpendPermissionManager {
    /// @notice A spend permission for an external entity to be able to spend an account's tokens.
    struct SpendPermission {
        /// @dev Smart account this spend permission is valid for.
        address account;
        /// @dev Entity that can spend `account`'s tokens.
        address spender;
        /// @dev Token address (ERC-7528 native token or ERC-20 contract).
        address token;
        /// @dev Maximum allowed value to spend within each `period`.
        uint160 allowance;
        /// @dev Time duration for resetting used `allowance` on a recurring basis (seconds).
        uint48 period;
        /// @dev Timestamp this spend permission is valid starting at (inclusive, unix seconds).
        uint48 start;
        /// @dev Timestamp this spend permission is valid until (exclusive, unix seconds).
        uint48 end;
        /// @dev Arbitrary data to differentiate unique spend permissions with otherwise identical fields.
        uint256 salt;
        /// @dev Arbitrary data to attach to a spend permission which may be consumed by the `spender`.
        bytes extraData;
    }

    /// @notice Period parameters and spend usage.
    struct PeriodSpend {
        /// @dev Timstamp this period starts at (inclusive, unix seconds).
        uint48 start;
        /// @dev Timestamp this period ends before (exclusive, unix seconds).
        uint48 end;
        /// @dev Accumulated spend amount for the period.
        uint160 spend;
    }

    /// @notice Approve a spend permission via a direct call from the account.
    /// @param spendPermission Details of the spend permission.
    /// @return approved True if spend permission is approved and not revoked.
    function approve(SpendPermission calldata spendPermission) external returns (bool);

    /// @notice Approve a spend permission via a signature from the account.
    /// @param spendPermission Details of the spend permission.
    /// @param signature Signed approval from the user.
    /// @return approved True if spend permission is approved and not revoked.
    function approveWithSignature(SpendPermission calldata spendPermission, bytes calldata signature)
        external
        returns (bool);

    /// @notice Revoke a spend permission to disable its use indefinitely.
    /// @param spendPermission Details of the spend permission.
    function revoke(SpendPermission calldata spendPermission) external;

    /// @notice Revoke a spend permission to disable its use indefinitely.
    /// @param spendPermission Details of the spend permission.
    function revokeAsSpender(SpendPermission calldata spendPermission) external;

    /// @notice Spend tokens using a spend permission, transferring them from `account` to `spender`.
    /// @param spendPermission Details of the spend permission.
    /// @param value Amount of token attempting to spend.
    function spend(SpendPermission memory spendPermission, uint160 value) external;

    /// @notice Spend tokens using a spend permission and atomically call MagicSpend to fund the account.
    /// @param spendPermission Details of the spend permission.
    /// @param value Amount of token attempting to spend.
    /// @param withdrawRequest Request to withdraw tokens from MagicSpend into the account.
    function spendWithWithdraw(
        SpendPermission memory spendPermission,
        uint160 value,
        MagicSpend.WithdrawRequest memory withdrawRequest
    ) external;

    /// @notice Get if a spend permission is approved.
    /// @param spendPermission Details of the spend permission.
    /// @return approved True if spend permission is approved.
    function isApproved(SpendPermission memory spendPermission) external view returns (bool);

    /// @notice Get if a spend permission is revoked.
    /// @param spendPermission Details of the spend permission.
    /// @return revoked True if spend permission is revoked.
    function isRevoked(SpendPermission memory spendPermission) external view returns (bool);

    /// @notice Get if spend permission is approved and not revoked.
    /// @param spendPermission Details of the spend permission.
    /// @return valid True if spend permission is approved and not revoked.
    function isValid(SpendPermission memory spendPermission) external view returns (bool);

    /// @notice Get last updated period for a spend permission.
    /// @param spendPermission Details of the spend permission.
    /// @return lastUpdatedPeriod Last updated period for the spend permission.
    function getLastUpdatedPeriod(SpendPermission memory spendPermission) external view returns (PeriodSpend memory);

    /// @notice Get start, end, and spend of the current period.
    /// @param spendPermission Details of the spend permission
    /// @return currentPeriod Currently active period with cumulative spend (struct)
    function getCurrentPeriod(SpendPermission memory spendPermission) external view returns (PeriodSpend memory);

    /// @notice Hash a SpendPermission struct for signing in accordance with EIP-712
    /// @param spendPermission Details of the spend permission.
    /// @return hash Hash of the spend permission.
    function getHash(SpendPermission memory spendPermission) external view returns (bytes32);

    /// @notice ERC-7528 native token address convention
    function NATIVE_TOKEN() external view returns (address);

    /// @notice MagicSpend singleton address
    function MAGIC_SPEND() external view returns (address);

    /// @notice PublicERC6492Validator contract address
    function PUBLIC_ERC6492_VALIDATOR() external view returns (address);

    /**
     * @dev Emitted when a spend permission is approved
     * @param hash Unique hash representing the spend permission
     * @param spendPermission Details of the spend permission
     */
    event SpendPermissionApproved(bytes32 indexed hash, SpendPermission spendPermission);

    /**
     * @dev Emitted when a spend permission is revoked
     * @param hash Unique hash representing the spend permission
     * @param spendPermission Details of the spend permission
     */
    event SpendPermissionRevoked(bytes32 indexed hash, SpendPermission spendPermission);

    /**
     * @dev Emitted when a spend permission is used
     * @param hash Unique hash representing the spend permission
     * @param account Account that had its tokens spent via the spend permission
     * @param spender Entity that spent `account`'s tokens
     * @param token Address of token spent via the spend permission
     * @param periodSpend Start and end of the current period with the new incremental spend
     */
    event SpendPermissionUsed(
        bytes32 indexed hash,
        address indexed account,
        address indexed spender,
        address token,
        PeriodSpend periodSpend
    );
}
