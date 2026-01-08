// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SpendPolicy} from "../../src/policies/SpendPolicy.sol";

contract MockSpendPermissionManager is SpendPolicy {
    constructor(address permissionManager) SpendPolicy(permissionManager) {}
}
