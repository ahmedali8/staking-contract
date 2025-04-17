// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

// INTERFACES
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IStaking } from "./interfaces/IStaking.sol";

// TYPES
import { UserInfo } from "./types/DataTypes.sol";

// LIBRARIES
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { Errors } from "./libraries/Errors.sol";

// ABSTRACT CONTRACTS
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Staking
/// @notice A time-weighted ERC-20 staking contract where users stake `tokenT` to earn rewards in `tokenR`
/// @dev Uses a reward accumulator pattern for precision; designed to support continuous reward emission over a fixed
/// period
contract Staking is ReentrancyGuard, IStaking {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                                      STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice The scaling factor for precision (1e27)
    uint256 private constant RAY = 1e27;

    /// @notice The token that users stake (e.g., tokenT)
    IERC20 public immutable STAKED_TOKEN;

    /// @notice The token that users earn as a reward (e.g., tokenR)
    IERC20 public immutable REWARD_TOKEN;

    /// @notice Reward tokens emitted per second
    uint256 public immutable REWARD_RATE_PER_SECOND;

    /// @notice Timestamp at which rewards start being distributed
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

    /// @notice Mapping of user address to user-specific staking and reward information
    mapping(address user => UserInfo info) private _userInfos;

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////////////////
                             EXTERNAL/PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IStaking
    function deposit(uint128 amount) external override nonReentrant {
        if (amount == 0) revert Errors.AmountIsZero();
        address _user = msg.sender;

        _sync(_user);
        _userInfos[_user].stakedBalance += amount;
        totalTokensStaked += amount;

        // take tokens from the user
        STAKED_TOKEN.safeTransferFrom(_user, address(this), amount);
    }

    /// @inheritdoc IStaking
    function withdraw(uint128 amount) external override nonReentrant {
        if (amount == 0) revert Errors.AmountIsZero();
        address _user = msg.sender;

        _sync(_user);
        _userInfos[_user].stakedBalance -= amount;
        totalTokensStaked -= amount;

        // send tokens to the user
        STAKED_TOKEN.safeTransfer(_user, amount);
    }

    /// @inheritdoc IStaking
    function claim() external override nonReentrant {
        address _user = msg.sender;
        if (getTotalEarnedReward(_user) == 0) revert Errors.NoPendingRewardsToClaim();

        _sync(_user);
        uint256 _pendingReward = _userInfos[_user].storedRewardBalance;
        _userInfos[_user].storedRewardBalance = 0;
        totalRewardsDistributed += _pendingReward;

        REWARD_TOKEN.safeTransfer(_user, _pendingReward);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                 PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Internal function that synchronizes the user's reward state.
     * @param user The address of the user to synchronize.
     *
     * Updates:
     * - `rewardAccumulator` (global)
     * - `lastRewardUpdateTime` (global)
     * - `_userInfos[user].storedRewardBalance`
     * - `_userInfos[user].rewardCheckpoint`
     */
    function _sync(address user) private {
        uint256 _updatedAccumulator = _calculateUpdatedAccumulator();

        // Update global reward state
        rewardAccumulator = _updatedAccumulator;
        lastRewardUpdateTime = _lastEffectiveTime();

        // Update user-specific reward state
        _userInfos[user].storedRewardBalance = uint128(_calculateUserReward(user, _updatedAccumulator));
        _userInfos[user].rewardCheckpoint = _updatedAccumulator;
    }

    // Caps time at reward end
    function _lastEffectiveTime() private view returns (uint256) {
        return block.timestamp < REWARDS_END_TIME ? block.timestamp : REWARDS_END_TIME;
    }

    // One-time rewardAccumulator computation
    function _calculateUpdatedAccumulator() private view returns (uint256) {
        uint256 _timeElapsed = _lastEffectiveTime() - lastRewardUpdateTime;
        if (totalTokensStaked == 0) return rewardAccumulator;
        return rewardAccumulator + FullMath.mulDiv(_timeElapsed * REWARD_RATE_PER_SECOND, RAY, totalTokensStaked);
    }

    // Delta * stake + stored
    function _calculateUserReward(address user, uint256 updatedAccumulator) private view returns (uint256) {
        UserInfo memory _userInfo = _userInfos[user];
        uint256 _delta;
        unchecked {
            _delta = updatedAccumulator - _userInfo.rewardCheckpoint;
        }
        uint256 _newlyAccrued = FullMath.mulDiv(_userInfo.stakedBalance, _delta, RAY);
        return _userInfo.storedRewardBalance + _newlyAccrued;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                 CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IStaking
    function getUserInfo(address user) external view override returns (UserInfo memory info) {
        info = _userInfos[user];
    }

    /// @inheritdoc IStaking
    function getCumulativeRewardPerToken() external view override returns (uint256 rewardPerToken) {
        rewardPerToken = _calculateUpdatedAccumulator();
    }

    /// @inheritdoc IStaking
    function getTotalEarnedReward(address user) public view override returns (uint256 reward) {
        reward = _calculateUserReward(user, _calculateUpdatedAccumulator());
    }
}
