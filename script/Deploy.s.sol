// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PublicERC6492Validator} from "../src/PublicERC6492Validator.sol";
import {SpendPermissionManager} from "../src/SpendPermissionManager.sol";
import {ERC20TokenHook} from "../src/hooks/ERC20TokenHook.sol";
import {MagicSpendHook} from "../src/hooks/MagicSpendHook.sol";
import {NativeTokenHook} from "../src/hooks/NativeTokenHook.sol";
import {SubAccountsHook} from "../src/hooks/SubAccountsHook.sol";
import {Script, console2} from "forge-std/Script.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

/**
 * @notice Deploy the SpendPermissionManager contract and its dependencies.
 *
 * @dev Before deploying contracts, make sure dependencies have been installed at the latest or otherwise specific
 * versions using `forge install [OPTIONS] [DEPENDENCIES]`.
 *
 *  For verification to work, BASESCAN_API_KEY must be your ETHERSCAN_API_KEY.
 *
 * forge script script/Deploy.s.sol:Deploy \
 *   --account dev \
 *   --sender $SENDER \
 *   --rpc-url $BASE_SEPOLIA_RPC \
 *   --chain-id 84532 \
 *   --broadcast --verify \
 *   --verifier etherscan \
 *   --etherscan-api-key $BASESCAN_API_KEY \
 *   --verifier-url "https://api.etherscan.io/v2/api?chainid=84532" \
 *   -vvvv
 */
contract Deploy is Script {
    // https://github.com/coinbase/MagicSpend/releases/tag/v1.0.0
    address constant MAGIC_SPEND = 0x011A61C07DbF256A68256B1cB51A5e246730aB92;

    function run() public {
        vm.startBroadcast();

        deploy();

        vm.stopBroadcast();
    }

    function deploy() internal {
        PublicERC6492Validator publicERC6492Validator = new PublicERC6492Validator();
        SpendPermissionManager spendPermissionManager = new SpendPermissionManager{salt: 0}(publicERC6492Validator);
        NativeTokenHook nativeTokenHook = new NativeTokenHook(address(spendPermissionManager));
        ERC20TokenHook erc20TokenHook = new ERC20TokenHook(address(spendPermissionManager));
        MagicSpendHook magicSpendHook = new MagicSpendHook(address(spendPermissionManager), MAGIC_SPEND);
        SubAccountsHook subAccountsHook = new SubAccountsHook(address(spendPermissionManager));

        logAddress("PublicERC6492Validator", address(publicERC6492Validator));
        logAddress("SpendPermissionManager", address(spendPermissionManager));
        logAddress("NativeTokenHook", address(nativeTokenHook));
        logAddress("ERC20TokenHook", address(erc20TokenHook));
        logAddress("MagicSpendHook", address(magicSpendHook));
        logAddress("SubAccountsHook", address(subAccountsHook));
    }

    function logAddress(string memory name, address addr) internal pure {
        console2.logString(string.concat(name, ": ", Strings.toHexString(addr)));
    }
}
