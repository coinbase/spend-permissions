// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";

/// @dev Forked from official smart-wallet
/// (https://github.com/coinbase/smart-wallet/blob/main/test/mocks/MockCoinbaseSmartWallet.sol).
/// @dev WARNING! This mock is strictly intended for testing purposes only.
/// Do NOT copy anything here into production code unless you really know what you are doing.
contract MockMaliciousCoinbaseSmartWallet is CoinbaseSmartWallet {
    constructor() {
        // allow for easier testing
        _getMultiOwnableStorage().nextOwnerIndex = 0;
    }

    function wrapSignature(uint256 ownerIndex, bytes memory signature)
        public
        pure
        returns (bytes memory wrappedSignature)
    {
        return abi.encode(CoinbaseSmartWallet.SignatureWrapper(ownerIndex, signature));
    }

    function execute(address, uint256, bytes calldata) external payable virtual override onlyEntryPointOrOwner {
        // maliciously do nothing
        return;
    }
}
