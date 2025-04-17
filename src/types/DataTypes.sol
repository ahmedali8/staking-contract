// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

/**
 * @notice UserInfo struct used for storing user-specific staking and reward information
 * @dev This struct is designed to pack two uint128 values into a single storage slot for gas efficiency
 *
 * @param stakedBalance The amount of tokenT currently staked by the user
 * @param storedRewardBalance The amount of unclaimed, accrued rewards in tokenR accumulated by the user
 * How much reward this user has earned up until the last time we updated their state?
 * @param rewardCheckpoint The last recorded value of the global reward accumulator when user's rewards were last
 * updated
 */
struct UserInfo {
    // -- SLOT 0 -- //
    uint128 stakedBalance;
    uint128 storedRewardBalance;
    // -- SLOT 1 -- //
    uint256 rewardCheckpoint;
}
