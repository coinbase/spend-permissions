// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PublicERC6492Validator} from "../src/PublicERC6492Validator.sol";
import {SessionManager} from "../src/SessionManager.sol";
import {SpendPermissionSessionPolicy} from "../src/policies/SpendPermissionSessionPolicy.sol";
import {ERC20SpendHook} from "../src/SpendPermissionSpendHooks/ERC20SpendHook.sol";
import {MagicSpendSpendHook} from "../src/SpendPermissionSpendHooks/MagicSpendSpendHook.sol";
import {NativeTokenSpendHook} from "../src/SpendPermissionSpendHooks/NativeTokenSpendHook.sol";
import {SubAccountSpendHook} from "../src/SpendPermissionSpendHooks/SubAccountSpendHook.sol";
import {Script, console2} from "forge-std/Script.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

/**
 * @notice Deploy the SessionManager, SpendPermissionSessionPolicy, and spend prep session policies.
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
        SessionManager sessionManager = new SessionManager{salt: 0}(publicERC6492Validator);
        SpendPermissionSessionPolicy spendPermissionPolicy = new SpendPermissionSessionPolicy{salt: 0}(address(sessionManager));
        NativeTokenSpendHook nativeTokenSpendHook = new NativeTokenSpendHook(address(spendPermissionPolicy));
        ERC20SpendHook erc20SpendHook = new ERC20SpendHook(address(spendPermissionPolicy));
        MagicSpendSpendHook magicSpendSpendHook = new MagicSpendSpendHook(address(spendPermissionPolicy), MAGIC_SPEND);
        SubAccountSpendHook subAccountSpendHook = new SubAccountSpendHook(address(spendPermissionPolicy));

        logAddress("PublicERC6492Validator", address(publicERC6492Validator));
        logAddress("SessionManager", address(sessionManager));
        logAddress("SpendPermissionSessionPolicy", address(spendPermissionPolicy));
        logAddress("NativeTokenSpendHook", address(nativeTokenSpendHook));
        logAddress("ERC20SpendHook", address(erc20SpendHook));
        logAddress("MagicSpendSpendHook", address(magicSpendSpendHook));
        logAddress("SubAccountSpendHook", address(subAccountSpendHook));
    }

    function logAddress(string memory name, address addr) internal pure {
        console2.logString(string.concat(name, ": ", Strings.toHexString(addr)));
    }
}

// (addresses omitted; script output logs deployed addresses)
