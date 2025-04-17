// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UserInfo } from "../types/DataTypes.sol";

interface IStaking {
    /*//////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a user deposits tokens into the staking contract
    event Deposited(address indexed user, uint256 amount);

    /// @notice Emitted when a user withdraws tokens from the staking contract
    event Withdrawn(address indexed user, uint256 amount);

    /// @notice Emitted when a user claims rewards
    event RewardsClaimed(address indexed user, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                              USER ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit tokenT and start earning rewards
    /// @param amount Amount of tokenT to stake
    function deposit(uint128 amount) external;

    /// @notice Withdraw previously staked tokenT
    /// @param amount Amount of tokenT to withdraw
    function withdraw(uint128 amount) external;

    /// @notice Claim any accrued but unclaimed tokenR rewards
    function claim() external;

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates the cumulative reward per token staked
    /// @return rewardPerToken The cumulative reward per token (scaled by 1e27)
    function getCumulativeRewardPerToken() external view returns (uint256 rewardPerToken);

    /// @notice Calculates the pending reward for a user
    /// @param user The address of the user
    /// @return reward The total pending reward for the user
    function getTotalEarnedReward(address user) external view returns (uint256 reward);
}
