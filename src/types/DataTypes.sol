// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

struct UserInfo {
    uint128 stakedBalance;
    uint128 storedRewardBalance;
    uint256 rewardCheckpoint;
}
