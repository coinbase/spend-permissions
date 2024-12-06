// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SpendPermission, SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";
import {MockSpendPermissionManager} from "../../mocks/MockSpendPermissionManager.sol";

contract GetHashTest is SpendPermissionManagerBase {
    function setUp() public {
        _initializeSpendPermissionManager();
    }

    function test_getHash_success(
        address account,
        address spender,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public view {
        SpendPermission memory spendPermission = SpendPermission({
            account: account,
            spender: spender,
            token: token,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        mockSpendPermissionManager.getHash(spendPermission);
    }

    function test_getHash_success_uniqueHashPerChain(
        address account,
        address spender,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData,
        uint64 chainId1,
        uint64 chainId2
    ) public {
        vm.assume(chainId1 != chainId2);
        vm.assume(chainId1 > 0);
        vm.assume(chainId2 > 0);
        SpendPermission memory spendPermission = SpendPermission({
            account: account,
            spender: spender,
            token: token,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        vm.chainId(chainId1);
        bytes32 hash1 = mockSpendPermissionManager.getHash(spendPermission);
        vm.chainId(chainId2);
        bytes32 hash2 = mockSpendPermissionManager.getHash(spendPermission);
        assertNotEq(hash1, hash2);
    }

    function test_getHash_success_uniqueHashPerContract(
        address account,
        address spender,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData
    ) public {
        SpendPermission memory spendPermission = SpendPermission({
            account: account,
            spender: spender,
            token: token,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        MockSpendPermissionManager mockSpendPermissionManager1 =
            new MockSpendPermissionManager(publicERC6492Validator, address(magicSpend));
        MockSpendPermissionManager mockSpendPermissionManager2 =
            new MockSpendPermissionManager(publicERC6492Validator, address(magicSpend));
        bytes32 hash1 = mockSpendPermissionManager1.getHash(spendPermission);
        bytes32 hash2 = mockSpendPermissionManager2.getHash(spendPermission);
        assertNotEq(hash1, hash2);
    }
}
