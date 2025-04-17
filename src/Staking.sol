// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { UserInfo } from "./types/DataTypes.sol";

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
    using SafeERC20 for IERC20;

    uint256 private constant RAY = 1e27;

    /// @notice The token that users stake (e.g., tokenT)
    IERC20 public immutable STAKED_TOKEN;

    /// @notice The token that users earn as a reward (e.g., tokenR)
    IERC20 public immutable REWARD_TOKEN;

    /// @notice Reward tokens emitted per second
    uint256 public immutable REWARD_RATE_PER_SECOND;

    uint256 public immutable REWARD_START_TIME;

    /// @notice Timestamp after which no new rewards are emitted
    uint256 public immutable REWARDS_END_TIME;

    /// @notice Last timestamp when global rewards were updated
    uint256 public lastRewardUpdateTime;

    /// @notice Accumulator: total rewards per token staked (scaled by 1e18)
    uint256 public rewardAccumulator;

    /// @notice Total amount of staked tokens across all users
    uint256 public totalTokensStaked;

    /// @notice Total amount of rewards that have been distributed
    uint256 public totalRewardsDistributed;

    mapping(address user => UserInfo info) public userInfos;

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
        REWARD_START_TIME = block.timestamp;
        REWARDS_END_TIME = block.timestamp + _rewardDuration;
    }

    /// @notice Deposit tokenT and start earning rewards
    /// @param amount Amount of tokenT to stake
    /// @dev This function will transfer the specified amount of tokenT from the user to the contract
    /// and update the user's staked balance.
    function deposit(uint128 amount) external {
        if (amount == 0) revert AmountIsZero();
        address _user = msg.sender;

        _sync(_user);
        userInfos[_user].stakedBalance += amount;
        totalTokensStaked += amount;

        // take tokens from the user
        STAKED_TOKEN.safeTransferFrom(_user, address(this), amount);
    }

    /// @notice Withdraw previously staked tokenT
    /// @param amount Amount of tokenT to withdraw
    /// @dev This function will transfer the specified amount of tokenT from the contract to the user
    /// and update the user's staked balance.
    function withdraw(uint128 amount) external {
        if (amount == 0) revert AmountIsZero();
        address _user = msg.sender;

        _sync(_user);
        userInfos[_user].stakedBalance -= amount;
        totalTokensStaked -= amount;

        // send tokens to the user
        STAKED_TOKEN.safeTransfer(_user, amount);
    }

    /// @notice Claim any accrued but unclaimed tokenR rewards
    /// @dev This function will transfer the pending rewards from the contract to the user
    /// and reset the user's pending rewards to zero.
    function claim() external {
        address _user = msg.sender;
        if (getTotalEarnedReward(_user) == 0) revert NoPendingRewardsToClaim();

        _sync(_user);
        uint256 _pendingReward = userInfos[_user].storedRewardBalance;
        userInfos[_user].storedRewardBalance = 0;
        totalRewardsDistributed += _pendingReward;

        REWARD_TOKEN.safeTransfer(_user, _pendingReward);
    }

    /// @dev Updates global and user-specific reward state
    function _sync(address user) internal {
        uint256 _updatedAccumulator = _calculateUpdatedAccumulator();

        // Update global reward state
        rewardAccumulator = _updatedAccumulator;
        lastRewardUpdateTime = _lastEffectiveTime();

        // Update user-specific reward state
        userInfos[user].storedRewardBalance = uint128(_calculateUserReward(user, _updatedAccumulator));
        userInfos[user].rewardCheckpoint = _updatedAccumulator;
    }

    /// @notice Calculates the cumulative reward per token staked.
    /// @dev This is the global tracker for how much reward (tokenR) is distributed per staked token (tokenT).
    /// @return rewardPerToken The cumulative reward per token (in tokenR) for the entire staking pool.
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
    function getCumulativeRewardPerToken() public view returns (uint256 rewardPerToken) {
        rewardPerToken = _calculateUpdatedAccumulator();
    }

    /// @notice Calculates the pending reward for a user.
    /// @dev Computes the difference between the user's last recorded global checkpoint and the latest one,
    /// then multiplies that delta by the user's current stake to compute newly earned rewards.
    /// Adds that to any previously pending reward that wasn't claimed yet.
    /// storedRewardBalances[user] + new reward since last sync (based on stake × delta)
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
    function getTotalEarnedReward(address user) public view returns (uint256 reward) {
        reward = _calculateUserReward(user, _calculateUpdatedAccumulator());
    }

    // Caps time at reward end
    function _lastEffectiveTime() internal view returns (uint256) {
        return block.timestamp < REWARDS_END_TIME ? block.timestamp : REWARDS_END_TIME;
    }

    // One-time rewardAccumulator computation
    function _calculateUpdatedAccumulator() internal view returns (uint256) {
        uint256 _timeElapsed = _lastEffectiveTime() - lastRewardUpdateTime;
        if (totalTokensStaked == 0) return rewardAccumulator;
        return rewardAccumulator + FullMath.mulDiv(_timeElapsed * REWARD_RATE_PER_SECOND, RAY, totalTokensStaked);
    }

    // Delta * stake + stored
    function _calculateUserReward(address user, uint256 updatedAccumulator) internal view returns (uint256) {
        UserInfo memory _userInfo = userInfos[user];
        uint256 _delta;
        unchecked {
            _delta = updatedAccumulator - _userInfo.rewardCheckpoint;
        }
        uint256 _newlyAccrued = FullMath.mulDiv(_userInfo.stakedBalance, _delta, RAY);
        return _userInfo.storedRewardBalance + _newlyAccrued;
    }
}
