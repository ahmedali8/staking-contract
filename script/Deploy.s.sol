// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29 <0.9.0;

import { BaseScript } from "./Base.s.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { StakingReward } from "../src/StakingReward.sol";
import { TokenR } from "../src/TokenR.sol";
import { TokenT } from "../src/TokenT.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/guides/scripting-with-solidity
contract Deploy is BaseScript {
    function run(
        uint256 totalReward,
        uint256 rewardDuration
    )
        public
        broadcast
        returns (TokenT tokenT, TokenR tokenR, StakingReward stakingReward)
    {
        tokenT = deployTokenT();
        tokenR = deployTokenR();
        stakingReward = deployStakingReward(tokenT, tokenR, totalReward, rewardDuration);
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
        returns (StakingReward stakingReward)
    {
        stakingReward = new StakingReward(stakedToken, rewardToken, totalReward, rewardDuration);
        vm.label(address(stakingReward), "StakingReward");
    }
}
