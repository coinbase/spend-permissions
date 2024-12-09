// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {MockERC20MissingReturn} from "../../mocks/MockERC20MissingReturn.sol";

import {PeriodSpend, SpendPermission, SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Errors} from "@openzeppelin/contracts/utils/Errors.sol";
import {ERC20} from "solady/../src/tokens/ERC20.sol";
import {MockERC20} from "solady/../test/utils/mocks/MockERC20.sol";
import {MockERC20LikeUSDT} from "solady/../test/utils/mocks/MockERC20LikeUSDT.sol";
import {ReturnsFalseToken} from "solady/../test/utils/weird-tokens/ReturnsFalseToken.sol";

import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";

import {MockCoinbaseSmartWalletUnderspends} from "../../mocks/MockCoinbaseSmartWalletUnderspends.sol";
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
        vm.assume(amount > 0);
        vm.deal(owner, amount);
        assertEq(owner.balance, amount);

        // Directly send ETH from EOA to SPM
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.UnexpectedReceiveAmount.selector, amount, 0));
        (bool success,) = address(mockSpendPermissionManager).call{value: amount}("");
        assertTrue(success);
        assertEq(owner.balance, amount);
        assertEq(address(mockSpendPermissionManager).balance, 0);
        vm.stopPrank();
    }

    function test_receive_revertsOutsideSpendCallMultipleAttempts(uint256 amount) public {
        vm.assume(amount > 0);
        vm.deal(owner, amount);
        assertEq(owner.balance, amount);

        // Try sending ETH directly multiple times
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.UnexpectedReceiveAmount.selector, amount, 0));
        (bool success,) = address(mockSpendPermissionManager).call{value: amount}("");
        assertTrue(success);
        assertEq(owner.balance, amount);
        assertEq(address(mockSpendPermissionManager).balance, 0);

        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.UnexpectedReceiveAmount.selector, amount, 0));
        (bool success2,) = address(mockSpendPermissionManager).call{value: amount}("");
        assertTrue(success2);
        assertEq(owner.balance, amount);
        assertEq(address(mockSpendPermissionManager).balance, 0);
        vm.stopPrank();
    }

    function test_receive_revertsOnInsufficientTransferByUser(
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
        vm.assume(spender != address(account));
        assumePayable(spender);
        vm.assume(start > 0);
        vm.assume(end > 0);
        vm.assume(start < end);
        vm.assume(period > 0);
        vm.assume(spend > 0);
        vm.assume(allowance > 0);
        vm.assume(allowance >= spend);

        // Set up underspending wallet
        MockCoinbaseSmartWalletUnderspends underspendingWallet = new MockCoinbaseSmartWalletUnderspends();

        // Initialize wallet with owner
        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(owner);
        underspendingWallet.initialize(owners);

        // Add SpendPermissionManager as an owner
        vm.startPrank(owner);
        underspendingWallet.addOwnerAddress(address(mockSpendPermissionManager));
        vm.stopPrank();

        SpendPermission memory spendPermission = SpendPermission({
            account: address(underspendingWallet),
            spender: spender,
            token: NATIVE_TOKEN,
            start: start,
            end: end,
            period: period,
            allowance: allowance,
            salt: salt,
            extraData: extraData
        });

        // Fund the underspending wallet
        vm.deal(address(underspendingWallet), allowance);
        assertEq(address(underspendingWallet).balance, allowance);
        vm.deal(spender, 0);
        assertEq(spender.balance, 0);

        bytes memory signature = _signSpendPermission(spendPermission, ownerPk, 0);

        vm.warp(start);

        vm.startPrank(spender);
        mockSpendPermissionManager.approveWithSignature(spendPermission, signature);

        // Attempt spend - should revert when SPM tries to forward funds to spender because user wallet only sends half
        // the amount
        vm.expectRevert("ETH transfer failed"); // Mock coinbase smart wallet throws if execute call fails
        mockSpendPermissionManager.spend(spendPermission, spend);

        // Verify balances remained unchanged
        assertEq(address(underspendingWallet).balance, allowance);
        assertEq(spender.balance, 0);

        PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.spend, 0);
    }

    function test_receive_success_withinSpend(
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
        SpendPermission memory spendPermission = SpendPermission({
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
        PeriodSpend memory usage = mockSpendPermissionManager.getCurrentPeriod(spendPermission);
        assertEq(usage.start, start);
        assertEq(usage.end, _safeAddUint48(start, period, end));
        assertEq(usage.spend, spend);
    }
}
