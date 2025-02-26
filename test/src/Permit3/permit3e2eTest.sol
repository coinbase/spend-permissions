// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./Permit3Base.sol";
import {console2} from "forge-std/console2.sol";
import {MockERC20} from "solady/../test/utils/mocks/MockERC20.sol";

contract Permit3E2ETest is Permit3Base {
    // Add MockERC20 instance
    MockERC20 public mockERC20;

    function setUp() public {
        _initializePermit3Base();

        // Add the permit3Utility as an owner of the smart wallet
        vm.prank(address(account));
        account.addOwnerAddress(address(permit3Utility));

        // Deploy mock ERC20
        mockERC20 = new MockERC20("Test Token", "TEST", 18);

        // Verify utility is properly registered as owner at index 1
        require(account.isOwnerAddress(address(permit3Utility)), "Utility not registered as owner");
        bytes memory ownerAtIndex1 = account.ownerAtIndex(1);
        require(address(uint160(uint256(bytes32(ownerAtIndex1)))) == address(permit3Utility), "Utility not at index 1");

        console2.log("Utility owner bytes at index 1:", address(uint160(uint256(bytes32(ownerAtIndex1)))));
        console2.log("Expected utility address:", address(permit3Utility));
    }

    function test_permit3_e2e_nativeTokenTransfer(
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
        vm.assume(spender != address(permit3Utility));
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

        // Fund the account with enough ETH
        vm.deal(address(account), spendAmount * 2);

        SpendPermission memory permission = SpendPermission({
            account: address(account),
            spender: spender,
            token: NATIVE_TOKEN,
            allowance: allowance,
            period: period,
            start: start,
            end: end,
            salt: salt,
            extraData: extraData
        });

        // Sign the spend permission with ERC6492 wrapper that includes utility registration calldata and
        // includes the utility owner index as prefix to the signature
        bytes memory signature = _signSpendPermissionWithUtilityRegistration(
            permission,
            ownerPk,
            0, // owner index
            address(permit3Utility),
            1 // utility owner index
        );

        // Warp to start time before approval
        vm.warp(start);

        // Approve the spend permission with the wrapped signature
        vm.prank(spender);
        permit3.approveWithSignature(permission, signature);

        // Verify utility registration
        address registeredUtility = permit3.accountToUtility(address(account));
        require(registeredUtility == address(permit3Utility), "Utility not registered");

        // Record balances before
        uint256 accountBalanceBefore = address(account).balance;
        uint256 spenderBalanceBefore = spender.balance;

        // Spend the native tokens
        vm.prank(spender);
        permit3.spend(permission, spendAmount);

        // Verify balances after
        assertEq(
            address(account).balance, accountBalanceBefore - spendAmount, "Account balance not decreased correctly"
        );
        assertEq(spender.balance, spenderBalanceBefore + spendAmount, "Spender balance not increased correctly");
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
        vm.assume(spender != address(permit3Utility));
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
            salt: salt,
            extraData: extraData
        });

        // Sign the spend permission with ERC6492 wrapper that includes ERC20 approval
        bytes memory signature = _signSpendPermissionWithERC20Approval(
            permission,
            ownerPk,
            0, // owner index
            address(permit3Utility),
            1, // utility owner index
            address(mockERC20)
        );

        // Warp to start time before approval
        vm.warp(start);

        // Record balances before
        uint256 accountBalanceBefore = mockERC20.balanceOf(address(account));
        uint256 spenderBalanceBefore = mockERC20.balanceOf(spender);
        uint256 permit3AllowanceBefore = mockERC20.allowance(address(account), address(permit3));

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
        permit3.spend(permission, spendAmount);

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
