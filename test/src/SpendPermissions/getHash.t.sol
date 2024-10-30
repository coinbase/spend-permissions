// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console2} from "forge-std/console2.sol";
import {LibString} from "solady/utils/LibString.sol";

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

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
        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
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
        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
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
        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
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
        MockSpendPermissionManager mockSpendPermissionManager1 = new MockSpendPermissionManager(publicERC6492Validator);
        MockSpendPermissionManager mockSpendPermissionManager2 = new MockSpendPermissionManager(publicERC6492Validator);
        bytes32 hash1 = mockSpendPermissionManager1.getHash(spendPermission);
        bytes32 hash2 = mockSpendPermissionManager2.getHash(spendPermission);
        assertNotEq(hash1, hash2);
    }

    function test_getHash_success_matchesViem(SpendPermissionManager.SpendPermission calldata spendPermission) public {
        string[] memory inputs = new string[](13);
        inputs[0] = "node";
        inputs[1] = "node/getHash.js";
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

        bytes32 contractHash = mockSpendPermissionManager.getHash(spendPermission);

        assertEq(viemHash, contractHash);
    }
}
