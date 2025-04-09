// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {ERC165Checker} from "openzeppelin-contracts/contracts/utils/introspection/ERC165Checker.sol";
import {EIP712} from "solady/utils/EIP712.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {IWalletPermit3Utility} from "../interfaces/IWalletPermit3Utility.sol";
import {HooksForwarder} from "./HooksForwarder.sol";
import {PublicERC6492Validator} from "./PublicERC6492Validator.sol";
import {SpendPermission, SpendPermissionBatch} from "./SpendPermission.sol";
/// @title Permit3
///
/// @notice Allow granting permission to external accounts to spend native and ERC-20 tokens.
///
/// @dev Allowance and spend values capped at uint160 (~1e48).
/// @dev Supports ERC-6492 signatures (https://eips.ethereum.org/EIPS/eip-6492).
///
/// @author Coinbase (https://github.com/coinbase/spend-permissions)

contract Permit3 is EIP712 {
    /// @notice Period parameters and spend usage.
    struct PeriodSpend {
        /// @dev Timstamp this period starts at (inclusive, unix seconds).
        uint48 start;
        /// @dev Timestamp this period ends before (exclusive, unix seconds).
        uint48 end;
        /// @dev Accumulated spend amount for the period.
        uint160 spend;
    }

    /// @notice EIP-712 hash of SpendPermission type.
    bytes32 public constant SPEND_PERMISSION_TYPEHASH = keccak256(
        "SpendPermission(address account,address spender,address token,uint160 allowance,uint48 period,uint48 start,uint48 end,uint256 salt,bytes extraData)"
    );

    /// @notice EIP-712 hash of SpendPermissionBatch type.
    bytes32 public constant SPEND_PERMISSION_BATCH_TYPEHASH = keccak256(
        "SpendPermissionBatch(address account,uint48 period,uint48 start,uint48 end,PermissionDetails[] permissions)PermissionDetails(address spender,address token,uint160 allowance,uint256 salt,bytes extraData)"
    );

    /// @notice EIP-712 hash of PermissionDetails type.
    bytes32 public constant PERMISSION_DETAILS_TYPEHASH =
        keccak256("PermissionDetails(address spender,address token,uint160 allowance,uint256 salt,bytes extraData)");

    /// @notice ERC-7528 native token address convention (https://eips.ethereum.org/EIPS/eip-7528).
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice Separated contract for validating signatures and executing ERC-6492 side effects.
    PublicERC6492Validator public immutable PUBLIC_ERC6492_VALIDATOR;

    /// @notice Separated contract for executing hooks.
    HooksForwarder public immutable HOOKS_FORWARDER;

    /// @notice Spend permission is approved.
    mapping(bytes32 hash => bool approved) internal _isApproved;

    /// @notice Spend permission is revoked.
    mapping(bytes32 hash => bool revoked) internal _isRevoked;

    /// @notice Last updated period for a spend permission.
    mapping(bytes32 hash => PeriodSpend) internal _lastUpdatedPeriod;

    /// @notice Spend permission was approved.
    ///
    /// @param hash Unique hash representing the spend permission.
    /// @param spendPermission Details of the spend permission.
    event SpendPermissionApproved(bytes32 indexed hash, SpendPermission spendPermission);

    /// @notice Spend permission was revoked.
    ///
    /// @param hash Unique hash representing the spend permission.
    /// @param spendPermission Details of the spend permission.
    event SpendPermissionRevoked(bytes32 indexed hash, SpendPermission spendPermission);

    /// @notice Spend permission was used.
    ///
    /// @param hash Unique hash representing the spend permission.
    /// @param account Account that had its tokens spent via the spend permission.
    /// @param spender Entity that spent `account`'s tokens.
    /// @param token Address of token spent via the spend permission.
    /// @param periodSpend Start and end of the current period with the new incremental spend (struct).
    event SpendPermissionUsed(
        bytes32 indexed hash, address indexed account, address indexed spender, address token, PeriodSpend periodSpend
    );

    /// @notice Invalid sender for the external call.
    ///
    /// @param sender Expected sender to be valid.
    error InvalidSender(address sender, address expected);

    /// @notice Token is an ERC-721, which is not supported to prevent NFT transfers
    ///
    /// @param token Address of the ERC-721 token contract.
    error ERC721TokenNotSupported(address token);

    /// @notice Invalid signature.
    error InvalidSignature();

    /// @notice Last updated period is different from the expected last updated period.
    error InvalidLastUpdatedPeriod(PeriodSpend actualLastUpdatedPeriod, PeriodSpend expectedLastUpdatedPeriod);

    /// @notice Mismatched accounts for atomically approving and revoking a pair of spend permissions.
    ///
    /// @param firstAccount Account of the first spend permission.
    /// @param secondAccount Account of the second spend permission.
    error MismatchedAccounts(address firstAccount, address secondAccount);

    /// @notice Spend permission batch is empty.
    error EmptySpendPermissionBatch();

    /// @notice Spend permission has zero token address.
    error ZeroToken();

    /// @notice Spend permission has zero spender address.
    error ZeroSpender();

    /// @notice Spend permission has zero allowance.
    error ZeroAllowance();

    /// @notice Spend permission has zero period.
    error ZeroPeriod();

    /// @notice Spend permission start time is not strictly less than end time.
    ///
    /// @param start Timestamp for start of the permission (unix seconds).
    /// @param end Timestamp for end of the permission (unix seconds).
    error InvalidStartEnd(uint48 start, uint48 end);

    /// @notice Attempting to spend zero value.
    error ZeroValue();

    /// @notice Unauthorized spend permission.
    error UnauthorizedSpendPermission();

    /// @notice Spend permission has not started yet.
    ///
    /// @param currentTimestamp Current timestamp (unix seconds).
    /// @param start Timestamp this spend permission is valid starting at (inclusive, unix seconds).
    error BeforeSpendPermissionStart(uint48 currentTimestamp, uint48 start);

    /// @notice Spend permission has already ended.
    ///
    /// @param currentTimestamp Current timestamp (unix seconds).
    /// @param end Timestamp this spend permission is valid until (exclusive, unix seconds).
    error AfterSpendPermissionEnd(uint48 currentTimestamp, uint48 end);

    /// @notice Spend value exceeds max size of uint160.
    ///
    /// @param value Spend value that triggered overflow.
    error SpendValueOverflow(uint256 value);

    /// @notice Spend value exceeds spend permission allowance.
    ///
    /// @param value Spend value that exceeded allowance.
    /// @param allowance Allowance value that was exceeded.
    error ExceededSpendPermission(uint256 value, uint256 allowance);

    /// @notice Contract received an unexpected amount of native token.
    error UnexpectedReceiveAmount(uint256 received, uint256 expected);

    /// @notice Mapping from account address to their registered utility contract
    mapping(address => address) public accountToUtility;

    /// @notice The current permission hash being processed
    bytes32 /*transient*/ private _currentPermissionHash;

    /// @notice The current token being processed
    address /*transient*/ private _currentToken;

    /// @notice The current account being processed
    address /*transient*/ private _currentAccount;

    /// @notice Event emitted when a utility contract is registered for an account
    event UtilityRegistered(address indexed account, address indexed utility);

    /// @notice Error thrown when trying to register a utility without proper authorization
    error UnauthorizedRegistration();

    /// @notice Require a specific sender for an external call.
    /// @param sender Expected sender for call to be valid.
    modifier requireSender(address sender) {
        if (msg.sender != sender) revert InvalidSender(msg.sender, sender);
        _;
    }

    /// @notice Deploy Permit3 and set immutable dependency contracts.
    ///
    /// @param publicERC6492Validator PublicERC6492Validator contract.
    constructor(PublicERC6492Validator publicERC6492Validator) {
        PUBLIC_ERC6492_VALIDATOR = publicERC6492Validator;
        HOOKS_FORWARDER = new HooksForwarder(address(this));
    }

    /// @notice Allow the contract to receive native token transfers.
    receive() external payable {}

    /// @notice Approve a spend permission via a direct call from the account.
    ///
    /// @dev Can only be called by the account of a spend permission.
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
    /// @dev Compatible with ERC-6492 signatures including side effects.
    ///
    /// @param spendPermission Details of the spend permission.
    /// @param signature Signed approval from the user.
    ///
    /// @return approved True if spend permission is approved and not revoked.
    function approveWithSignature(SpendPermission calldata spendPermission, bytes calldata signature)
        external
        returns (bool)
    {
        // TODO read transient storage and revert if nonzero to prevent reentrancy
        bytes32 hash = getHash(spendPermission);
        _currentPermissionHash = hash;
        _currentToken = spendPermission.token;
        _currentAccount = spendPermission.account;

        // validate signature over spend permission data, deploying or preparing account if necessary
        if (!PUBLIC_ERC6492_VALIDATOR.isValidSignatureNowAllowSideEffects(spendPermission.account, hash, signature)) {
            revert InvalidSignature();
        }

        // Clear transient storage
        _currentPermissionHash = bytes32(0);
        _currentToken = address(0);
        _currentAccount = address(0);

        return _approve(spendPermission);
    }

    /// @notice Approve a spend permission batch via a signature from the account.
    ///
    /// @dev Compatible with ERC-6492 signatures including side effects.
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
            !PUBLIC_ERC6492_VALIDATOR.isValidSignatureNowAllowSideEffects(
                spendPermissionBatch.account, getBatchHash(spendPermissionBatch), signature
            )
        ) {
            revert InvalidSignature();
        }

        // loop through each spend permission in the batch and approve it
        bool allApproved = true;
        uint256 batchLen = spendPermissionBatch.permissions.length;
        for (uint256 i; i < batchLen; i++) {
            // approve each spend permission in the batch, surfacing if any return false (are already revoked)
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

    /// @notice Approve a spend permission while revoking another if its last updated period matches an expected value.
    ///
    /// @dev Comparing the revoked spend permission's last updated period mitigates frontrunning with further spend.
    /// @dev The accounts of the spend permissions must match, but all other fields can differ.
    /// @dev Reverts if not called by the account of the spend permissions.
    ///
    /// @param permissionToApprove Details of the spend permission to approve.
    /// @param permissionToRevoke Details of the spend permission to revoke.
    /// @param expectedLastUpdatedPeriod Expected last updated period for the spend permission being revoked.
    ///
    /// @return approved True if new spend permission is approved and not revoked.
    function approveWithRevoke(
        SpendPermission calldata permissionToApprove,
        SpendPermission calldata permissionToRevoke,
        PeriodSpend calldata expectedLastUpdatedPeriod
    ) external requireSender(permissionToApprove.account) returns (bool) {
        // require both spend permissions apply to the same account
        if (permissionToApprove.account != permissionToRevoke.account) {
            revert MismatchedAccounts(permissionToApprove.account, permissionToRevoke.account);
        }

        // validate that no spending has occurred since the expected last updated period
        PeriodSpend memory lastUpdatedPeriod = getLastUpdatedPeriod(permissionToRevoke);
        if (
            lastUpdatedPeriod.spend != expectedLastUpdatedPeriod.spend
                || lastUpdatedPeriod.start != expectedLastUpdatedPeriod.start
                || lastUpdatedPeriod.end != expectedLastUpdatedPeriod.end
        ) {
            revert InvalidLastUpdatedPeriod(lastUpdatedPeriod, expectedLastUpdatedPeriod);
        }

        // revoke old and approve new spend permissions
        _revoke(permissionToRevoke);
        return _approve(permissionToApprove);
    }

    /// @notice Revoke a spend permission to disable its use indefinitely.
    ///
    /// @dev Reverts if not called by the account of the spend permission.
    ///
    /// @param spendPermission Details of the spend permission.
    function revoke(SpendPermission calldata spendPermission) external requireSender(spendPermission.account) {
        _revoke(spendPermission);
    }

    /// @notice Revoke a spend permission to disable its use indefinitely.
    ///
    /// @dev Reverts if not called by the spender of the spend permission.
    ///
    /// @param spendPermission Details of the spend permission.
    function revokeAsSpender(SpendPermission calldata spendPermission)
        external
        requireSender(spendPermission.spender)
    {
        _revoke(spendPermission);
    }

    /// NO HOOKS VERSION
    /// @notice Spend tokens using a spend permission, transferring them from `account` to `spender`.
    ///
    /// @dev Reverts if not called by the spender of the spend permission.
    /// @dev Reverts if using spend permission or completing token transfer fail.
    ///
    /// @param spendPermission Details of the spend permission.
    /// @param value Amount of token attempting to spend.
    function spend(SpendPermission memory spendPermission, uint256 value)
        external
        requireSender(spendPermission.spender)
    {
        _useSpendPermission(spendPermission, value);

        if (spendPermission.token == NATIVE_TOKEN) {
            if (accountToUtility[spendPermission.account] != address(0)) {
                // If the account has a registered utility, call the utility's spendNativeToken function
                IWalletPermit3Utility(accountToUtility[spendPermission.account]).spendNativeToken(
                    spendPermission.account, value
                );
            }
            // transfer native token to spender using balance, which will revert if funds are not actually available
            SafeTransferLib.safeTransferETH(payable(spendPermission.spender), value);
        } else {
            // transfer erc20 tokens to spender using allowance, which will revert if transfer fails
            // Allowance should be set already, by independent call in case of EOA, or by the 6492 signature flow in the
            // case of a smart wallet.
            SafeTransferLib.safeTransferFrom(
                spendPermission.token, spendPermission.account, spendPermission.spender, value
            );
        }
    }

    /// @notice Spend tokens using a spend permission, transferring them from `account` to `spender`.
    ///
    /// @dev Reverts if not called by the spender of the spend permission.
    /// @dev Reverts if using spend permission or completing token transfer fail.
    ///
    /// @param spendPermission Details of the spend permission.
    /// @param value Amount of token attempting to spend.
    function spend(SpendPermission memory spendPermission, uint256 value, address hooks, bytes calldata hookData)
        external
        requireSender(spendPermission.spender)
    {
        if (hooks != address(0)) {
            HOOKS_FORWARDER.preSpend(spendPermission, value, hooks, hookData);
        }

        _useSpendPermission(spendPermission, value);

        if (spendPermission.token == NATIVE_TOKEN) {
            // transfer native token to spender using balance, which will revert if funds are not actually available
            SafeTransferLib.safeTransferETH(payable(spendPermission.spender), value);
        } else {
            // transfer erc20 tokens to spender using allowance, which will revert if transfer fails
            // if allowance does not exist, the preSpend hook will need to set it
            SafeTransferLib.safeTransferFrom(
                spendPermission.token, spendPermission.account, spendPermission.spender, value
            );
        }

        if (hooks != address(0)) {
            HOOKS_FORWARDER.postSpend(spendPermission, value, hooks, hookData);
        }
    }

    /// @notice Get if a spend permission is approved.
    ///
    /// @param spendPermission Details of the spend permission.
    ///
    /// @return approved True if spend permission is approved.
    function isApproved(SpendPermission memory spendPermission) public view returns (bool) {
        return _isApproved[getHash(spendPermission)];
    }

    /// @notice Get if a spend permission is revoked.
    ///
    /// @param spendPermission Details of the spend permission.
    ///
    /// @return revoked True if spend permission is revoked.
    function isRevoked(SpendPermission memory spendPermission) public view returns (bool) {
        return _isRevoked[getHash(spendPermission)];
    }

    /// @notice Get if spend permission is approved and not revoked.
    ///
    /// @param spendPermission Details of the spend permission.
    ///
    /// @return valid True if spend permission is approved and not revoked.
    function isValid(SpendPermission memory spendPermission) public view returns (bool) {
        bytes32 hash = getHash(spendPermission);
        return !_isRevoked[hash] && _isApproved[hash];
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
    /// @dev Period boundaries are at fixed intervals of [start + n * period, min(end, start + (n + 1) * period) - 1]
    ///
    /// @param spendPermission Details of the spend permission
    ///
    /// @return currentPeriod Currently active period with cumulative spend (struct)
    function getCurrentPeriod(SpendPermission memory spendPermission) public view returns (PeriodSpend memory) {
        // check current timestamp is within spend permission time range
        uint48 currentTimestamp = uint48(block.timestamp);
        if (currentTimestamp < spendPermission.start) {
            revert BeforeSpendPermissionStart(currentTimestamp, spendPermission.start);
        } else if (currentTimestamp >= spendPermission.end) {
            revert AfterSpendPermissionEnd(currentTimestamp, spendPermission.end);
        }

        PeriodSpend memory lastUpdatedPeriod = _lastUpdatedPeriod[getHash(spendPermission)];

        // last period exists if spend is non-zero
        bool lastPeriodExists = lastUpdatedPeriod.spend != 0;

        // last period still active if current timestamp within [start, end - 1] range.
        bool lastPeriodStillActive = currentTimestamp < lastUpdatedPeriod.end;

        // return last period if exists and still active, otherwise compute new period with no spend
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
                    SPEND_PERMISSION_TYPEHASH,
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

    /// @notice Hash a SpendPermissionBatch struct for signing in accordance with EIP-712
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
                    SPEND_PERMISSION_BATCH_TYPEHASH,
                    spendPermissionBatch.account,
                    spendPermissionBatch.period,
                    spendPermissionBatch.start,
                    spendPermissionBatch.end,
                    keccak256(abi.encodePacked(permissionDetailsHashes))
                )
            )
        );
    }

    /// @notice Registers a utility contract for an account
    /// @dev The account must have called setTransientAccount first
    /// @param utility The utility contract to register
    function registerPermit3Utility(address utility) external {
        // Register the utility
        accountToUtility[msg.sender] = utility;
        emit UtilityRegistered(msg.sender, utility);
    }

    /// @notice Approve a spend permission.
    ///
    /// @dev Early returns false if permission is revoked, stopping unusable approval.
    /// @dev Only emits approval event once on first approval.
    ///
    /// @param spendPermission Details of the spend permission.
    ///
    /// @return approved True if spend permission is approved and not revoked.
    function _approve(SpendPermission memory spendPermission) internal returns (bool) {
        // check token is non-zero
        if (spendPermission.token == address(0)) revert ZeroToken();

        // check token is not an ERC-721
        if (spendPermission.token != NATIVE_TOKEN) {
            if (ERC165Checker.supportsInterface(spendPermission.token, type(IERC721).interfaceId)) {
                revert ERC721TokenNotSupported(spendPermission.token);
            }
        }

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
    /// @dev Only emits revoked event once on first revocation.
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

        // check spend permission is approved and not revoked
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

        // update total spend for current period and emit event for incremental spend
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

    /// @notice Get EIP-712 domain name and version.
    ///
    /// @return name Name string for the EIP-712 domain.
    /// @return version Version string for the EIP-712 domain.
    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        name = "Permit3";
        version = "1";
    }

    /// @notice Get the current account being processed
    /// @return The address of the current account being processed
    function getCurrentAccount() external view returns (address) {
        return _currentAccount;
    }

    /// @notice Get the current permission hash being processed
    /// @return The hash of the current permission being processed
    function getCurrentPermissionHash() external view returns (bytes32) {
        return _currentPermissionHash;
    }

    /// @notice Get the current token being processed
    /// @return The address of the current token being processed
    function getCurrentToken() external view returns (address) {
        return _currentToken;
    }
}
