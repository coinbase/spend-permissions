// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {
    PermissionDetails,
    SpendPermission,
    SpendPermissionBatch,
    SpendPermissionManager
} from "../../../src/SpendPermissionManager.sol";

import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";
import {MockSpendPermissionManager} from "../../mocks/MockSpendPermissionManager.sol";

contract GetBatchHashTest is SpendPermissionManagerBase {
    function setUp() public {
        _initializeSpendPermissionManager();
    }

    function test_getBatchHash_reverts_emptyBatch(
        address account,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance
    ) public {
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);
        PermissionDetails[] memory permissions = new PermissionDetails[](0);
        SpendPermissionBatch memory spendPermissionBatch = SpendPermissionBatch({
            account: address(account),
            start: start,
            end: end,
            period: period,
            permissions: permissions
        });
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.EmptySpendPermissionBatch.selector));
        mockSpendPermissionManager.getBatchHash(spendPermissionBatch);
    }

    function test_getBatchHash_success(
        address account,
        address spender,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint128 salt
    ) public view {
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);
        PermissionDetails memory permissionDetails1 = PermissionDetails({
            token: token,
            allowance: allowance,
            spender: spender,
            salt: uint256(salt),
            extraData: "0x"
        });
        PermissionDetails memory permissionDetails2 = PermissionDetails({
            token: token,
            allowance: allowance,
            spender: spender,
            salt: uint256(salt) + 1,
            extraData: "0x"
        });
        PermissionDetails[] memory permissions = new PermissionDetails[](2);
        permissions[0] = permissionDetails1;
        permissions[1] = permissionDetails2;
        SpendPermissionBatch memory spendPermissionBatch = SpendPermissionBatch({
            account: address(account),
            start: start,
            end: end,
            period: period,
            permissions: permissions
        });
        mockSpendPermissionManager.getBatchHash(spendPermissionBatch);
    }

    function test_getBatchHash_success_uniqueHashPerChain(
        address account,
        address spender,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint128 salt,
        uint64 chainId1,
        uint64 chainId2
    ) public {
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);
        vm.assume(chainId1 != chainId2);
        vm.assume(chainId1 > 0);
        vm.assume(chainId2 > 0);
        PermissionDetails memory permissionDetails1 = PermissionDetails({
            token: token,
            allowance: allowance,
            spender: spender,
            salt: uint256(salt),
            extraData: "0x"
        });
        PermissionDetails memory permissionDetails2 = PermissionDetails({
            token: token,
            allowance: allowance,
            spender: spender,
            salt: uint256(salt) + 1,
            extraData: "0x"
        });
        PermissionDetails[] memory permissions = new PermissionDetails[](2);
        permissions[0] = permissionDetails1;
        permissions[1] = permissionDetails2;
        SpendPermissionBatch memory spendPermissionBatch = SpendPermissionBatch({
            account: address(account),
            start: start,
            end: end,
            period: period,
            permissions: permissions
        });
        vm.chainId(chainId1);
        bytes32 hash1 = mockSpendPermissionManager.getBatchHash(spendPermissionBatch);
        vm.chainId(chainId2);
        bytes32 hash2 = mockSpendPermissionManager.getBatchHash(spendPermissionBatch);
        assertNotEq(hash1, hash2);
    }

    function test_getBatchHash_success_uniqueHashPerContract(
        address account,
        address spender,
        address token,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt1,
        uint256 salt2
    ) public {
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(allowance > 0);
        PermissionDetails memory permissionDetails1 =
            PermissionDetails({token: token, allowance: allowance, spender: spender, salt: salt1, extraData: "0x"});
        PermissionDetails memory permissionDetails2 =
            PermissionDetails({token: token, allowance: allowance, spender: spender, salt: salt2, extraData: "0x"});
        PermissionDetails[] memory permissions = new PermissionDetails[](2);
        permissions[0] = permissionDetails1;
        permissions[1] = permissionDetails2;
        SpendPermissionBatch memory spendPermissionBatch = SpendPermissionBatch({
            account: address(account),
            start: start,
            end: end,
            period: period,
            permissions: permissions
        });
        MockSpendPermissionManager mockSpendPermissionManager1 =
            new MockSpendPermissionManager(publicERC6492Validator, address(magicSpend));
        MockSpendPermissionManager mockSpendPermissionManager2 =
            new MockSpendPermissionManager(publicERC6492Validator, address(magicSpend));
        bytes32 hash1 = mockSpendPermissionManager1.getBatchHash(spendPermissionBatch);
        bytes32 hash2 = mockSpendPermissionManager2.getBatchHash(spendPermissionBatch);
        assertNotEq(hash1, hash2);
    }
}
