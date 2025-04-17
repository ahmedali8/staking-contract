// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23 <0.9.0;

abstract contract Constants {
    uint40 internal constant APRIL_1_2025 = 1_743_462_000;
    uint256 internal constant TOTAL_REWARD = 1_000_000 ether;
    uint256 internal constant REWARD_DURATION = 365 days;
    uint256 internal constant WAD = 1e18;
    uint256 internal constant ONE_MILLION_TOKENS = 1_000_000 ether;
    uint256 internal constant ONE_SECOND = 1;
}
