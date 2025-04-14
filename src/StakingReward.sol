// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StakingReward {
    IERC20 public immutable stakedToken;
    IERC20 public immutable rewardToken;
    uint256 public immutable rewardRatePerSecond;
    uint256 public immutable rewardsEndTime;

    constructor(address _stakedToken, address _rewardToken, uint256 _totalReward, uint256 _rewardDuration) {
        stakedToken = IERC20(_stakedToken);
        rewardToken = IERC20(_rewardToken);
        rewardRatePerSecond = _totalReward / _rewardDuration;
        rewardsEndTime = block.timestamp + _rewardDuration;
    }

    function deposit(uint256 amount) external { }
    function withdraw(uint256 amount) external { }
    function claim() external { }
}
