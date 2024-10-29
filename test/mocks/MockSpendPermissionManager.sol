// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC6492Deployer} from "../../src/ERC6492Deployer.sol";
import {SpendPermissionManager} from "../../src/SpendPermissionManager.sol";

contract MockSpendPermissionManager is SpendPermissionManager {
    constructor(ERC6492Deployer _erc6492Deployer) SpendPermissionManager(_erc6492Deployer) {}

    function useSpendPermission(SpendPermission memory spendPermission, uint256 value) public {
        _useSpendPermission(spendPermission, value);
    }
}
