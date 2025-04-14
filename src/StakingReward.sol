// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StakingReward {
    // Used for scaling fixed point math (1e18 = 1 token)
    uint256 private constant PRECISION = 1e18;

    IERC20 public immutable stakedToken;
    IERC20 public immutable rewardToken;
    uint256 public immutable rewardRatePerSecond;
    uint256 public immutable rewardsEndTime;

    uint256 public lastRewardUpdateTime;
    uint256 public cumulativeRewardPerToken;
    uint256 public totalTokensStaked;

    // staked tokenT balance
    mapping(address staker => uint256 stakedAmount) public stakedBalances;

    // unclaimed, accrued rewards in tokenR
    mapping(address staker => uint256 rewardAmount) public pendingRewards;

    // last recorded cumulativeRewardPerToken for reward accounting
    mapping(address staker => uint256 checkpoint) public userLastCumulativeRewardsPerToken;

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
