// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29 <0.9.0;

import { BaseScript } from "./Base.s.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Staking } from "../src/Staking.sol";
import { TokenR } from "../src/tokens/TokenR.sol";
import { TokenT } from "../src/tokens/TokenT.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/guides/scripting-with-solidity
contract Deploy is BaseScript {
    function run(
        uint256 totalReward,
        uint256 rewardDuration
    )
        public
        broadcast
        returns (TokenT tokenT, TokenR tokenR, Staking staking)
    {
        tokenT = deployTokenT();
        tokenR = deployTokenR();
        staking = deployStakingReward(tokenT, tokenR, totalReward, rewardDuration);
    }

    function deployTokenT() public returns (TokenT tokenT) {
        tokenT = new TokenT();
        vm.label(address(tokenT), "TokenT");
    }

    function deployTokenR() public returns (TokenR tokenR) {
        tokenR = new TokenR();
        vm.label(address(tokenR), "TokenR");
    }

    function deployStakingReward(
        IERC20 stakedToken,
        IERC20 rewardToken,
        uint256 totalReward,
        uint256 rewardDuration
    )
        public
        returns (Staking staking)
    {
        staking = new Staking(stakedToken, rewardToken, totalReward, rewardDuration);
        vm.label(address(staking), "Staking");
    }
}
