// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";

import {MagicSpend} from "magicspend/MagicSpend.sol";
import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";
import {CoinbaseSmartWalletFactory} from "smart-wallet/CoinbaseSmartWalletFactory.sol";

import {CoinbaseSmartWalletSignatureHooks} from "../../../src/CoinbaseSmartWalletSignatureHooks.sol";

import {MagicSpendHook} from "../../../src/MagicSpendHook.sol";
import {Permit3, SpendPermission} from "../../../src/Permit3.sol";
import {PublicERC6492Validator} from "../../../src/PublicERC6492Validator.sol";

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "solady/../test/utils/mocks/MockERC20.sol";

import {Base} from "../../base/Base.sol";

contract Permit3Base is Base {
    // Constants
    address constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    bytes32 constant EIP6492_MAGIC_VALUE = 0x6492649264926492649264926492649264926492649264926492649264926492;
    bytes32 constant CBSW_MESSAGE_TYPEHASH = keccak256("CoinbaseSmartWalletMessage(bytes32 hash)");
    uint256 constant NONCE_HASH_BITS = 128;

    // Contract instances
    PublicERC6492Validator public publicERC6492Validator;
    Permit3 public permit3;
    CoinbaseSmartWalletSignatureHooks public signatureHook;
    CoinbaseSmartWalletFactory public mockCoinbaseSmartWalletFactory;
    MagicSpend public magicSpend;
    MagicSpendHook public magicSpendHook;
    MockERC20 public mockERC20;

    function _initializePermit3Base() internal {
        _initialize(); // Initialize from Base

        // Deploy core contracts
        publicERC6492Validator = new PublicERC6492Validator();
        permit3 = new Permit3(publicERC6492Validator); // Pass zero address for MAGIC_SPEND for now
        signatureHook = new CoinbaseSmartWalletSignatureHooks(address(publicERC6492Validator));
        mockCoinbaseSmartWalletFactory = new CoinbaseSmartWalletFactory(address(account));
        mockERC20 = new MockERC20("Test Token", "TEST", 18);
        magicSpend = new MagicSpend(owner, 1);
        magicSpendHook = new MagicSpendHook(permit3);

        // Add the signatureHook as an owner of the smart wallet
        vm.prank(address(account));
        account.addOwnerAddress(address(signatureHook));

        // Add Permit3 as an owner of the smart wallet (needed for hook delegatecalls)
        vm.prank(address(account));
        account.addOwnerAddress(address(permit3));

        // Verify signatureHook is properly registered as owner at index 1
        require(account.isOwnerAddress(address(signatureHook)), "SignatureHook not registered as owner");
        bytes memory ownerAtIndex1 = account.ownerAtIndex(1);
        require(
            address(uint160(uint256(bytes32(ownerAtIndex1)))) == address(signatureHook), "SignatureHook not at index 1"
        );

        // Verify Permit3 is properly registered as owner
        require(account.isOwnerAddress(address(permit3)), "Permit3 not registered as owner");

        // Fund the test account with some ETH
        vm.deal(address(account), 100 ether);
    }

    /// @notice Helper to create a SpendPermission with default values
    function _createSpendPermission() internal view returns (SpendPermission memory) {
        return SpendPermission({
            account: address(account),
            spender: spender,
            token: NATIVE_TOKEN,
            allowance: 1 ether,
            period: 604800, // 1 week
            start: uint48(block.timestamp),
            end: type(uint48).max,
            salt: 0,
            extraData: ""
        });
    }

    /// @notice Helper to sign a spend permission with ERC6492 wrapper for utility registration
    /// @param spendPermission The spend permission to sign
    /// @param ownerPk Private key of the signer
    /// @param ownerIndex Index of the signer in the wallet's owner list
    /// @param utility Address of the utility contract to register
    /// @param utilityOwnerIndex Index of the utility contract in the wallet's owner list
    // function _signSpendPermissionWithUtilityRegistration(
    //     SpendPermission memory spendPermission,
    //     uint256 ownerPk,
    //     uint256 ownerIndex,
    //     address utility,
    //     uint256 utilityOwnerIndex
    // ) internal view returns (bytes memory) {
    //     bytes32 spendPermissionHash = permit3.getHash(spendPermission);

    //     // Construct replaySafeHash without relying on the account contract being deployed
    //     bytes32 cbswDomainSeparator = keccak256(
    //         abi.encode(
    //             keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
    //             keccak256(bytes("Coinbase Smart Wallet")),
    //             keccak256(bytes("1")),
    //             block.chainid,
    //             spendPermission.account
    //         )
    //     );
    //     bytes32 replaySafeHash = keccak256(
    //         abi.encodePacked(
    //             "\x19\x01", cbswDomainSeparator, keccak256(abi.encode(CBSW_MESSAGE_TYPEHASH, spendPermissionHash))
    //         )
    //     );
    //     bytes memory signature = _sign(ownerPk, replaySafeHash);
    //     bytes memory wrappedSignature = _applySignatureWrapper(ownerIndex, signature);

    //     // Add utility owner index to the front of the wrapped signature
    //     wrappedSignature = abi.encode(CoinbaseSmartWallet.SignatureWrapper(utilityOwnerIndex, wrappedSignature));

    //     // Create the prepare data for registering the utility
    //     bytes memory registerCalldata =
    //         abi.encodeWithSelector(CoinbaseSmartWalletPermit3Utility.registerPermit3Utility.selector);

    //     // Wrap inner sig in 6492 format with utility registration as prepare data
    //     bytes memory eip6492Signature = abi.encode(
    //         utility, // factory (the utility contract that will execute prepare data)
    //         registerCalldata, // prepare data (utility registration)
    //         wrappedSignature
    //     );
    //     eip6492Signature = abi.encodePacked(eip6492Signature, EIP6492_MAGIC_VALUE);
    //     return eip6492Signature;
    // }

    /// Signature format:
    /// prepareTarget = address of the SignatureHook contract
    /// prepareData = SignatureHook.executeSignedCallsWithMessage(account, calls, signature, verifyingContract, hash)
    /// where account = address(account)
    /// calls = [
    ///     CoinbaseSmartWallet.Call({
    ///         target: address(mockERC20),
    ///         value: 0,
    ///         data: abi.encodeWithSelector(IERC20.approve.selector, address(permit3), infiniteAllowance))
    ///     })
    /// ]
    /// signature = actual signature from the smart account over the following message:
    /// keccak256(abi.encode(verifyingContract, calls, hash))
    /// verifyingContract = address(permit3)
    /// hash = spendPermissionHash (the hash of the spend permission)
    /// Finally, the "inner signature" of the 6492 signature is literally just {ownerIndex}{empty bytes}, as this
    /// signature will cause the smart account
    /// to call isValidSignature on the SignatureHook contract, which will return true if the signature from the account
    /// had already been validated during the
    /// call to executeSignedCallsWithMessage.
    /// very last is the standard 6492 magic value

    function _encodeERC20ApprovalCall(address token) internal view returns (CoinbaseSmartWallet.Call memory) {
        return CoinbaseSmartWallet.Call({
            target: token,
            value: 0,
            data: abi.encodeWithSelector(IERC20.approve.selector, address(permit3), type(uint256).max)
        });
    }

    function _encodeRegisterHookCall(SpendPermission memory spendPermission, address hook)
        internal
        view
        returns (CoinbaseSmartWallet.Call memory)
    {
        return CoinbaseSmartWallet.Call({
            target: address(permit3),
            value: 0,
            data: abi.encodeWithSelector(Permit3.registerHookForPermission.selector, spendPermission, hook)
        });
    }

    function _signSpendPermissionWithERC20Approval(
        SpendPermission memory spendPermission,
        uint256 ownerPk,
        uint256 ownerIndex,
        address token
    ) internal view returns (bytes memory) {
        CoinbaseSmartWallet.Call[] memory calls = new CoinbaseSmartWallet.Call[](1);
        calls[0] = _encodeERC20ApprovalCall(token);

        // Sign the spend permission with ERC6492 wrapper that includes ERC20 approval
        bytes memory signature = _signSpendPermissionWithSignedCalls(
            spendPermission,
            ownerPk,
            0, // owner index
            calls
        );

        return signature;
    }

    /// @notice Helper to sign a spend permission with ERC6492 wrapper for ERC20 approval using
    /// CoinbaseSmartWalletSignatureHooks
    /// @param spendPermission The spend permission to sign
    /// @param ownerPk Private key of the signer
    /// @param ownerIndex Index of the signer in the wallet's owner list
    /// @param calls The calls to sign
    function _signSpendPermissionWithSignedCalls(
        SpendPermission memory spendPermission,
        uint256 ownerPk,
        uint256 ownerIndex,
        CoinbaseSmartWallet.Call[] memory calls
    ) internal view returns (bytes memory) {
        bytes32 spendPermissionHash = permit3.getHash(spendPermission);

        // Create the message to sign: keccak256(abi.encode(verifyingContract, calls, hash))
        bytes32 messageToSign = keccak256(abi.encode(address(permit3), calls, spendPermissionHash));

        // Construct replaySafeHash for the smart wallet
        bytes32 cbswDomainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Coinbase Smart Wallet")),
                keccak256(bytes("1")),
                block.chainid,
                spendPermission.account
            )
        );
        bytes32 replaySafeHash = keccak256(
            abi.encodePacked(
                "\x19\x01", cbswDomainSeparator, keccak256(abi.encode(CBSW_MESSAGE_TYPEHASH, messageToSign))
            )
        );

        // Sign the message with the owner's private key
        bytes memory actualSignature = _sign(ownerPk, replaySafeHash);
        bytes memory wrappedSignature = _applySignatureWrapper(ownerIndex, actualSignature);

        // Create the prepare data for CoinbaseSmartWalletSignatureHooks.executeSignedCallsWithMessage
        bytes memory prepareData = abi.encodeWithSelector(
            CoinbaseSmartWalletSignatureHooks.executeSignedCallsWithMessage.selector,
            spendPermission.account,
            calls,
            wrappedSignature,
            address(permit3),
            spendPermissionHash
        );

        // Create the inner signature: {signatureHookOwnerIndex}{empty bytes}
        // SignatureHook is at owner index 1 (as verified in initialization)
        uint256 signatureHookOwnerIndex = 1;
        bytes memory innerSignature = abi.encode(CoinbaseSmartWallet.SignatureWrapper(signatureHookOwnerIndex, ""));

        // Wrap everything in EIP6492 format
        bytes memory eip6492Signature = abi.encode(
            address(signatureHook), // prepareTarget (SignatureHook contract)
            prepareData, // prepareData (executeSignedCallsWithMessage call)
            innerSignature // inner signature ({ownerIndex}{empty})
        );
        eip6492Signature = abi.encodePacked(eip6492Signature, EIP6492_MAGIC_VALUE);

        return eip6492Signature;
    }

    function _createWithdrawRequest(SpendPermission memory spendPermission, uint128 nonceEntropy)
        internal
        view
        returns (MagicSpend.WithdrawRequest memory withdrawRequest)
    {
        // Get the hash and extract the portion we want
        bytes32 permissionHash = permit3.getHash(spendPermission);
        uint128 hashPortion = uint128(uint256(permissionHash));

        // Combine hash portion and entropy portion
        uint256 nonce = (uint256(nonceEntropy) << NONCE_HASH_BITS) | hashPortion;

        return MagicSpend.WithdrawRequest({
            asset: address(0),
            amount: 0,
            nonce: nonce,
            expiry: type(uint48).max,
            signature: hex""
        });
    }

    function _signWithdrawRequest(address account, MagicSpend.WithdrawRequest memory withdrawRequest)
        internal
        view
        returns (bytes memory signature)
    {
        bytes32 hash = magicSpend.getHash(account, withdrawRequest);
        return _sign(ownerPk, hash);
    }
}
