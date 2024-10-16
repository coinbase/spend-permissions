// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC1271} from "openzeppelin-contracts/contracts/interfaces/IERC1271.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";
import {EIP712} from "solady/utils/EIP712.sol";
import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";

/// @title SpendPermissionManager
///
/// @notice Allow spending native and ERC-20 tokens with a spend permission.
///
/// @dev Allowance and spend values capped at uint160 ~ 1e48.
///
/// @author Coinbase (https://github.com/coinbase/spend-permissions)
contract SpendPermissionManager is EIP712 {
    /// @notice A spend permission for an external entity to be able to spend an account's tokens.
    struct SpendPermission {
        /// @dev Smart account this spend permission is valid for.
        address account;
        /// @dev Entity that can spend `account`'s tokens.
        address spender;
        /// @dev Token address (ERC-7528 native token address or ERC-20 contract).
        address token;
        /// @dev Timestamp this spend permission is valid after (unix seconds).
        uint48 start;
        /// @dev Timestamp this spend permission is valid until (unix seconds).
        uint48 end;
        /// @dev Time duration for resetting used `allowance` on a recurring basis (seconds).
        uint48 period;
        /// @dev Maximum allowed value to spend within each `period`.
        uint160 allowance;
    }

    /// @notice Spend Permission usage for a certain period.
    struct PeriodSpend {
        /// @dev Start time of the period (unix seconds).
        uint48 start;
        /// @dev End time of the period (unix seconds).
        uint48 end;
        /// @dev Accumulated spend amount for period.
        uint160 spend;
    }

    bytes32 constant MESSAGE_TYPEHASH = keccak256(
        "SpendPermission(address account,address spender,address token,uint48 start,uint48 end,uint48 period,uint160 allowance)"
    );

    /// @notice ERC-7528 address convention for native token (https://eips.ethereum.org/EIPS/eip-7528).
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice Spend permission is revoked.
    mapping(bytes32 hash => mapping(address account => bool revoked)) internal _isRevoked;

    /// @notice Spend permission is approved.
    mapping(bytes32 hash => mapping(address account => bool approved)) internal _isApproved;

    /// @notice Last updated period for a spend permission.
    mapping(bytes32 hash => mapping(address account => PeriodSpend)) internal _lastUpdatedPeriod;

    /// @notice Invalid sender for the external call.
    ///
    /// @param sender Expected sender to be valid.
    error InvalidSender(address sender, address expected);

    /// @notice Invalid signature.
    error InvalidSignature();

    /// @notice Spend Permission start time is not strictly less than end time.
    ///
    /// @param start Unix timestamp (seconds) for start of the permission.
    /// @param end Unix timestamp (seconds) for end of the permission.
    error InvalidStartEnd(uint48 start, uint48 end);

    /// @notice Spend Permission has zero allowance.
    error ZeroAllowance();

    /// @notice Spend Permission has zero period.
    error ZeroPeriod();

    /// @notice Unauthorized spend permission.
    error UnauthorizedSpendPermission();

    /// @notice Recurring period has not started yet.
    ///
    /// @param currentTimestamp Current timestamp (unix seconds).
    /// @param start Timestamp this spend permission is valid starting at (unix seconds).
    error BeforeSpendPermissionStart(uint48 currentTimestamp, uint48 start);

    /// @notice Recurring period has not started yet.
    ///
    /// @param currentTimestamp Current timestamp (unix seconds).
    /// @param end Timestamp this spend permission is valid until (unix seconds).
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
    /// @param account The smart contract account the spend permission controls.
    /// @param spendPermission Details of the spend permission.
    event SpendPermissionApproved(bytes32 indexed hash, address indexed account, SpendPermission spendPermission);

    /// @notice SpendPermission was revoked prematurely by account.
    ///
    /// @param hash The unique hash representing the spend permission.
    /// @param account The smart contract account the spend permission controlled.
    /// @param spendPermission Details of the spend permission.
    event SpendPermissionRevoked(bytes32 indexed hash, address indexed account, SpendPermission spendPermission);

    /// @notice Register native or ERC-20 token spend for a spend permission period.
    ///
    /// @param hash Hash of the spend permission.
    /// @param account Account that spent tokens via a spend permission.
    /// @param token Address of token spent via a spend permission.
    /// @param newUsage Start and end of the current period with new spend usage (struct).
    event SpendPermissionUsed(
        bytes32 indexed hash, address indexed account, address indexed token, PeriodSpend newUsage
    );

    /// @notice Require a specific sender for an external call,
    ///
    /// @param sender Expected sender for call to be valid.
    modifier requireSender(address sender) {
        if (msg.sender != sender) revert InvalidSender(msg.sender, sender);
        _;
    }

    /// @notice Approve a spend permission via a direct call from the account.
    ///
    /// @param spendPermission Details of the spend permission.
    function approve(SpendPermission calldata spendPermission) external requireSender(spendPermission.account) {
        _approve(spendPermission);
    }

    /// @notice Revoke a spend permission to disable its use indefinitely.
    ///
    /// @param spendPermission Details of the spend permission.
    function revoke(SpendPermission calldata spendPermission) external requireSender(spendPermission.account) {
        bytes32 hash = getHash(spendPermission);
        _isRevoked[hash][spendPermission.account] = true;
        emit SpendPermissionRevoked(hash, spendPermission.account, spendPermission);
    }

    /// @notice Approve a spend permission with signature and spend tokens in one call.
    ///
    /// @dev After initially approving a spend permission, it is more gas efficient to call `spend` for repeated use.
    ///
    /// @param spendPermission Details of the spend permission.
    /// @param signature Signed approval from the user.
    /// @param recipient Address to spend tokens to.
    /// @param value Amount of token attempting to spend (wei).
    function spendWithSignature(
        SpendPermission memory spendPermission,
        bytes memory signature,
        address recipient,
        uint160 value
    ) external requireSender(spendPermission.spender) {
        approveWithSignature(spendPermission, signature);
        spend(spendPermission, recipient, value);
    }

    /// @notice Approve a spend permission via a signature from the account.
    ///
    /// @dev Compatible with ERC-6492 signatures (https://eips.ethereum.org/EIPS/eip-6492).
    /// @dev Accounts are automatically deployed if initCode present in signature.
    ///
    /// @param spendPermission Details of the spend permission.
    /// @param signature Signed approval from the user.
    function approveWithSignature(SpendPermission memory spendPermission, bytes memory signature) public {
        // validate signature over spend permission data and optionally deploy account
        if (
            !SignatureCheckerLib.isValidERC6492SignatureNowAllowSideEffects(
                spendPermission.account, getHash(spendPermission), signature
            )
        ) {
            revert InvalidSignature();
        }
        _approve(spendPermission);
    }

    /// @notice Spend tokens using a spend permission.
    ///
    /// @param spendPermission Details of the spend permission.
    /// @param recipient Address to spend tokens to.
    /// @param value Amount of token attempting to spend (wei).
    function spend(SpendPermission memory spendPermission, address recipient, uint160 value)
        public
        requireSender(spendPermission.spender)
    {
        _useSpendPermission(spendPermission, value);
        _transferFrom(spendPermission.token, spendPermission.account, recipient, value);
    }

    /// @notice Hash a SpendPermission struct for signing in accordance with EIP-712.
    ///
    /// @param spendPermission Details of the spend permission.
    ///
    /// @return hash Hash of the spend permission.
    function getHash(SpendPermission memory spendPermission) public view returns (bytes32) {
        return _hashTypedData(keccak256(abi.encode(MESSAGE_TYPEHASH, spendPermission)));
    }

    /// @notice Return if spend permission is approved and not revoked.
    ///
    /// @param spendPermission Details of the spend permission.
    ///
    /// @return approved True if spend permission is approved and not revoked.
    function isApproved(SpendPermission memory spendPermission) public view returns (bool) {
        bytes32 hash = getHash(spendPermission);
        return !_isRevoked[hash][spendPermission.account] && _isApproved[hash][spendPermission.account];
    }

    /// @notice Get current period spend.
    ///
    /// @dev Reverts if spend permission has not started or has already ended.
    /// @dev Period boundaries are at fixed intervals of [start + n * period, start + (n + 1) * period - 1].
    ///
    /// @param spendPermission Details of the spend permission.
    ///
    /// @return currentPeriod Currently active period with spend (struct).
    function getCurrentPeriod(SpendPermission memory spendPermission) public view returns (PeriodSpend memory) {
        // check current timestamp is within spend permission time range
        uint48 currentTimestamp = uint48(block.timestamp);
        if (currentTimestamp < spendPermission.start) {
            revert BeforeSpendPermissionStart(currentTimestamp, spendPermission.start);
        } else if (currentTimestamp >= spendPermission.end) {
            revert AfterSpendPermissionEnd(currentTimestamp, spendPermission.end);
        }

        // return last period if still active, otherwise compute new active period start time with no spend
        PeriodSpend memory lastUpdatedPeriod = _lastUpdatedPeriod[getHash(spendPermission)][spendPermission.account];

        // last period exists if spend is non-zero
        bool lastPeriodExists = lastUpdatedPeriod.spend != 0;

        // last period still active if current timestamp within [start, end - 1] range.
        bool lastPeriodStillActive = currentTimestamp < uint256(lastUpdatedPeriod.end);

        if (lastPeriodExists && lastPeriodStillActive) {
            return lastUpdatedPeriod;
        } else {
            // last active period does not exist or is outdated, determine current period

            // current period progress is remainder of time since first recurring period mod reset period
            uint48 currentPeriodProgress = (currentTimestamp - spendPermission.start) % spendPermission.period;

            // current period start is progress duration before current time
            uint48 start = currentTimestamp - currentPeriodProgress;

            // current period end will overflow if period is sufficiently large
            bool endOverflow = uint256(start) + uint256(spendPermission.period) > type(uint48).max;

            // end is one period after start or maximum uint48 if overflow
            uint48 end = endOverflow ? type(uint48).max : start + spendPermission.period;

            return PeriodSpend({start: start, end: end, spend: 0});
        }
    }

    /// @notice Approve spend permission.
    ///
    /// @param spendPermission Details of the spend permission.
    function _approve(SpendPermission memory spendPermission) internal {
        // check start is strictly before end
        if (spendPermission.start >= spendPermission.end) {
            revert InvalidStartEnd(spendPermission.start, spendPermission.end);
        }

        // check period non-zero
        if (spendPermission.period == 0) revert ZeroPeriod();

        // check allowance non-zero
        if (spendPermission.allowance == 0) revert ZeroAllowance();

        bytes32 hash = getHash(spendPermission);
        _isApproved[hash][spendPermission.account] = true;
        emit SpendPermissionApproved(hash, spendPermission.account, spendPermission);
    }

    /// @notice Use a spend permission.
    ///
    /// @param spendPermission Details of the spend permission.
    /// @param value Amount of token attempting to spend (wei).
    function _useSpendPermission(SpendPermission memory spendPermission, uint256 value) internal {
        // early return if no value spent
        if (value == 0) return;

        // require spend permission is approved and not revoked
        if (!isApproved(spendPermission)) revert UnauthorizedSpendPermission();

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
        _lastUpdatedPeriod[hash][spendPermission.account] = currentPeriod;
        emit SpendPermissionUsed(
            hash,
            spendPermission.account,
            spendPermission.token,
            PeriodSpend(currentPeriod.start, currentPeriod.end, uint160(value))
        );
    }

    /// @notice Transfer assets from an account to a recipient.
    ///
    /// @param token Address of the token contract.
    /// @param account Address of the user account.
    /// @param recipient Address of the token recipient.
    /// @param value Amount of tokens to transfer.
    function _transferFrom(address token, address account, address recipient, uint256 value) internal {
        // transfer tokens from account to recipient
        if (token == NATIVE_TOKEN) {
            _execute({account: account, target: recipient, value: value, data: hex""});
        } else {
            _execute({
                account: account,
                target: token,
                value: 0,
                data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, value)
            });
        }
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

    /// @notice Return EIP712 domain name and version.
    ///
    /// @return name Name string for the EIP712 domain.
    /// @return version Version string for the EIP712 domain.
    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        name = "Spend Permission Manager";
        version = "1";
    }
}
