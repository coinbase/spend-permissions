// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IWalletPermit3Utility.sol";
import "./Permit3.sol";
import {console2} from "forge-std/console2.sol";

import {IERC1271} from "openzeppelin-contracts/contracts/interfaces/IERC1271.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";
import {PublicERC6492Validator} from "./PublicERC6492Validator.sol";
/// @title CoinbaseSmartWalletPermit3Utility
/// @notice Utility contract for handling Permit3 integrations with Coinbase Smart Wallet
contract CoinbaseSmartWalletPermit3Utility is IWalletPermit3Utility {
    /// @notice The Permit3 contract instance
    Permit3 public immutable permit3;

    /// @notice Magic value indicating a valid signature (from IERC1271)
    bytes4 constant MAGICVALUE = 0x1626ba7e;

    /// @notice ERC-7528 native token address convention (https://eips.ethereum.org/EIPS/eip-7528).
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice Transient flag for controlling isValidSignature behavior
    // bool transient private shouldValidate;

address transient private _currentAccount;
address transient private _currentToken;

    /// @notice Only allows the Permit3 contract to call the function
    error OnlyPermit3();

    /// @notice The account is not the current account being processed in Permit3
    error InvalidAccount();

    /// @notice The hash is not the current permission hash being processed in Permit3
    error InvalidHash();

    /// @notice The signature is not valid
    error InvalidSignature();

    /// @notice Constructor to set the Permit3 contract address
    /// @param _permit3 Address of the Permit3 contract
    constructor(Permit3 _permit3) {
        permit3 = _permit3;
    }

    /// @notice Ensures only the Permit3 contract can call the function
    modifier onlyPermit3() {
        if (msg.sender != address(permit3)) revert OnlyPermit3();
        _;
    }

    /// @notice Implementation of IERC1271 isValidSignature
    /// @dev Behavior controlled by transient storage flag
    /// @dev When flag is off: returns failure
    /// @dev When flag is on: unwraps outer signature and forwards to wallet
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        console2.log("isValidSignature from utility");
        console2.log("Hash passed to utility:", uint256(hash));
        
        // Get the raw permission hash from Permit3
        bytes32 permissionHash = permit3.getCurrentPermissionHash();
        console2.log("Current permission hash from Permit3:", uint256(permissionHash));
        
        // Reconstruct the replay-safe hash that we expect
        bytes32 cbswDomainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Coinbase Smart Wallet")),
                keccak256(bytes("1")),
                block.chainid,
                permit3.getCurrentAccount()
            )
        );
        bytes32 expectedHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                cbswDomainSeparator,
                keccak256(abi.encode(keccak256("CoinbaseSmartWalletMessage(bytes32 hash)"), permissionHash))
            )
        );
        console2.log("Expected replay-safe hash:", uint256(expectedHash));
        
        if (hash != expectedHash) revert InvalidHash();
        
        // Forward the ORIGINAL permission hash to the wallet's signature validation
        bytes4 magicValue = CoinbaseSmartWallet(payable(permit3.getCurrentAccount())).isValidSignature(permissionHash, signature);
        if (magicValue != MAGICVALUE) {
            revert InvalidSignature();
        }

        console2.log("Current account:", permit3.getCurrentAccount());
        console2.log("Current token:", permit3.getCurrentToken());
        // THESE ARE NOT BEING SET BECAUSE THIS METHOD IS CALLED STATICALLY
        // _currentAccount = permit3.getCurrentAccount();
        // _currentToken = permit3.getCurrentToken();

// INSTEAD, let's check here whether the criteria we're trying to set up by failing here is 
// already met. In the case of native token, that would be the registration of the utility contract.
// and in the case of ERC20, that would be the approval of the ERC20 token.

        if (permit3.getCurrentToken() == NATIVE_TOKEN) {
            console2.log("Native token case");
            // Native token case
            // check if the utility contract is registered for the current account
            if (permit3.accountToUtility(permit3.getCurrentAccount()) != address(this)) {
                console2.log("Utility contract not registered - returning 0xffffffff");
                return 0xffffffff;
            }
        } else {
            console2.log("ERC20 case");
            // ERC20 case
            // check if the ERC20 token is approved for infinite spending
            if (IERC20(permit3.getCurrentToken()).allowance(permit3.getCurrentAccount(), address(permit3)) < type(uint256).max) {
                console2.log("ERC20 token not approved for infinite spending - returning 0xffffffff");
                return 0xffffffff;
            }
        }

        return MAGICVALUE;
    }

    /// @notice Approves an ERC20 token for infinite spending by Permit3
    /// @dev Calls execute on the CoinbaseSmartWallet to approve Permit3 for infinite spending
    /// @param token The ERC20 token to approve
    /// @param account The CoinbaseSmartWallet account granting the approval
    function approveERC20(address token, address account) external onlyPermit3 {
        if (account != permit3.getCurrentAccount()) revert InvalidAccount();
        // Create the approval calldata for the ERC20 token
        bytes memory approvalCalldata =
            abi.encodeWithSelector(IERC20.approve.selector, address(permit3), type(uint256).max);

        // Call execute on the CoinbaseSmartWallet
        CoinbaseSmartWallet(payable(account)).execute(
            token, // target (the ERC20 token contract)
            0, // value (no ETH needed for approve)
            approvalCalldata
        );
        // shouldValidate = true;
    }

    /// @notice Registers this utility contract with Permit3
    function registerPermit3Utility() external {
        console2.log("registerPermit3Utility from utility");
        console2.log("Current account:", permit3.getCurrentAccount());
        bytes memory registerCalldata =
            abi.encodeWithSelector(Permit3.registerPermit3Utility.selector, permit3.getCurrentAccount(), address(this));

        CoinbaseSmartWallet(payable(permit3.getCurrentAccount())).execute(address(permit3), 0, registerCalldata);
    }

    /// @notice Sends native tokens (ETH) from the account to Permit3
    /// @dev Calls execute on the CoinbaseSmartWallet to send ETH to Permit3
    /// @inheritdoc IWalletPermit3Utility
    function spendNativeToken(address account, uint256 value) external override onlyPermit3 {
        if (account != permit3.getCurrentAccount()) revert InvalidAccount();
        CoinbaseSmartWallet(payable(account)).execute(
            address(permit3), // target (the Permit3 contract)
            value, // value (amount of ETH to send)
            "" // data (empty since we're just sending ETH)
        );
        // shouldValidate = true;
    }
}
