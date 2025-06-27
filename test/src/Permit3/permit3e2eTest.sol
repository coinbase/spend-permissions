// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SpendPermission} from "../../../src/Permit3.sol";
import "./Permit3Base.sol";
import {console2} from "forge-std/console2.sol";

contract Permit3E2ETest is Permit3Base {
    function setUp() public {
        _initializePermit3Base();
    }

    function test_permit3_e2e_erc20Transfer(
        address spender,
        uint48 start,
        uint48 end,
        uint48 period,
        uint160 allowance,
        uint256 salt,
        bytes memory extraData,
        uint256 spendAmount
    ) public {
        vm.assume(spender != address(0));
        // Prevent spender from being any of our core contracts
        vm.assume(spender != address(account));
        vm.assume(spender != address(signatureHook));
        vm.assume(spender != address(permit3));
        // Prevent spender from being a precompile
        assumeNotPrecompile(spender);

        // Ensure start is in a reasonable range and end is after start
        vm.assume(start >= block.timestamp);
        vm.assume(end > start);
        vm.assume(end <= type(uint48).max);
        vm.assume(period > 0);

        // Ensure allowance is reasonable and sufficient for our minimum spend
        vm.assume(allowance >= 0.1 ether);
        vm.assume(allowance <= 1000 ether); // reasonable upper bound

        // Ensure spend amount is valid - between 0.1 ether and allowance
        spendAmount = bound(spendAmount, 0.1 ether, uint256(allowance));

        // Mint tokens to the account
        mockERC20.mint(address(account), uint256(allowance));

        SpendPermission memory permission = SpendPermission({
            account: address(account),
            spender: spender,
            token: address(mockERC20),
            allowance: allowance,
            period: period,
            start: start,
            end: end,
            hook: address(0), // No hook for this test
            salt: salt,
            extraData: extraData
        });

        // Sign the spend permission with ERC6492 wrapper that includes ERC20 approval
        bytes memory signature = _signSpendPermissionWithERC20Approval(
            permission,
            ownerPk,
            0, // owner index
            address(mockERC20)
        );

        // Warp to start time before approval
        vm.warp(start);

        // Record balances before
        uint256 accountBalanceBefore = mockERC20.balanceOf(address(account));
        uint256 spenderBalanceBefore = mockERC20.balanceOf(spender);

        // Approve the spend permission with the wrapped signature
        vm.prank(spender);
        permit3.approveWithSignature(permission, signature);

        // Verify ERC20 approval
        assertEq(
            mockERC20.allowance(address(account), address(permit3)),
            type(uint256).max,
            "Permit3 not approved for infinite spending"
        );

        // Spend the tokens
        vm.prank(spender);
        permit3.spend(permission, uint160(spendAmount));

        // Verify balances after
        assertEq(
            mockERC20.balanceOf(address(account)),
            accountBalanceBefore - spendAmount,
            "Account balance not decreased correctly"
        );
        assertEq(
            mockERC20.balanceOf(spender), spenderBalanceBefore + spendAmount, "Spender balance not increased correctly"
        );
        assertEq(
            mockERC20.allowance(address(account), address(permit3)),
            type(uint256).max,
            "Permit3 allowance changed unexpectedly"
        );
    }
}
