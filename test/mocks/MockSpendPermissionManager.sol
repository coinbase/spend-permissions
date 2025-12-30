// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SpendPermissionSessionPolicy} from "../../src/policies/SpendPermissionSessionPolicy.sol";

contract MockSpendPermissionManager is SpendPermissionSessionPolicy {
    constructor(address sessionManager) SpendPermissionSessionPolicy(sessionManager) {}
}
