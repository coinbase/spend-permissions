// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";

import {PermissionTypes} from "../PermissionTypes.sol";
import {Policy} from "./Policy.sol";

/// @notice Policy that allows an authority to execute a constrained ERC20->(something) swap
///         on a fixed `swapTarget`, bounded by `maxAmountIn` and checked by `minAmountOut` (balance delta on
/// `tokenOut`).
/// @dev This is the "policy" equivalent of the legacy SpendPermissionSwap helper:
///      - wallet approves `swapTarget` for `amountIn`
///      - wallet calls `swapTarget` with `swapData`
///      - wallet resets approval to 0
///      - policy post-call checks tokenOut balance increased by at least minAmountOut
contract CoinbaseSmartWalletSwapPolicy is Policy {
    using SafeERC20 for IERC20;

    error InvalidPolicyData();
    error InvalidPolicyConfigAccount(address actual, address expected);
    error InvalidSwapTarget(address actual, address expected);
    error SelectorMismatch(bytes4 actual, bytes4 expected);
    error AmountInTooHigh(uint256 amountIn, uint256 maxAmountIn);
    error TokenOutBalanceTooLow(uint256 initialBalance, uint256 finalBalance, uint256 minAmountOut);
    error InvalidSender(address sender, address expected);

    address public immutable PERMISSION_MANAGER;

    struct Config {
        address account;
        address authority;
        address tokenIn;
        address tokenOut;
        address swapTarget;
        bytes4 swapSelector;
        uint256 maxAmountIn;
        uint256 minAmountOut;
        uint48 validAfter;
        uint48 validUntil;
    }

    struct PolicyData {
        uint256 amountIn;
        bytes swapData;
    }

    modifier requireSender(address sender) {
        if (msg.sender != sender) revert InvalidSender(msg.sender, sender);
        _;
    }

    constructor(address permissionManager) {
        PERMISSION_MANAGER = permissionManager;
    }

    function authority(bytes calldata policyConfig) external pure override returns (address) {
        Config memory cfg = abi.decode(policyConfig, (Config));
        return cfg.authority;
    }

    function onExecute(
        PermissionTypes.Install calldata install,
        uint256 execNonce,
        bytes calldata policyConfig,
        bytes calldata policyData
    )
        external
        override
        requireSender(PERMISSION_MANAGER)
        returns (bytes memory accountCallData, bytes memory postCallData)
    {
        execNonce;

        Config memory cfg = abi.decode(policyConfig, (Config));
        if (cfg.account != install.account) revert InvalidPolicyConfigAccount(cfg.account, install.account);

        uint48 currentTimestamp = uint48(block.timestamp);
        if (cfg.validAfter != 0 && currentTimestamp < cfg.validAfter) revert InvalidPolicyData();
        if (cfg.validUntil != 0 && currentTimestamp >= cfg.validUntil) revert InvalidPolicyData();

        PolicyData memory data = abi.decode(policyData, (PolicyData));
        if (data.swapData.length < 4) revert InvalidPolicyData();

        if (data.amountIn > cfg.maxAmountIn) revert AmountInTooHigh(data.amountIn, cfg.maxAmountIn);

        // Read the first 4 bytes of calldata and compare to the expected selector.
        bytes4 actualSelector = bytes4(bytes32(data.swapData));
        if (actualSelector != cfg.swapSelector) revert SelectorMismatch(actualSelector, cfg.swapSelector);

        // Snapshot tokenOut balance before wallet execution.
        uint256 initialOutBalance = IERC20(cfg.tokenOut).balanceOf(cfg.account);

        // Wallet call plan: approve -> swap -> approve(0)
        CoinbaseSmartWallet.Call[] memory calls = new CoinbaseSmartWallet.Call[](3);
        calls[0] = CoinbaseSmartWallet.Call({
            target: cfg.tokenIn,
            value: 0,
            data: abi.encodeWithSelector(IERC20.approve.selector, cfg.swapTarget, data.amountIn)
        });
        calls[1] = CoinbaseSmartWallet.Call({target: cfg.swapTarget, value: 0, data: data.swapData});
        calls[2] = CoinbaseSmartWallet.Call({
            target: cfg.tokenIn, value: 0, data: abi.encodeWithSelector(IERC20.approve.selector, cfg.swapTarget, 0)
        });

        accountCallData = abi.encodeWithSelector(CoinbaseSmartWallet.executeBatch.selector, calls);
        postCallData = abi.encodeWithSelector(
            this.afterExecute.selector, cfg.account, cfg.tokenOut, initialOutBalance, cfg.minAmountOut
        );
    }

    function afterExecute(address account, address tokenOut, uint256 initialOutBalance, uint256 minAmountOut)
        external
        requireSender(PERMISSION_MANAGER)
    {
        uint256 finalOutBalance = IERC20(tokenOut).balanceOf(account);
        if (finalOutBalance < initialOutBalance + minAmountOut) {
            revert TokenOutBalanceTooLow(initialOutBalance, finalOutBalance, minAmountOut);
        }
    }
}


