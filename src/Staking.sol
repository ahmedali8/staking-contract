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

contract Staking {
    // Used for scaling fixed point math (1e18 = 1 token)
    uint256 private constant PRECISION = 1e18;

    /// @notice The token that users stake (e.g., tokenT)
    IERC20 public immutable STAKED_TOKEN;

    /// @notice The token that users earn as a reward (e.g., tokenR)
    IERC20 public immutable REWARD_TOKEN;

    /// @notice Reward tokens emitted per second
    uint256 public immutable REWARD_RATE_PER_SECOND;

    /// @notice Timestamp after which no new rewards are emitted
    uint256 public immutable REWARDS_END_TIME;

    /// @notice Last timestamp when global rewards were updated
    uint256 public lastRewardUpdateTime;

    /// @notice Accumulator: total rewards per token staked (scaled by 1e18)
    uint256 public rewardAccumulator;

    /// @notice Total amount of staked tokens across all users
    uint256 public totalTokensStaked;

    // staked tokenT balance
    mapping(address user => uint256 stakedAmount) public stakedBalances;

    // unclaimed, accrued rewards in tokenR
    // How much reward this user has earned up until the last time we updated their state?
    mapping(address user => uint256 rewardAmount) public storedRewardBalance;

    // last recorded rewardAccumulator for reward accounting
    mapping(address user => uint256 checkpoint) public userRewardCheckpoint;

    error AmountIsZero();
    error NoPendingRewardsToClaim();
    error NoStakedTokens();

    /// @notice Constructor to initialize the staking contract.
    /// @param _stakedToken The token that users will stake (e.g., tokenT)
    /// @param _rewardToken The token that users will earn as a reward (e.g., tokenR)
    /// @param _totalReward The total amount of reward tokens to be distributed
    /// @param _rewardDuration The duration (in seconds) over which the rewards will be distributed
    constructor(IERC20 _stakedToken, IERC20 _rewardToken, uint256 _totalReward, uint256 _rewardDuration) {
        STAKED_TOKEN = _stakedToken;
        REWARD_TOKEN = _rewardToken;
        REWARD_RATE_PER_SECOND = _totalReward / _rewardDuration;
        REWARDS_END_TIME = block.timestamp + _rewardDuration;
    }

    /// @notice Deposit tokenT and start earning rewards
    /// @param amount Amount of tokenT to stake
    /// @dev This function will transfer the specified amount of tokenT from the user to the contract
    /// and update the user's staked balance.
    function deposit(uint256 amount) external {
        if (amount == 0) revert AmountIsZero();

        _sync(msg.sender);
        stakedBalances[msg.sender] += amount;
        totalTokensStaked += amount;

        // take tokens from the user
        STAKED_TOKEN.transferFrom(msg.sender, address(this), amount);
    }

    /// @notice Withdraw previously staked tokenT
    /// @param amount Amount of tokenT to withdraw
    /// @dev This function will transfer the specified amount of tokenT from the contract to the user
    /// and update the user's staked balance.
    function withdraw(uint256 amount) external {
        if (amount == 0) revert AmountIsZero();

        _sync(msg.sender);
        stakedBalances[msg.sender] -= amount;
        totalTokensStaked -= amount;

        // send tokens to the user
        STAKED_TOKEN.transfer(msg.sender, amount);

        // TODO: if the user is withdrawing full amount then send him the rewards as well
    }

    /// @notice Claim any accrued but unclaimed tokenR rewards
    /// @dev This function will transfer the pending rewards from the contract to the user
    /// and reset the user's pending rewards to zero.
    function claim() external {
        if (stakedBalances[msg.sender] == 0) revert NoStakedTokens();
        if (getTotalEarnedReward(msg.sender) == 0) revert NoPendingRewardsToClaim();

        _sync(msg.sender);

        uint256 _pendingReward = storedRewardBalance[msg.sender];
        storedRewardBalance[msg.sender] = 0;

        REWARD_TOKEN.transfer(msg.sender, _pendingReward);
    }

    /// @dev Updates global and user-specific reward state
    function _sync(address user) internal {
        uint256 _timeNow = _lastEffectiveTime();

        // Update global reward accumulator
        rewardAccumulator = getCumulativeRewardPerToken();
        lastRewardUpdateTime = _timeNow;

        // Update user-specific reward state
        storedRewardBalance[user] = getTotalEarnedReward(user);

        userRewardCheckpoint[user] = rewardAccumulator;
    }

    /// @notice Calculates the cumulative reward per token staked.
    /// @dev This is the global tracker for how much reward (tokenR) is distributed per staked token (tokenT).
    /// @return The cumulative reward per token (in tokenR) for the entire staking pool.
    ///
    /// Example:
    /// - Alice stakes 100 tokenT at second 0
    /// - At second 10, Bob stakes 300 tokenT
    /// - At second 20, cumulative rewards = 20 tokenR (1 tokenR/sec)
    ///
    /// Time 0-10 (only Alice):
    ///   - Total Staked: 100
    ///   - Rewards: 10 tokenR -> rewardPerToken = 10 / 100 = 0.1 -> 0.1e18
    ///
    /// Time 10-20 (Alice 100 + Bob 300 = 400):
    ///   - Rewards: 10 tokenR
    ///   - rewardPerToken = 10 / 400 = 0.025 -> 0.025e18
    ///
    /// Total rewardAccumulator = 0.1e18 + 0.025e18 = 0.125e18
    function getCumulativeRewardPerToken() public view returns (uint256) {
        uint256 _timeElapsed = _lastEffectiveTime() - lastRewardUpdateTime;
        if (totalTokensStaked == 0) return rewardAccumulator;
        uint256 _rewardIncrement = (_timeElapsed * REWARD_RATE_PER_SECOND * PRECISION) / totalTokensStaked;
        return rewardAccumulator + _rewardIncrement;
    }

    /// @notice Calculates the pending reward for a user.
    /// @dev Computes the difference between the user's last recorded global checkpoint and the latest one,
    /// then multiplies that delta by the user's current stake to compute newly earned rewards.
    /// Adds that to any previously pending reward that wasn't claimed yet.
    /// storedRewardBalance[user] + new reward since last sync (based on stake × delta)
    ///
    /// Example:
    /// Continuing from above:
    ///   - At second 20:
    ///   - rewardAccumulator = 0.125e18
    ///
    /// Alice:
    ///   - staked 100 tokenT
    ///   - checkpoint = 0 (she staked at time = 0)
    ///   - delta = 0.125e18 - 0 = 0.125e18
    ///   - newReward = 100 * 0.125e18 / 1e18 = 12.5 tokenR
    ///
    /// Bob:
    ///   - staked 300 tokenT
    ///   - checkpoint = 0.1e18 (he staked at time = 10)
    ///   - delta = 0.125e18 - 0.1e18 = 0.025e18
    ///   - newReward = 300 * 0.025e18 / 1e18 = 7.5 tokenR
    function getTotalEarnedReward(address user) public view returns (uint256) {
        uint256 _rewardDelta = getCumulativeRewardPerToken() - userRewardCheckpoint[user];
        uint256 _newlyAccrued = (stakedBalances[user] * _rewardDelta) / PRECISION;
        return storedRewardBalance[user] + _newlyAccrued;
    }

    function _lastEffectiveTime() internal view returns (uint256) {
        return block.timestamp < REWARDS_END_TIME ? block.timestamp : REWARDS_END_TIME;
    }
}
