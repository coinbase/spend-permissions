// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {PublicERC6492Validator} from "../src/PublicERC6492Validator.sol";
import {PermissionManager} from "../src/PermissionManager.sol";
import {PermissionTypes} from "../src/PermissionTypes.sol";
import {CoinbaseSmartWalletSwapPolicy} from "../src/policies/CoinbaseSmartWalletSwapPolicy.sol";

import {MockCoinbaseSmartWallet} from "./mocks/MockCoinbaseSmartWallet.sol";
import {MockSwapTarget} from "./mocks/MockSwapTarget.sol";

interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract TestToken is ERC20 {
    constructor() ERC20("TestToken", "TST") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract CoinbaseSmartWalletSwapPolicyTest is Test {
    // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
    bytes32 internal constant DOMAIN_TYPEHASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    uint256 internal ownerPk = uint256(keccak256("owner"));
    address internal owner = vm.addr(ownerPk);
    uint256 internal spenderPk = uint256(keccak256("spender"));
    address internal spender = vm.addr(spenderPk);

    MockCoinbaseSmartWallet internal account;
    PublicERC6492Validator internal validator;
    PermissionManager internal sm;
    CoinbaseSmartWalletSwapPolicy internal swapPolicy;
    MockSwapTarget internal swapTarget;

    TestToken internal tokenIn;
    TestToken internal tokenOut;

    function setUp() public {
        account = new MockCoinbaseSmartWallet();
        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(owner);
        account.initialize(owners);

        validator = new PublicERC6492Validator();
        sm = new PermissionManager(validator);
        swapPolicy = new CoinbaseSmartWalletSwapPolicy(address(sm));
        swapTarget = new MockSwapTarget();

        vm.prank(owner);
        account.addOwnerAddress(address(sm));

        tokenIn = new TestToken();
        tokenOut = new TestToken();
    }

    function test_happyPath_mockSwapTarget() public {
        uint256 amountIn = 10 ether;
        uint256 minAmountOut = 3 ether;
        uint256 amountOut = 5 ether;

        tokenIn.mint(address(account), amountIn);
        tokenOut.mint(address(swapTarget), amountOut);

        CoinbaseSmartWalletSwapPolicy.Config memory cfg = CoinbaseSmartWalletSwapPolicy.Config({
            account: address(account),
            authority: spender,
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            swapTarget: address(swapTarget),
            swapSelector: MockSwapTarget.swap.selector,
            maxAmountIn: amountIn,
            minAmountOut: minAmountOut,
            validAfter: 0,
            validUntil: 0
        });
        bytes memory policyConfig = abi.encode(cfg);

        PermissionTypes.Install memory install = PermissionTypes.Install({
            account: address(account),
            policy: address(swapPolicy),
            policyConfigHash: keccak256(policyConfig),
            validAfter: 0,
            validUntil: 0,
            salt: 999
        });

        bytes memory userSig = _signInstall(install);
        sm.installPolicyWithSignature(install, policyConfig, userSig);

        bytes memory swapData = abi.encodeWithSelector(
            MockSwapTarget.swap.selector, address(tokenIn), address(tokenOut), address(account), amountIn, amountOut
        );
        bytes memory policyData =
            abi.encode(CoinbaseSmartWalletSwapPolicy.PolicyData({amountIn: amountIn, swapData: swapData}));

        uint256 beforeOut = tokenOut.balanceOf(address(account));
        vm.prank(spender);
        sm.execute(install, policyConfig, policyData, 1, uint48(block.timestamp + 60), hex"");
        uint256 afterOut = tokenOut.balanceOf(address(account));

        assertEq(afterOut - beforeOut, amountOut);
        assertTrue(afterOut - beforeOut >= minAmountOut);
    }

    /// @dev More “realistic” fork test: uses Base mainnet USDC/WETH + a deployed router.
    /// Set `RUN_FORK_TESTS=true` and configure the "base" RPC in `foundry.toml` to run this locally.
    function test_baseFork_likeProduction() public {
        bool runFork = vm.envOr("RUN_FORK_TESTS", false);
        if (!runFork) return;

        vm.createSelectFork("base");

        address usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        address weth = 0x4200000000000000000000000000000000000006;
        address router = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;

        MockCoinbaseSmartWallet forkAccount = new MockCoinbaseSmartWallet();
        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(owner);
        forkAccount.initialize(owners);

        PublicERC6492Validator forkValidator = new PublicERC6492Validator();
        PermissionManager forkSm = new PermissionManager(forkValidator);
        CoinbaseSmartWalletSwapPolicy forkSwapPolicy = new CoinbaseSmartWalletSwapPolicy(address(forkSm));

        vm.prank(owner);
        forkAccount.addOwnerAddress(address(forkSm));

        uint256 amountIn = 10_000_000; // 10 USDC (6 decimals)
        deal(usdc, address(forkAccount), amountIn, true);
        uint256 minAmountOut = 1;

        CoinbaseSmartWalletSwapPolicy.Config memory cfg = CoinbaseSmartWalletSwapPolicy.Config({
            account: address(forkAccount),
            authority: spender,
            tokenIn: usdc,
            tokenOut: weth,
            swapTarget: router,
            swapSelector: IUniswapV2Router.swapExactTokensForTokens.selector,
            maxAmountIn: amountIn,
            minAmountOut: minAmountOut,
            validAfter: 0,
            validUntil: 0
        });
        bytes memory policyConfig = abi.encode(cfg);

        PermissionTypes.Install memory install = PermissionTypes.Install({
            account: address(forkAccount),
            policy: address(forkSwapPolicy),
            policyConfigHash: keccak256(policyConfig),
            validAfter: 0,
            validUntil: 0,
            salt: 4242
        });

        vm.prank(address(forkAccount));
        forkSm.installPolicy(install, policyConfig);

        address[] memory path = new address[](2);
        path[0] = usdc;
        path[1] = weth;
        bytes memory swapData = abi.encodeWithSelector(
            IUniswapV2Router.swapExactTokensForTokens.selector, amountIn, 0, path, address(forkAccount), block.timestamp
        );
        bytes memory policyData =
            abi.encode(CoinbaseSmartWalletSwapPolicy.PolicyData({amountIn: amountIn, swapData: swapData}));

        uint256 beforeUsdc = IERC20(usdc).balanceOf(address(forkAccount));
        uint256 beforeWeth = IERC20(weth).balanceOf(address(forkAccount));

        vm.prank(spender);
        forkSm.execute(install, policyConfig, policyData, 1, uint48(block.timestamp + 60), hex"");

        uint256 afterUsdc = IERC20(usdc).balanceOf(address(forkAccount));
        uint256 afterWeth = IERC20(weth).balanceOf(address(forkAccount));

        assertEq(beforeUsdc - afterUsdc, amountIn);
        assertTrue(afterWeth >= beforeWeth + minAmountOut);
        assertEq(IERC20(usdc).allowance(address(forkAccount), router), 0);
    }

    function _signInstall(PermissionTypes.Install memory install) internal view returns (bytes memory) {
        bytes32 structHash = sm.getInstallStructHash(install);
        bytes32 digest = _hashTypedData(address(sm), "Permission Manager", "1", structHash);
        bytes32 replaySafeDigest = account.replaySafeHash(digest);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, replaySafeDigest);
        bytes memory signature = abi.encodePacked(r, s, v);
        return account.wrapSignature(0, signature);
    }

    function _hashTypedData(address verifyingContract, string memory name, string memory version, bytes32 structHash)
        internal
        view
        returns (bytes32)
    {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH, keccak256(bytes(name)), keccak256(bytes(version)), block.chainid, verifyingContract
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}

