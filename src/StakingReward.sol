// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Example:
// Alice stakes 100 tokenT at second 0
// Bob stakes 300 tokenT at second 10
// At second 20, both come to claim their rewards without unstaking
// According to 1 tokenT reward per second
// Alice's reward should be:
//   For 0-10 seconds: 10 * 100/100 = 10 tokenR
//   For 10-20 seconds: 10 * 100/400 = 2.5 tokenR
//   Total: 12.5 tokenR
// Bob's reward should be:
//   For 0-10 seconds: 10 * 0/100 = 0 tokenR
//   For 10-20 seconds: 10 * 300/400 = 7.5 tokenR
//   Total: 7.5 tokenR

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
    mapping(address user => uint256 stakedAmount) public stakedBalances;

    // unclaimed, accrued rewards in tokenR
    mapping(address user => uint256 rewardAmount) public pendingRewards;

    // last recorded cumulativeRewardPerToken for reward accounting
    mapping(address user => uint256 checkpoint) public userLastCumulativeRewardsPerToken;

    constructor(address _stakedToken, address _rewardToken, uint256 _totalReward, uint256 _rewardDuration) {
        stakedToken = IERC20(_stakedToken);
        rewardToken = IERC20(_rewardToken);
        rewardRatePerSecond = _totalReward / _rewardDuration;
        rewardsEndTime = block.timestamp + _rewardDuration;
    }

    function deposit(uint256 amount) external { }
    function withdraw(uint256 amount) external { }
    function claim() external { }

    function getCumulativeRewardPerToken(
        uint256 current,
        uint256 timeElapsed,
        uint256 rate,
        uint256 totalStaked
    )
        public
        pure
        returns (uint256)
    {
        if (totalStaked == 0) return current;
        uint256 _rewardIncrement = (timeElapsed * rate * PRECISION) / totalStaked;
        return current + _rewardIncrement;
    }

    function getUserPendingReward(
        uint256 userStake,
        uint256 globalAccumulator,
        uint256 userCheckpoint,
        uint256 alreadyPending
    )
        public
        pure
        returns (uint256)
    {
        uint256 _delta = globalAccumulator - userCheckpoint;
        uint256 _newReward = (userStake * _delta) / PRECISION;
        return alreadyPending + _newReward;
    }

    function _lastEffectiveTime() internal view returns (uint256) {
        return block.timestamp < rewardsEndTime ? block.timestamp : rewardsEndTime;
    }
}
