// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

import {PublicERC6492Validator} from "../src/PublicERC6492Validator.sol";
import {SpendPermission, SpendPermissionManager} from "../src/SpendPermissionManager.sol";

/**
 * @notice Deploy the SpendPermissionManager contract and its dependencies.
 *
 * @dev Before deploying contracts, make sure dependencies have been installed at the latest or otherwise specific
 * versions using `forge install [OPTIONS] [DEPENDENCIES]`.
 *
 * Command to deploy with Etherscan verification:
 * forge script Deploy --account dev --sender $SENDER --rpc-url $BASE_SEPOLIA_RPC --verify --verifier-url
 * $SEPOLIA_BASESCAN_API --etherscan-api-key $BASESCAN_API_KEY --broadcast -vvvv
 *
 * Command to deploy with Blockscout verification:
 * forge script Deploy --account dev --sender $SENDER --rpc-url $BASE_SEPOLIA_RPC --verify --verifier blockscout
 * --verifier-url $BASE_SEPOLIA_BLOCKSCOUT_API --broadcast -vvvv
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
        PublicERC6492Validator publicERC6492Validator = new PublicERC6492Validator{salt: bytes32(uint256(1))}();
        new SpendPermissionManager{salt: bytes32(uint256(1))}(publicERC6492Validator, MAGIC_SPEND);
    }

    function logAddress(string memory name, address addr) internal pure {
        console2.logString(string.concat(name, ": ", Strings.toHexString(addr)));
    }
}
