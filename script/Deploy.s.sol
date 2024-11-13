// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

import {PublicERC6492Validator} from "../src/PublicERC6492Validator.sol";
import {SpendPermissionManager} from "../src/SpendPermissionManager.sol";

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
    function run() public {
        vm.startBroadcast();

        deploy();

        vm.stopBroadcast();
    }

    function deploy() internal {
        PublicERC6492Validator publicERC6492Validator = new PublicERC6492Validator{salt: 0}();
        new SpendPermissionManager{salt: 0}(publicERC6492Validator);
    }

    function logAddress(string memory name, address addr) internal pure {
        console2.logString(string.concat(name, ": ", Strings.toHexString(addr)));
    }
}
