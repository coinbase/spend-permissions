// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {PublicERC6492Validator} from "../PublicERC6492Validator.sol";
import {SpendPermissionManager} from "../SpendPermissionManager.sol";

contract TestERC20_NoHook is ERC20 {
    constructor() ERC20("NoHook", "NHK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract NoHook_EOA_HappyPath_Test is Test {
    PublicERC6492Validator validator;
    SpendPermissionManager permit3;
    TestERC20_NoHook token;

    uint256 ownerPk = uint256(keccak256("owner-eoa"));
    address owner = vm.addr(ownerPk);
    uint256 spenderPk = uint256(keccak256("spender-eoa"));
    address spender = vm.addr(spenderPk);

    function setUp() public {
        validator = new PublicERC6492Validator();
        permit3 = new SpendPermissionManager(validator);
        token = new TestERC20_NoHook();

        // fund owner with ERC20 and approve Permit3 for max allowance
        token.mint(owner, 1_000 ether);
        vm.prank(owner);
        token.approve(address(permit3), type(uint256).max);
    }

    function test_noHook_eoa_erc20_spend_success() public {
        uint48 start = uint48(block.timestamp);
        uint48 end = type(uint48).max;
        uint48 period = 7 days;
        uint160 allowance = 100 ether;
        uint160 spend = 10 ether;

        SpendPermissionManager.SpendPermission memory sp = SpendPermissionManager.SpendPermission({
            account: owner,
            spender: spender,
            token: address(token),
            allowance: allowance,
            period: period,
            start: start,
            end: end,
            salt: 0,
            extraData: hex"",
            hook: address(0),
            hookConfig: hex""
        });

        // EOA signs the EIP-712 typed data hash
        bytes32 digest = permit3.getHash(sp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        // approve with signature and spend
        vm.startPrank(spender);
        permit3.approveWithSignature(sp, sig);
        permit3.spend(sp, spend, hex"");
        vm.stopPrank();

        assertEq(token.balanceOf(owner), 1_000 ether - spend);
        assertEq(token.balanceOf(spender), spend);

        SpendPermissionManager.PeriodSpend memory usage = permit3.getCurrentPeriod(sp);
        assertEq(usage.start, start);
        assertEq(usage.spend, spend);
    }
}

