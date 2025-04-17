// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

/// @title Errors
/// @notice A library of custom error messages for the Staking contract
library Errors {
    /// @notice Emitted when the amount is zero
    error AmountIsZero();

    /// @notice Emitted when the user has no pending rewards to claim
    error NoPendingRewardsToClaim();

    /// @notice Emitted when the user has no staked tokens
    error NoStakedTokens();
}
