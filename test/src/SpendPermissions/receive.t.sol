// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {MockERC20MissingReturn} from "../../mocks/MockERC20MissingReturn.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Errors} from "@openzeppelin/contracts/utils/Errors.sol";
import {ERC20} from "solady/../src/tokens/ERC20.sol";
import {MockERC20} from "solady/../test/utils/mocks/MockERC20.sol";
import {MockERC20LikeUSDT} from "solady/../test/utils/mocks/MockERC20LikeUSDT.sol";
import {ReturnsFalseToken} from "solady/../test/utils/weird-tokens/ReturnsFalseToken.sol";

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";

import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";
import {MockMaliciousCoinbaseSmartWallet} from "../../mocks/MockMaliciousCoinbaseSmartWallet.sol";

contract ReceiveTest is SpendPermissionManagerBase {
    function setUp() public {
        _initializeSpendPermissionManager();
        vm.startPrank(owner);
        account.addOwnerAddress(address(mockSpendPermissionManager));

        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(owner);
        vm.stopPrank();
    }

    function test_receive_revertsOutsideSpendCall(uint256 amount) public {
        vm.deal(address(account), amount);
        assertEq(address(account).balance, amount);
        vm.startPrank(address(account));
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.ReceiveCalledOutsideSpend.selector));
        account.execute({target: address(mockSpendPermissionManager), value: amount, data: hex""});
    }

    function test_receive_revertsOutsideSpendCallMultipleAttempts(uint256 amount) public {
        vm.deal(address(account), amount);
        assertEq(address(account).balance, amount);
        vm.startPrank(address(account));
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.ReceiveCalledOutsideSpend.selector));
        account.execute({target: address(mockSpendPermissionManager), value: amount, data: hex""});
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.ReceiveCalledOutsideSpend.selector));
        account.execute({target: address(mockSpendPermissionManager), value: amount, data: hex""});
    }

    function test_receive_success_ether(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData,
        uint160 spend
    ) public {
        vm.assume(spender != address(0));
        vm.assume(spender != address(account)); // otherwise balance checks can fail
        assumePayable(spender);
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(spend > 0);
        vm.assume(allowance > 0);
        vm.assume(allowance >= spend);
        SpendPermissionManager.SpendPermission memory spendPermission = SpendPermissionManager.SpendPermission({
            account: address(account),
            spender: spender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });
        vm.deal(address(account), allowance);
        assertEq(address(account).balance, allowance);
        vm.deal(spender, 0);
        assertEq(spender.balance, 0);

        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);

        vm.warp(start);

        vm.startPrank(spender);
        mockSpendPermissionManager.approveWithSignature(spendPermission, signature);
        mockSpendPermissionManager.spend(spendPermission, spend);

        assertEq(address(account).balance, allowance - spend);
        assertEq(spender.balance, spend);
        SpendPermissionManager.PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period, end));
        assertEq(usage.spend, spend);
    }
}
