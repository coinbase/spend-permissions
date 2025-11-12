// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

import {ERC20TokenHook} from "../src/hooks/ERC20TokenHook.sol";
import {MagicSpendHook} from "../src/hooks/MagicSpendHook.sol";
import {NativeTokenHook} from "../src/hooks/NativeTokenHook.sol";
import {SubAccountsHook} from "../src/hooks/SubAccountsHook.sol";

contract DeployHooks is Script {
    address constant PERMIT3 = 0x20c072A9EC341c8CCc110D55C32cBBC19070499A;
    // https://github.com/coinbase/MagicSpend/releases/tag/v1.0.0
    address constant MAGIC_SPEND = 0x011A61C07DbF256A68256B1cB51A5e246730aB92;

    function run() public {
        vm.startBroadcast();
        deploy();
        vm.stopBroadcast();
    }

    /*
    NativeTokenHook: 0xa41efd874fe068a6d821bdad3806e4a5c3dde909
    ERC20TokenHook: 0x2cdcce65de95c1c21d87cf217d3c593eda9ac2d1
    MagicSpendHook: 0x4bb1839430c9f5f5d0a12a08befd9f71567849b0
    SubAccountsHook: 0xba3ecb26576ef1f27d5a0a69e312a0b3e9259605
    */

    function deploy() internal {
        NativeTokenHook nativeTokenHook = new NativeTokenHook(PERMIT3);
        ERC20TokenHook erc20TokenHook = new ERC20TokenHook(PERMIT3);
        MagicSpendHook magicSpendHook = new MagicSpendHook(PERMIT3, MAGIC_SPEND);
        SubAccountsHook subAccountsHook = new SubAccountsHook(PERMIT3);

        logAddress("NativeTokenHook", address(nativeTokenHook));
        logAddress("ERC20TokenHook", address(erc20TokenHook));
        logAddress("MagicSpendHook", address(magicSpendHook));
        logAddress("SubAccountsHook", address(subAccountsHook));
    }

    function logAddress(string memory name, address addr) internal pure {
        console2.logString(string.concat(name, ": ", Strings.toHexString(addr)));
    }
}

