// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TokenT is ERC20 {
    constructor() ERC20("TokenR", "TKR") {
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }
}
