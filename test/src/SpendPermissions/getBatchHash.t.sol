// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console2} from "forge-std/console2.sol";
import {LibString} from "solady/utils/LibString.sol";

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

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
        SpendPermissionManager.PermissionDetails[] memory permissions =
            new SpendPermissionManager.PermissionDetails[](0);
        SpendPermissionManager.SpendPermissionBatch memory spendPermissionBatch = SpendPermissionManager
            .SpendPermissionBatch({
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
        SpendPermissionManager.PermissionDetails memory permissionDetails1 = SpendPermissionManager.PermissionDetails({
            token: token,
            allowance: allowance,
            spender: spender,
            salt: uint256(salt),
            extraData: "0x"
        });
        SpendPermissionManager.PermissionDetails memory permissionDetails2 = SpendPermissionManager.PermissionDetails({
            token: token,
            allowance: allowance,
            spender: spender,
            salt: uint256(salt) + 1,
            extraData: "0x"
        });
        SpendPermissionManager.PermissionDetails[] memory permissions =
            new SpendPermissionManager.PermissionDetails[](2);
        permissions[0] = permissionDetails1;
        permissions[1] = permissionDetails2;
        SpendPermissionManager.SpendPermissionBatch memory spendPermissionBatch = SpendPermissionManager
            .SpendPermissionBatch({
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
        SpendPermissionManager.PermissionDetails memory permissionDetails1 = SpendPermissionManager.PermissionDetails({
            token: token,
            allowance: allowance,
            spender: spender,
            salt: uint256(salt),
            extraData: "0x"
        });
        SpendPermissionManager.PermissionDetails memory permissionDetails2 = SpendPermissionManager.PermissionDetails({
            token: token,
            allowance: allowance,
            spender: spender,
            salt: uint256(salt) + 1,
            extraData: "0x"
        });
        SpendPermissionManager.PermissionDetails[] memory permissions =
            new SpendPermissionManager.PermissionDetails[](2);
        permissions[0] = permissionDetails1;
        permissions[1] = permissionDetails2;
        SpendPermissionManager.SpendPermissionBatch memory spendPermissionBatch = SpendPermissionManager
            .SpendPermissionBatch({
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
        SpendPermissionManager.PermissionDetails memory permissionDetails1 = SpendPermissionManager.PermissionDetails({
            token: token,
            allowance: allowance,
            spender: spender,
            salt: salt1,
            extraData: "0x"
        });
        SpendPermissionManager.PermissionDetails memory permissionDetails2 = SpendPermissionManager.PermissionDetails({
            token: token,
            allowance: allowance,
            spender: spender,
            salt: salt2,
            extraData: "0x"
        });
        SpendPermissionManager.PermissionDetails[] memory permissions =
            new SpendPermissionManager.PermissionDetails[](2);
        permissions[0] = permissionDetails1;
        permissions[1] = permissionDetails2;
        SpendPermissionManager.SpendPermissionBatch memory spendPermissionBatch = SpendPermissionManager
            .SpendPermissionBatch({
            account: address(account),
            start: start,
            end: end,
            period: period,
            permissions: permissions
        });
        MockSpendPermissionManager mockSpendPermissionManager1 = new MockSpendPermissionManager(publicERC6492Validator);
        MockSpendPermissionManager mockSpendPermissionManager2 = new MockSpendPermissionManager(publicERC6492Validator);
        bytes32 hash1 = mockSpendPermissionManager1.getBatchHash(spendPermissionBatch);
        bytes32 hash2 = mockSpendPermissionManager2.getBatchHash(spendPermissionBatch);
        assertNotEq(hash1, hash2);
    }

    function test_getBatchHash_success_matchesViem(SpendPermissionManager.SpendPermission calldata spendPermission)
        public
    {
        string[] memory inputs = new string[](13);
        inputs[0] = "node";
        inputs[1] = "node/getBatchHash.js";
        inputs[2] = LibString.toString(block.chainid);
        inputs[3] = LibString.toHexString(address(mockSpendPermissionManager));
        inputs[4] = LibString.toHexString(spendPermission.account);
        inputs[5] = LibString.toHexString(spendPermission.spender);
        inputs[6] = LibString.toHexString(spendPermission.token);
        inputs[7] = LibString.toString(spendPermission.allowance);
        inputs[8] = LibString.toString(spendPermission.period);
        inputs[9] = LibString.toString(spendPermission.start);
        inputs[10] = LibString.toString(spendPermission.end);
        inputs[11] = LibString.toString(spendPermission.salt);
        inputs[12] = LibString.toHexString(spendPermission.extraData);

        bytes memory res = vm.ffi(inputs);
        bytes32 viemHash = abi.decode(res, (bytes32));
        console2.logBytes32(viemHash);

        SpendPermissionManager.PermissionDetails memory permissionDetails = SpendPermissionManager.PermissionDetails({
            spender: spendPermission.spender,
            token: spendPermission.token,
            allowance: spendPermission.allowance,
            salt: spendPermission.salt,
            extraData: spendPermission.extraData
        });
        SpendPermissionManager.PermissionDetails[] memory permissions =
            new SpendPermissionManager.PermissionDetails[](1);
        permissions[0] = permissionDetails;

        SpendPermissionManager.SpendPermissionBatch memory spendPermissionBatch = SpendPermissionManager
            .SpendPermissionBatch({
            account: spendPermission.account,
            period: spendPermission.period,
            start: spendPermission.start,
            end: spendPermission.end,
            permissions: permissions
        });

        bytes32 contractHash = mockSpendPermissionManager.getBatchHash(spendPermissionBatch);
        console2.logBytes32(contractHash);

        assertEq(viemHash, contractHash);
    }
}
