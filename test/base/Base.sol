// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {UserOperation} from "account-abstraction/interfaces/UserOperation.sol";
import {Test, console2} from "forge-std/Test.sol";
import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";
import {Utils, WebAuthnInfo} from "webauthn-sol/../test/Utils.sol";
import {WebAuthn} from "webauthn-sol/WebAuthn.sol";

import {MockCoinbaseSmartWallet} from "../mocks/MockCoinbaseSmartWallet.sol";
import {MockContractSigner} from "../mocks/MockContractSigner.sol";

contract Base is Test {
    string public constant BASE_SEPOLIA_RPC = "https://sepolia.base.org";
    address constant ENTRY_POINT_V06 = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
    address constant CDP_PAYMASTER = 0xC484bCD10aB8AD132843872DEb1a0AdC1473189c;
    bytes4 constant EIP1271_MAGIC_VALUE = 0x1626ba7e;
    uint256 ownerPk = uint256(keccak256("owner"));
    address owner = vm.addr(ownerPk);
    uint256 spenderPk = uint256(keccak256("spender"));
    address spender = vm.addr(spenderPk);
    uint256 p256PrivateKey = uint256(0x03d99692017473e2d631945a812607b23269d85721e0f370b8d3e7d29a874fd2);
    bytes p256PublicKey =
        hex"1c05286fe694493eae33312f2d2e0d0abeda8db76238b7a204be1fb87f54ce4228fef61ef4ac300f631657635c28e59bfb2fe71bce1634c81c65642042f6dc4d";
    MockContractSigner spenderContract;
    MockCoinbaseSmartWallet account;

    function _initialize() internal {
        spenderContract = new MockContractSigner(spender);

        account = new MockCoinbaseSmartWallet();
        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(owner);
        account.initialize(owners);
    }

    function _createUserOperation() internal view returns (UserOperation memory) {
        return UserOperation({
            sender: address(account),
            nonce: 0,
            initCode: hex"",
            callData: hex"",
            callGasLimit: 0,
            verificationGasLimit: 0,
            preVerificationGas: 0,
            maxFeePerGas: 0,
            maxPriorityFeePerGas: 0,
            paymasterAndData: abi.encodePacked(CDP_PAYMASTER),
            signature: hex""
        });
    }

    function _createExecuteBatchData(CoinbaseSmartWallet.Call[] memory calls) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(CoinbaseSmartWallet.executeBatch.selector, calls);
    }

    function _createCall(address target, uint256 value, bytes memory data)
        internal
        pure
        returns (CoinbaseSmartWallet.Call memory)
    {
        return CoinbaseSmartWallet.Call(target, value, data);
    }

    function _sign(uint256 pk, bytes32 hash) internal pure returns (bytes memory signature) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, hash);
        return abi.encodePacked(r, s, v);
    }

    function _signP256(uint256 pk, bytes32 hash) internal pure returns (bytes memory signature) {
        WebAuthnInfo memory webAuthn = Utils.getWebAuthnStruct(hash);
        (bytes32 r, bytes32 s) = vm.signP256(pk, webAuthn.messageHash);
        s = bytes32(Utils.normalizeS(uint256(s)));

        return abi.encode(
            WebAuthn.WebAuthnAuth({
                authenticatorData: webAuthn.authenticatorData,
                clientDataJSON: webAuthn.clientDataJSON,
                typeIndex: 1,
                challengeIndex: 23,
                r: uint256(r),
                s: uint256(s)
            })
        );
    }

    function _applySignatureWrapper(uint256 ownerIndex, bytes memory signatureData)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(CoinbaseSmartWallet.SignatureWrapper(ownerIndex, signatureData));
    }
}
