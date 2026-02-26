// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

import {PublicERC6492Validator} from "../src/PublicERC6492Validator.sol";
import {SpendPermissionManager} from "../src/SpendPermissionManager.sol";
import {SpendRouter} from "../src/SpendRouter.sol";

/**
 * @notice Deploy the SpendPermissionManager contract and its dependencies.
 *
 * @dev Before deploying contracts, make sure dependencies have been installed at the latest or otherwise specific
 * versions using `forge install [OPTIONS] [DEPENDENCIES]`.
 *
 * forge script Deploy --account dev --sender $SENDER --rpc-url $BASE_SEPOLIA_RPC --verify --verifier-url
 * $SEPOLIA_BASESCAN_API --etherscan-api-key $BASESCAN_API_KEY --broadcast -vvvv
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
        // Deploy dependencies
        PublicERC6492Validator publicERC6492Validator = new PublicERC6492Validator{salt: 0}();
        
        // Deploy Manager
        SpendPermissionManager manager = new SpendPermissionManager{salt: 0}(publicERC6492Validator, MAGIC_SPEND);
        
        // Deploy Router
        SpendRouter router = new SpendRouter{salt: 0}(manager);

        logAddress("PublicERC6492Validator", address(publicERC6492Validator));
        logAddress("SpendPermissionManager", address(manager));
        logAddress("SpendRouter", address(router));
    }

    function logAddress(string memory name, address addr) internal pure {
        console2.logString(string.concat(name, ": ", Strings.toHexString(addr)));
    }
}
