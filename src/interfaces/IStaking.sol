// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UserInfo } from "../types/DataTypes.sol";

/// @title IStaking
/// @notice Interface for a time-weighted ERC-20 staking contract where users stake `tokenT` to earn rewards in `tokenR`
/// @dev Uses a reward accumulator pattern for precision; designed to support continuous reward emission over a fixed
/// period
interface IStaking {
    /*//////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a user deposits tokens into the staking contract
    /// @param user The user who deposited
    /// @param amount The amount of tokenT deposited
    event Deposited(address indexed user, uint256 amount);

    /// @notice Emitted when a user withdraws tokens from the staking contract
    /// @param user The user who withdrew
    /// @param amount The amount of tokenT withdrawn
    event Withdrawn(address indexed user, uint256 amount);

    /// @notice Emitted when a user claims accrued rewards
    /// @param user The user who claimed
    /// @param amount The amount of tokenR claimed
    event RewardsClaimed(address indexed user, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                              USER ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Stake a specified amount of tokenT to begin earning tokenR rewards
    /// @dev Transfers tokenT from the user to the contract; updates global and user-specific reward state
    /// @param amount Amount of tokenT to deposit (must be > 0)
    function deposit(uint128 amount) external;

    /// @notice Withdraw staked tokenT
    /// @dev Transfers tokenT from the contract back to the user; does not automatically claim rewards
    /// @param amount Amount of tokenT to withdraw (must be > 0 and ≤ user's staked balance)
    function withdraw(uint128 amount) external;

    /// @notice Claim any pending tokenR rewards accrued from staking
    /// @dev Transfers the user's reward balance to their wallet and resets the stored balance
    function claim() external;

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the user info (stake, rewards, checkpoint)
    /// @param user The address to query
    /// @return info The user's staking-related data
    function getUserInfo(address user) external view returns (UserInfo memory info);

    /// @notice Returns the global cumulative reward per staked token, accounting for time elapsed since last update
    /// @dev Used for precise pro-rata reward distribution across all stakers
    /// @return rewardPerToken The updated accumulator (scaled by 1e27 for RAY precision)
    function getCumulativeRewardPerToken() external view returns (uint256 rewardPerToken);

    /// @notice Computes total earned tokenR for a user (including both stored and newly accrued rewards)
    /// @dev View-only; does not change state or reset reward balances
    /// @param user The address of the user
    /// @return reward The full amount of tokenR the user can claim
    function getTotalEarnedReward(address user) external view returns (uint256 reward);
}
