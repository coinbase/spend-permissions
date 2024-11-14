// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {MockERC20} from "solady/../test/utils/mocks/MockERC20.sol";

contract MockERC20MissingReturn is MockERC20 {
    constructor(string memory name_, string memory symbol_, uint8 decimals_) MockERC20(name_, symbol_, decimals_) {}

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        super.transfer(to, amount); // ignore return value
        assembly {
            return(0, 0)
        }
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        super.transferFrom(from, to, amount); // ignore return value
        assembly {
            return(0, 0)
        }
    }
}
