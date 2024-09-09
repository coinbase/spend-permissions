// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {NativeTokenRecurringAllowance} from "../../src/mixins/NativeTokenRecurringAllowance.sol";

import {MockNativeTokenRecurringAllowance} from "../mocks/MockNativeTokenRecurringAllowance.sol";

contract NativeTokenRecurringAllowanceBase {
    MockNativeTokenRecurringAllowance mockNativeTokenRecurringAllowance;

    function _initializeNativeTokenRecurringAllowance() internal {
        mockNativeTokenRecurringAllowance = new MockNativeTokenRecurringAllowance();
    }

    function _createRecurringAllowance(uint48 start, uint48 period, uint160 allowance)
        internal
        pure
        returns (NativeTokenRecurringAllowance.RecurringAllowance memory)
    {
        return NativeTokenRecurringAllowance.RecurringAllowance(start, period, allowance);
    }

    function _safeAdd(uint48 a, uint48 b) internal pure returns (uint48 c) {
        bool overflow = uint256(a) + uint256(b) > type(uint48).max;
        return overflow ? type(uint48).max : a + b;
    }
}