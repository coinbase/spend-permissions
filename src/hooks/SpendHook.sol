// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SpendPermissionManager} from "../SpendPermissionManager.sol";

abstract contract SpendHook {
    SpendPermissionManager public immutable PERMIT3;

    constructor(address permit3) {
        PERMIT3 = SpendPermissionManager(payable(permit3));
    }

    function onSpend(
        SpendPermissionManager.SpendPermission calldata spendPermission,
        uint160 value,
        bytes memory hookData
    ) external view virtual returns (bytes memory callData);
}
