// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @notice Minimal swap target for tests. Pulls `amountIn` from msg.sender and pushes `amountOut` to `recipient`.
contract MockSwapTarget {
    error TransferFromFailed();
    error TransferFailed();

    function swap(address tokenIn, address tokenOut, address recipient, uint256 amountIn, uint256 amountOut) external {
        bool okIn = IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        if (!okIn) revert TransferFromFailed();

        bool okOut = IERC20(tokenOut).transfer(recipient, amountOut);
        if (!okOut) revert TransferFailed();
    }
}

