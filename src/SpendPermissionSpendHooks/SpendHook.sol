// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";

import {SpendPolicy} from "../policies/SpendPolicy.sol";

/// @notice Spend-permission-specific hook that returns wallet calls to prepare for a spend (funds/approvals).
interface SpendHook {
    function prepare(
        SpendPolicy.SpendPermission calldata spendPermission,
        uint160 value,
        bytes calldata hookData
    ) external returns (CoinbaseSmartWallet.Call[] memory calls);
}

