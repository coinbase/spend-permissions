// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";

import {PermissionTypes} from "../PermissionTypes.sol";
import {Policy} from "./Policy.sol";

contract CoinbaseSmartWalletSingleCallPolicy is Policy {
    error ValueTooHigh(uint256 value, uint256 maxValue);
    error BeforeValidAfter(uint48 currentTimestamp, uint48 validAfter);
    error AfterValidUntil(uint48 currentTimestamp, uint48 validUntil);
    error InvalidRecipient();

    struct Config {
        address authority;
        uint256 maxValue;
        uint48 validAfter;
        uint48 validUntil;
    }

    struct PolicyData {
        address to;
        uint256 value;
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
    ) external view override returns (bytes memory accountCallData, bytes memory postCallData) {
        install;
        execNonce;

        Config memory cfg = abi.decode(policyConfig, (Config));
        PolicyData memory data = abi.decode(policyData, (PolicyData));

        uint48 currentTimestamp = uint48(block.timestamp);
        if (cfg.validAfter != 0 && currentTimestamp < cfg.validAfter) {
            revert BeforeValidAfter(currentTimestamp, cfg.validAfter);
        }
        if (cfg.validUntil != 0 && currentTimestamp >= cfg.validUntil) {
            revert AfterValidUntil(currentTimestamp, cfg.validUntil);
        }

        if (data.value > cfg.maxValue) revert ValueTooHigh(data.value, cfg.maxValue);
        if (data.to == address(0)) revert InvalidRecipient();

        // ETH-only move: no arbitrary calldata.
        accountCallData = abi.encodeWithSelector(CoinbaseSmartWallet.execute.selector, data.to, data.value, "");
        postCallData = "";
    }
}


