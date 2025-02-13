// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";

import {SpendPermission} from "./SpendPermission.sol";

interface IHooks {
    function preSpend(SpendPermission calldata spendPermission, uint256 value, bytes calldata hookData) external;
    function postSpend(SpendPermission calldata spendPermission, uint256 value, bytes calldata hookData) external;
}

contract HooksForwarder {
    address immutable PERMIT3;

    constructor(address permit3) {
        PERMIT3 = permit3;
    }

    function preSpend(SpendPermission calldata spendPermission, uint256 value, address hooks, bytes calldata hookData)
        external
    {
        if (msg.sender != PERMIT3) revert();
        IHooks(hooks).preSpend(spendPermission, value, hookData);
    }

    function postSpend(SpendPermission calldata spendPermission, uint256 value, address hooks, bytes calldata hookData)
        external
    {
        if (msg.sender != PERMIT3) revert();
        IHooks(hooks).postSpend(spendPermission, value, hookData);
    }
}
