// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SpendPermission} from "../../../src/Permit3.sol";

import "./Permit3Base.sol";
import {console2} from "forge-std/console2.sol";
import {MagicSpend} from "magicspend/MagicSpend.sol";

contract Permit3E2ETest is Permit3Base {
    struct CommonTestParams {
        address spender;
        uint48 start;
        uint48 end;
        uint48 period;
        uint160 allowance;
        uint256 salt;
        bytes extraData;
        uint128 entropy;
        uint256 spendAmount;
    }

    // Helper function to validate common assumptions
    function _validateCommonAssumptions(CommonTestParams memory params) internal view {
        vm.assume(params.spender != address(0));
        // Prevent spender from being any of our core contracts
        vm.assume(params.spender != address(account));
        vm.assume(params.spender != address(signatureHook));
        vm.assume(params.spender != address(permit3));
        vm.assume(params.spender != address(magicSpend));
        // Prevent spender from being a precompile
        assumeNotPrecompile(params.spender);

        // Ensure start is in a reasonable range and end is after start
        vm.assume(params.start >= block.timestamp);
        vm.assume(params.end > params.start);
        vm.assume(params.end <= type(uint48).max);
        vm.assume(params.period > 0);

        // Ensure allowance is reasonable and sufficient for our minimum spend
        vm.assume(params.allowance >= 0.1 ether);
        vm.assume(params.allowance <= 1000 ether); // reasonable upper bound
    }

    function setUp() public {
        _initializePermit3Base();
    }

    function test_permit3_e2e_erc20Transfer(CommonTestParams memory params) public {
        _validateCommonAssumptions(params);

        // Ensure spend amount is valid - between 0.1 ether and allowance
        params.spendAmount = bound(params.spendAmount, 0.1 ether, uint256(params.allowance));

        // Mint tokens to the account
        mockERC20.mint(address(account), uint256(params.allowance));

        SpendPermission memory permission = SpendPermission({
            account: address(account),
            spender: params.spender,
            token: address(mockERC20),
            allowance: params.allowance,
            period: params.period,
            start: params.start,
            end: params.end,
            salt: params.salt,
            extraData: params.extraData
        });

        CoinbaseSmartWallet.Call[] memory calls = new CoinbaseSmartWallet.Call[](1);
        calls[0] = _encodeERC20ApprovalCall(address(mockERC20));

        // Sign the spend permission with ERC6492 wrapper that includes ERC20 approval
        bytes memory signature = _signSpendPermissionWithERC20Approval(permission, ownerPk, 0, address(mockERC20));

        // Warp to start time before approval
        vm.warp(params.start);

        // Record balances before
        uint256 accountBalanceBefore = mockERC20.balanceOf(address(account));
        uint256 spenderBalanceBefore = mockERC20.balanceOf(params.spender);

        // Approve the spend permission with the wrapped signature
        vm.prank(params.spender);
        permit3.approveWithSignature(permission, signature);

        // Verify ERC20 approval
        assertEq(
            mockERC20.allowance(address(account), address(permit3)),
            type(uint256).max,
            "Permit3 not approved for infinite spending"
        );

        // Spend the tokens
        vm.prank(params.spender);
        permit3.spend(permission, uint160(params.spendAmount));

        // Verify balances after
        assertEq(
            mockERC20.balanceOf(address(account)),
            accountBalanceBefore - params.spendAmount,
            "Account balance not decreased correctly"
        );
        assertEq(
            mockERC20.balanceOf(params.spender),
            spenderBalanceBefore + params.spendAmount,
            "Spender balance not increased correctly"
        );
        assertEq(
            mockERC20.allowance(address(account), address(permit3)),
            type(uint256).max,
            "Permit3 allowance changed unexpectedly"
        );
    }

    function test_permit3_e2e_erc20TransferWithMagicSpend(CommonTestParams memory params) public {
        _validateCommonAssumptions(params);

        // Ensure spend amount is valid - between 0.1 ether and allowance
        params.spendAmount = bound(params.spendAmount, 0.1 ether, uint256(params.allowance));

        // Mint tokens to the account
        mockERC20.mint(address(account), uint256(params.allowance));

        SpendPermission memory permission = SpendPermission({
            account: address(account),
            spender: params.spender,
            token: address(mockERC20),
            allowance: params.allowance,
            period: params.period,
            start: params.start,
            end: params.end,
            salt: params.salt,
            extraData: params.extraData
        });

        // Create and sign a withdraw request
        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(permission, params.entropy);
        withdrawRequest.asset = address(mockERC20);
        withdrawRequest.amount = params.spendAmount;
        withdrawRequest.signature = _signWithdrawRequest(address(account), withdrawRequest);

        mockERC20.mint(address(magicSpend), params.allowance);

        // Create signature that encodes the register hook call and the ERC20 approval call
        CoinbaseSmartWallet.Call[] memory calls = new CoinbaseSmartWallet.Call[](2);
        calls[0] = _encodeRegisterHookCall(permission, address(magicSpendHook));
        calls[1] = _encodeERC20ApprovalCall(address(mockERC20));
        bytes memory signature = _signSpendPermissionWithSignedCalls(permission, ownerPk, 0, calls);

        // Warp to start time before approval
        vm.warp(params.start);

        // Record balances before
        uint256 accountBalanceBefore = mockERC20.balanceOf(address(account));
        uint256 spenderBalanceBefore = mockERC20.balanceOf(params.spender);

        // Approve the spend permission with the wrapped signature
        vm.prank(params.spender);
        permit3.approveWithSignature(permission, signature);

        // Verify ERC20 approval
        assertEq(
            mockERC20.allowance(address(account), address(permit3)),
            type(uint256).max,
            "Permit3 not approved for infinite spending"
        );

        // Spend using hook data that encodes the magicSpend address and withdraw request
        vm.prank(params.spender);
        permit3.spend(permission, uint160(params.spendAmount), abi.encode(address(magicSpend), withdrawRequest));

        // Verify balances after
        // In MagicSpend scenario, account balance should remain unchanged
        // (receives from MagicSpend what it spends to spender)
        assertEq(
            mockERC20.balanceOf(address(account)),
            accountBalanceBefore,
            "Account balance should remain unchanged in MagicSpend scenario"
        );
        assertEq(
            mockERC20.balanceOf(params.spender),
            spenderBalanceBefore + params.spendAmount,
            "Spender balance not increased correctly"
        );
        assertEq(
            mockERC20.allowance(address(account), address(permit3)),
            type(uint256).max,
            "Permit3 allowance changed unexpectedly"
        );
    }
}
