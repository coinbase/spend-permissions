// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1271} from "openzeppelin-contracts/contracts/interfaces/IERC1271.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";
import {EIP712} from "solady/utils/EIP712.sol";

import {PublicERC6492Validator} from "./PublicERC6492Validator.sol";

/// @title SpendPermissionManager
///
/// @notice Allow spending native and ERC-20 tokens from a `CoinbaseSmartWalletV1` with a spend permission.
///
/// @dev Allowance and spend values capped at uint160 ~ 1e48.
///
/// @author Coinbase (https://github.com/coinbase/spend-permissions)
contract SpendPermissionManager is EIP712 {
    using SafeERC20 for IERC20;

    /// @notice A spend permission for an external entity to be able to spend an account's tokens.
    struct SpendPermission {
        /// @dev Smart account this spend permission is valid for.
        address account;
        /// @dev Entity that can spend `account`'s tokens.
        address spender;
        /// @dev Token address (ERC-7528 native token address or ERC-20 contract).
        address token;
        /// @dev Maximum allowed value to spend within each `period`.
        uint160 allowance;
        /// @dev Time duration for resetting used `allowance` on a recurring basis (seconds).
        uint48 period;
        /// @dev Timestamp this spend permission is valid after (inclusive, unix seconds).
        uint48 start;
        /// @dev Timestamp this spend permission is valid until (exclusive, unix seconds).
        uint48 end;
        /// @dev An arbitrary salt to differentiate unique spend permissions with otherwise identical data.
        uint256 salt;
        /// @dev Arbitrary data to include in the signature.
        bytes extraData;
    }

    struct SpendPermissionBatch {
        /// @dev Smart account this spend permission is valid for.
        address account;
        /// @dev Time duration for resetting used allowance on a recurring basis (seconds).
        uint48 period;
        /// @dev Timestamp this spend permission is valid after (inclusive, unix seconds).
        uint48 start;
        /// @dev Timestamp this spend permission is valid until (exclusive, unix seconds).
        uint48 end;
        /// @dev Array of `PermissionDetails` structs defining properties that apply per-permission.
        PermissionDetails[] permissions;
    }

    struct PermissionDetails {
        /// @dev Entity that can spend user funds.
        address spender;
        /// @dev Token address (ERC-7528 ether address or ERC-20 contract).
        address token;
        /// @dev Maximum allowed value to spend within a recurring period.
        uint160 allowance;
        /// @dev An arbitrary salt to differentiate unique spend permissions with otherwise identical data.
        uint256 salt;
        /// @dev Arbitrary data to include in the signature.
        bytes extraData;
    }

    /// @notice Period parameters and spend usage.
    struct PeriodSpend {
        /// @dev Start time of the period (unix seconds).
        uint48 start;
        /// @dev End time of the period (unix seconds).
        uint48 end;
        /// @dev Accumulated spend amount for period.
        uint160 spend;
    }

    /// @notice Separated contract for validating signatures and executing ERC-6492 side effects
    ///         (https://eips.ethereum.org/EIPS/eip-6492).
    PublicERC6492Validator public immutable publicERC6492Validator;

    bytes32 public constant PERMISSION_TYPEHASH = keccak256(
        "SpendPermission(address account,address spender,address token,uint160 allowance,uint48 period,uint48 start,uint48 end,uint256 salt,bytes extraData)"
    );

    bytes32 public constant PERMISSION_BATCH_TYPEHASH = keccak256(
        "SpendPermissionBatch(address account,uint48 period,uint48 start,uint48 end,PermissionDetails[] permissions)PermissionDetails(address spender,address token,uint160 allowance,uint256 salt,bytes extraData)"
    );

    bytes32 public constant PERMISSION_DETAILS_TYPEHASH =
        keccak256("PermissionDetails(address spender,address token,uint160 allowance,uint256 salt,bytes extraData)");

    /// @notice ERC-7528 address convention for native token (https://eips.ethereum.org/EIPS/eip-7528).
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice Spend permission is revoked.
    mapping(bytes32 hash => bool revoked) public isRevoked;

    /// @notice Spend permission is approved.
    mapping(bytes32 hash => bool approved) public isApproved;

    /// @notice Last updated period for a spend permission.
    mapping(bytes32 hash => PeriodSpend) internal _lastUpdatedPeriod;

    /// @notice Invalid sender for the external call.
    ///
    /// @param sender Expected sender to be valid.
    error InvalidSender(address sender, address expected);

    /// @notice Invalid signature.
    error InvalidSignature();

    /// @notice Last updated period is different from the expected last updated period.
    error InvalidLastUpdatedPeriod(PeriodSpend actualLastUpdatedPeriod, PeriodSpend expectedLastUpdatedPeriod);

    /// @notice Mismatched accounts for spend permission.
    ///
    /// @param firstAccount First account in the spend permission.
    /// @param secondAccount Second account in the spend permission.
    error MismatchedAccounts(address firstAccount, address secondAccount);

    /// @notice Empty batch of spend permissions.
    error EmptySpendPermissionBatch();

    /// @notice Spend Permission has zero token address.
    error ZeroToken();

    /// @notice Spend Permission has zero spender address.
    error ZeroSpender();

    /// @notice Spend Permission has zero allowance.
    error ZeroAllowance();

    /// @notice Spend Permission has zero period.
    error ZeroPeriod();

    /// @notice Spend Permission start time is not strictly less than end time.
    ///
    /// @param start Unix timestamp (seconds) for start of the permission.
    /// @param end Unix timestamp (seconds) for end of the permission.
    error InvalidStartEnd(uint48 start, uint48 end);

    /// @notice Attempting to spend zero value.
    error ZeroValue();

    /// @notice Unauthorized spend permission.
    error UnauthorizedSpendPermission();

    /// @notice Recurring period has not started yet.
    ///
    /// @param currentTimestamp Current timestamp (unix seconds).
    /// @param start Timestamp this spend permission is valid starting at (unix seconds).
    error BeforeSpendPermissionStart(uint48 currentTimestamp, uint48 start);

    /// @notice Recurring period has already ended.
    ///
    /// @param currentTimestamp Current timestamp (unix seconds).
    /// @param end Timestamp this spend permission is valid until (exclusive, unix seconds).
    error AfterSpendPermissionEnd(uint48 currentTimestamp, uint48 end);

    /// @notice Spend value exceeds max size of uint160.
    ///
    /// @param value Spend value that triggered overflow.
    error SpendValueOverflow(uint256 value);

    /// @notice Spend value exceeds spend permission.
    ///
    /// @param value Spend value that exceeded allowance.
    /// @param allowance Allowance value that was exceeded.
    error ExceededSpendPermission(uint256 value, uint256 allowance);

    /// @notice SpendPermission was approved via transaction.
    ///
    /// @param hash The unique hash representing the spend permission.
    /// @param spendPermission Details of the spend permission.
    event SpendPermissionApproved(bytes32 indexed hash, SpendPermission spendPermission);

    /// @notice SpendPermission was revoked.
    ///
    /// @param hash The unique hash representing the spend permission.
    /// @param spendPermission Details of the spend permission.
    event SpendPermissionRevoked(bytes32 indexed hash, SpendPermission spendPermission);

    /// @notice Register native or ERC-20 token spend for a spend permission period.
    ///
    /// @param hash Hash of the spend permission.
    /// @param account Account that had its tokens spent via a spend permission.
    /// @param spender Entity that spent `account`'s tokens.
    /// @param token Address of token spent via a spend permission.
    /// @param periodSpend Start and end of the current period with marginal new spend (struct).
    event SpendPermissionUsed(
        bytes32 indexed hash, address indexed account, address indexed spender, address token, PeriodSpend periodSpend
    );

    /// @notice Construct a new SpendPermissionManager contract.
    ///
    /// @dev The PublicERC6492Validator contract is used to validate ERC-6492 signatures.
    ///
    /// @param _publicERC6492Validator Address of the PublicERC6492Validator contract.
    constructor(PublicERC6492Validator _publicERC6492Validator) {
        publicERC6492Validator = _publicERC6492Validator;
    }

    /// @notice Require a specific sender for an external call.
    ///
    /// @param sender Expected sender for call to be valid.
    modifier requireSender(address sender) {
        if (msg.sender != sender) revert InvalidSender(msg.sender, sender);
        _;
    }

    /// @notice Approve a spend permission via a direct call from the account.
    ///
    /// @dev Can only be called by the `account` of a permission.
    ///
    /// @param spendPermission Details of the spend permission.
    ///
    /// @return approved True if spend permission is approved and not revoked.
    function approve(SpendPermission calldata spendPermission)
        external
        requireSender(spendPermission.account)
        returns (bool)
    {
        return _approve(spendPermission);
    }

    /// @notice Approve a spend permission via a signature from the account.
    ///
    /// @dev Compatible with ERC-6492 signatures including side effects (https://eips.ethereum.org/EIPS/eip-6492).
    ///
    /// @param spendPermission Details of the spend permission.
    /// @param signature Signed approval from the user.
    ///
    /// @return approved True if spend permission is approved and not revoked.
    function approveWithSignature(SpendPermission calldata spendPermission, bytes calldata signature)
        external
        returns (bool)
    {
        // validate signature over spend permission data, deploying or preparing account if necessary
        if (
            !publicERC6492Validator.isValidSignatureNowAllowSideEffects(
                spendPermission.account, getHash(spendPermission), signature
            )
        ) {
            revert InvalidSignature();
        }
        return _approve(spendPermission);
    }

    /// @notice Approve a spend permission batch via a signature from the account.
    ///
    /// @dev Compatible with ERC-6492 signatures including side effects (https://eips.ethereum.org/EIPS/eip-6492).
    /// @dev Does not enforce uniqueness of permissions within a batch, allowing duplicate idempotent approvals.
    ///
    /// @param spendPermissionBatch Details of the spend permission batch.
    /// @param signature Signed approval from the user.
    ///
    /// @return allApproved True if all spend permissions in the batch are approved and not revoked.
    function approveBatchWithSignature(SpendPermissionBatch memory spendPermissionBatch, bytes calldata signature)
        external
        returns (bool)
    {
        // validate signature over spend permission batch data
        if (
            !publicERC6492Validator.isValidSignatureNowAllowSideEffects(
                spendPermissionBatch.account, getBatchHash(spendPermissionBatch), signature
            )
        ) {
            revert InvalidSignature();
        }

        // loop through each spend permission in the batch and approve it
        bool allApproved = true;
        uint256 batchLen = spendPermissionBatch.permissions.length;
        for (uint256 i; i < batchLen; i++) {
            // approve each spend permission in the batch, capturing a false return to surface if any return false (are
            // already revoked)
            if (
                !_approve(
                    SpendPermission({
                        account: spendPermissionBatch.account,
                        spender: spendPermissionBatch.permissions[i].spender,
                        token: spendPermissionBatch.permissions[i].token,
                        allowance: spendPermissionBatch.permissions[i].allowance,
                        period: spendPermissionBatch.period,
                        start: spendPermissionBatch.start,
                        end: spendPermissionBatch.end,
                        salt: spendPermissionBatch.permissions[i].salt,
                        extraData: spendPermissionBatch.permissions[i].extraData
                    })
                )
            ) {
                allApproved = false;
            }
        }
        return allApproved;
    }

    /// @notice Spend tokens using a spend permission, transferring them from `account` to `spender`.
    ///
    /// @dev Can only be called by the `spender` of a permission.
    ///
    /// @param spendPermission Details of the spend permission.
    /// @param value Amount of token attempting to spend.
    function spend(SpendPermission memory spendPermission, uint160 value)
        external
        requireSender(spendPermission.spender)
    {
        _useSpendPermission(spendPermission, value);
        _transferFrom(spendPermission.token, spendPermission.account, spendPermission.spender, value);
    }

    /// @notice Approves a permission while revoking another if its last update has not changed.
    ///
    /// @dev Enforces that the last updated period of the permission being revoked matches the last valid updated period
    ///      submitted as an argument. This is to prevent frontrunning `approveWithRevoke` with additional last-minute
    ///      spends.
    /// @dev The `account` of the permissions must match, but the remaining fields can differ.
    /// @dev Can only be called by the `account` of a permission.
    ///
    /// @param permissionToApprove Details of the spend permission to approve.
    /// @param permissionToRevoke Details of the spend permission to revoke.
    /// @param lastValidUpdatedPeriod Last valid updated period for the spend permission being revoked.
    ///
    /// @return approved True if new spend permission is approved and not revoked.
    function approveWithRevoke(
        SpendPermission calldata permissionToApprove,
        SpendPermission calldata permissionToRevoke,
        PeriodSpend calldata lastValidUpdatedPeriod
    ) external requireSender(permissionToApprove.account) returns (bool) {
        // require both spend permissions apply to the same account
        if (permissionToApprove.account != permissionToRevoke.account) {
            revert MismatchedAccounts(permissionToApprove.account, permissionToRevoke.account);
        }
        // validate that no spending has occurred since the last updated period passed to the function
        PeriodSpend memory lastUpdatedPeriod = getLastUpdatedPeriod(permissionToRevoke);
        if (
            lastUpdatedPeriod.spend != lastValidUpdatedPeriod.spend
                || lastUpdatedPeriod.start != lastValidUpdatedPeriod.start
                || lastUpdatedPeriod.end != lastValidUpdatedPeriod.end
        ) {
            revert InvalidLastUpdatedPeriod(lastUpdatedPeriod, lastValidUpdatedPeriod);
        }
        // revoke old and approve new spend permissions
        _revoke(permissionToRevoke);
        return _approve(permissionToApprove);
    }

    /// @notice Revoke a spend permission to disable its use indefinitely.
    ///
    /// @dev Can only be called by the `account` of a permission.
    ///
    /// @param spendPermission Details of the spend permission.
    function revoke(SpendPermission calldata spendPermission) external requireSender(spendPermission.account) {
        _revoke(spendPermission);
    }

    /// @notice Revoke a spend permission to disable its use indefinitely.
    ///
    /// @dev Can only be called by the `spender` of a permission.
    ///
    /// @param spendPermission Details of the spend permission.
    function spenderRevoke(SpendPermission calldata spendPermission) external requireSender(spendPermission.spender) {
        _revoke(spendPermission);
    }

    /// @notice Hash a SpendPermission struct for signing in accordance with EIP-712
    ///         (https://eips.ethereum.org/EIPS/eip-712).
    ///
    /// @param spendPermission Details of the spend permission.
    ///
    /// @return hash Hash of the spend permission.
    function getHash(SpendPermission memory spendPermission) public view returns (bytes32) {
        return _hashTypedData(
            keccak256(
                abi.encode(
                    PERMISSION_TYPEHASH,
                    spendPermission.account,
                    spendPermission.spender,
                    spendPermission.token,
                    spendPermission.allowance,
                    spendPermission.period,
                    spendPermission.start,
                    spendPermission.end,
                    spendPermission.salt,
                    keccak256(spendPermission.extraData)
                )
            )
        );
    }

    /// @notice Hash a SpendPermissionBatch struct for signing in accordance with EIP-712.
    ///         (https://eips.ethereum.org/EIPS/eip-712).
    ///
    /// @dev Reverts if the batch is empty.
    ///
    /// @param spendPermissionBatch Details of the spend permission batch.
    ///
    /// @return hash Hash of the spend permission batch.
    function getBatchHash(SpendPermissionBatch memory spendPermissionBatch) public view returns (bytes32) {
        // check batch is non-empty
        uint256 permissionDetailsLen = spendPermissionBatch.permissions.length;
        if (permissionDetailsLen == 0) revert EmptySpendPermissionBatch();

        // loop over permission details to aggregate inner struct hashes
        bytes32[] memory permissionDetailsHashes = new bytes32[](permissionDetailsLen);
        for (uint256 i; i < permissionDetailsLen; i++) {
            permissionDetailsHashes[i] = keccak256(
                abi.encode(
                    PERMISSION_DETAILS_TYPEHASH,
                    spendPermissionBatch.permissions[i].spender,
                    spendPermissionBatch.permissions[i].token,
                    spendPermissionBatch.permissions[i].allowance,
                    spendPermissionBatch.permissions[i].salt,
                    keccak256(spendPermissionBatch.permissions[i].extraData)
                )
            );
        }

        return _hashTypedData(
            keccak256(
                abi.encode(
                    PERMISSION_BATCH_TYPEHASH,
                    spendPermissionBatch.account,
                    spendPermissionBatch.period,
                    spendPermissionBatch.start,
                    spendPermissionBatch.end,
                    keccak256(abi.encodePacked(permissionDetailsHashes))
                )
            )
        );
    }

    /// @notice Return if spend permission is approved and not revoked.
    ///
    /// @param spendPermission Details of the spend permission.
    ///
    /// @return approved True if spend permission is approved and not revoked.
    function isValid(SpendPermission memory spendPermission) public view returns (bool) {
        bytes32 hash = getHash(spendPermission);
        return !isRevoked[hash] && isApproved[hash];
    }

    /// @notice Get last updated period for a spend permission.
    ///
    /// @param spendPermission Details of the spend permission.
    ///
    /// @return lastUpdatedPeriod Last updated period for the spend permission.
    function getLastUpdatedPeriod(SpendPermission memory spendPermission) public view returns (PeriodSpend memory) {
        return _lastUpdatedPeriod[getHash(spendPermission)];
    }

    /// @notice Get start, end, and spend of the current period.
    ///
    /// @dev Reverts if spend permission has not started or has already ended.
    /// @dev Period boundaries are at fixed intervals of [start + n * period, min(end, start + (n + 1) * period) - 1].
    ///
    /// @param spendPermission Details of the spend permission.
    ///
    /// @return currentPeriod Currently active period with cumulative spend (struct).
    function getCurrentPeriod(SpendPermission memory spendPermission) public view returns (PeriodSpend memory) {
        // check current timestamp is within spend permission time range
        uint48 currentTimestamp = uint48(block.timestamp);
        if (currentTimestamp < spendPermission.start) {
            revert BeforeSpendPermissionStart(currentTimestamp, spendPermission.start);
        } else if (currentTimestamp >= spendPermission.end) {
            revert AfterSpendPermissionEnd(currentTimestamp, spendPermission.end);
        }

        // return last period if still active, otherwise compute new active period start time with no spend
        PeriodSpend memory lastUpdatedPeriod = _lastUpdatedPeriod[getHash(spendPermission)];

        // last period exists if spend is non-zero
        bool lastPeriodExists = lastUpdatedPeriod.spend != 0;

        // last period still active if current timestamp within [start, end - 1] range.
        bool lastPeriodStillActive = currentTimestamp < lastUpdatedPeriod.end;

        if (lastPeriodExists && lastPeriodStillActive) {
            return lastUpdatedPeriod;
        } else {
            // last active period does not exist or is outdated, determine current period

            // current period progress is remainder of time since first recurring period mod reset period
            uint48 currentPeriodProgress = (currentTimestamp - spendPermission.start) % spendPermission.period;

            // current period start is progress duration before current time
            uint48 start = currentTimestamp - currentPeriodProgress;

            // current period end will overflow if period is sufficiently large
            bool endOverflow = uint256(start) + uint256(spendPermission.period) > spendPermission.end;

            // end is one period after start or spend permission's end if overflow
            uint48 end = endOverflow ? spendPermission.end : start + spendPermission.period;

            return PeriodSpend({start: start, end: end, spend: 0});
        }
    }

    /// @notice Approve spend permission.
    ///
    /// @dev Emits a `SpendPermissionApproved` event if the spend permission is newly approved and not already revoked.
    ///
    /// @param spendPermission Details of the spend permission.
    ///
    /// @return approved True if spend permission is approved and not revoked.
    function _approve(SpendPermission memory spendPermission) internal returns (bool) {
        // check token is non-zero
        if (spendPermission.token == address(0)) revert ZeroToken();

        // check spender is non-zero
        if (spendPermission.spender == address(0)) revert ZeroSpender();

        // check period non-zero
        if (spendPermission.period == 0) revert ZeroPeriod();

        // check allowance non-zero
        if (spendPermission.allowance == 0) revert ZeroAllowance();

        // check start is strictly before end
        if (spendPermission.start >= spendPermission.end) {
            revert InvalidStartEnd(spendPermission.start, spendPermission.end);
        }

        bytes32 hash = getHash(spendPermission);

        // return false early if spend permission is already revoked
        if (_isRevoked[hash]) return false;

        // return early if spend permission is already approved
        if (_isApproved[hash]) return true;

        _isApproved[hash] = true;
        emit SpendPermissionApproved(hash, spendPermission);
        return true;
    }

    /// @notice Revoke a spend permission.
    ///
    /// @dev Emits a `SpendPermissionRevoked` event if the spend permission is newly revoked.
    ///
    /// @param spendPermission Details of the spend permission.
    ///
    /// @return revoked True if spend permission is revoked.
    function _revoke(SpendPermission memory spendPermission) internal returns (bool) {
        bytes32 hash = getHash(spendPermission);
        // return early if spend permission is already revoked
        if (_isRevoked[hash]) return true;
        _isRevoked[hash] = true;
        emit SpendPermissionRevoked(hash, spendPermission);
        return true;
    }

    /// @notice Use a spend permission.
    ///
    /// @param spendPermission Details of the spend permission.
    /// @param value Amount of token attempting to spend (wei).
    function _useSpendPermission(SpendPermission memory spendPermission, uint256 value) internal {
        // check value is non-zero
        if (value == 0) revert ZeroValue();

        // require spend permission is approved and not revoked
        if (!isValid(spendPermission)) revert UnauthorizedSpendPermission();

        PeriodSpend memory currentPeriod = getCurrentPeriod(spendPermission);
        uint256 totalSpend = value + uint256(currentPeriod.spend);

        // check total spend value does not overflow max value
        if (totalSpend > type(uint160).max) revert SpendValueOverflow(totalSpend);

        // check total spend value does not exceed spend permission
        if (totalSpend > spendPermission.allowance) {
            revert ExceededSpendPermission(totalSpend, spendPermission.allowance);
        }

        bytes32 hash = getHash(spendPermission);

        // save new spend for active period
        currentPeriod.spend = uint160(totalSpend);
        _lastUpdatedPeriod[hash] = currentPeriod;
        emit SpendPermissionUsed(
            hash,
            spendPermission.account,
            spendPermission.spender,
            spendPermission.token,
            PeriodSpend(currentPeriod.start, currentPeriod.end, uint160(value))
        );
    }

    /// @notice Transfer assets from an account to a recipient.
    ///
    /// @dev Uses `safeTransferFrom` for ERC-20 tokens to enforce revert on failure.
    ///
    /// @param token Address of the token contract.
    /// @param account Address of the user account.
    /// @param recipient Address of the token recipient.
    /// @param value Amount of tokens to transfer.
    function _transferFrom(address token, address account, address recipient, uint256 value) internal {
        // transfer tokens from account to recipient
        if (token == NATIVE_TOKEN) {
            _execute({account: account, target: recipient, value: value, data: hex""});
            return;
        }
        // if ERC-20 token, set allowance for this contract to spend on behalf of account
        _execute({
            account: account,
            target: token,
            value: 0,
            data: abi.encodeWithSelector(IERC20.approve.selector, address(this), value)
        });

        // use ERC-20 allowance to transfer from account to recipient
        // safeTransferFrom will revert if transfer fails, regardless of ERC-20 implementation
        IERC20(token).safeTransferFrom(account, recipient, value);
    }

    /// @notice Execute a single call on an account.
    ///
    /// @param account Address of the user account.
    /// @param target Address of the target contract.
    /// @param value Amount of native token to send in call.
    /// @param data Bytes data to send in call.
    function _execute(address account, address target, uint256 value, bytes memory data) internal virtual {
        CoinbaseSmartWallet(payable(account)).execute({target: target, value: value, data: data});
    }

    /// @notice Return EIP-712 domain name and version.
    ///
    /// @return name Name string for the EIP-712 domain.
    /// @return version Version string for the EIP-712 domain.
    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        name = "Spend Permission Manager";
        version = "1";
    }
}
