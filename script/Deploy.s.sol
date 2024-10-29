// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

import {ERC6492Deployer} from "../src/ERC6492Deployer.sol";
import {SpendPermissionManager} from "../src/SpendPermissionManager.sol";
/**
 * forge script Deploy --account dev --sender $SENDER --rpc-url $BASE_SEPOLIA_RPC --verify --verifier-url
 * $SEPOLIA_BASESCAN_API --etherscan-api-key $BASESCAN_API_KEY --broadcast -vvvv
 */

contract Deploy is Script {
    address public constant OWNER = 0x6EcB18183838265968039955F1E8829480Db5329; // dev wallet

    function run() public {
        vm.startBroadcast();

        deploy();

        vm.stopBroadcast();
    }

    function deploy() internal {
        ERC6492Deployer erc6492Deployer = new ERC6492Deployer();
        new SpendPermissionManager{salt: 0}(erc6492Deployer);
    }

    function logAddress(string memory name, address addr) internal pure {
        console2.logString(string.concat(name, ": ", Strings.toHexString(addr)));
    }
}
