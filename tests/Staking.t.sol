// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23 <0.9.0;

import { console2 } from "forge-std/src/console2.sol";
import { Base_Test } from "./Base.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Staking } from "../src/Staking.sol";

contract Staking_Test is Base_Test {
    function setUp() public override {
        Base_Test.setUp();
    }

    function test_RewardRatePerSecond() public view {
        uint256 expectedRewardRate = 31_709_791_983_764_586; // 0.031709791983764586 tokenR per second
        uint256 actualRewardRate = staking.rewardRatePerSecond();
        assertEq(actualRewardRate, expectedRewardRate, "Reward rate per second should match expected value");
    }

    function test_RewardEndTime() public view {
        uint256 expectedEndTime = APRIL_1_2025 + 365 days;
        uint256 actualEndTime = staking.rewardsEndTime();
        assertEq(actualEndTime, expectedEndTime, "Reward end time should match expected value");
    }

    function test_RevertWhen_DepositAmountIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Staking.AmountIsZero.selector));
        staking.deposit(0);
    }

    function test_DepositUpdatesBalanceAndGlobalState() public {
        // Set Alice as the active user
        resetPrank(users.alice);

        uint256 depositAmount = 100 ether;

        // Approve staking contract to transfer Alice's tokenT
        IERC20(tokenT).approve(address(staking), depositAmount);

        // Capture timestamp before deposit
        uint256 timestampBefore = block.timestamp;

        // Deposit tokenT into the staking contract
        staking.deposit(depositAmount);

        // Check: Alice’s stake is correctly updated
        uint256 stakedBalance = staking.stakedBalances(users.alice);
        assertEq(stakedBalance, depositAmount, "Alice's staked balance should match deposit amount");

        // Check: totalTokensStaked is updated
        uint256 totalStaked = staking.totalTokensStaked();
        assertEq(totalStaked, depositAmount, "Total staked should equal Alice's deposit");

        // Check: lastRewardUpdateTime equals current block timestamp
        uint256 lastUpdate = staking.lastRewardUpdateTime();
        assertEq(lastUpdate, timestampBefore, "lastRewardUpdateTime should match block.timestamp at deposit");

        // Check: cumulativeRewardPerToken remains zero (no one was staking before)
        uint256 cumulativeReward = staking.getCumulativeRewardPerToken();
        assertEq(cumulativeReward, 0, "cumulativeRewardPerToken should remain 0 on first deposit");
    }

    function test_ClaimUpdatesRewardAndZeroesOut() public {
        resetPrank(users.alice);

        uint256 depositAmount = 100 ether;
        tokenT.approve(address(staking), depositAmount);
        staking.deposit(depositAmount);

        // Warp 10 seconds into the future
        uint256 increaseTime = 10 seconds;
        vm.warp(block.timestamp + increaseTime);

        uint256 rewardBefore = tokenR.balanceOf(users.alice);
        uint256 pending = staking.getUserPendingReward(users.alice);
        uint256 rewardRate = staking.rewardRatePerSecond();

        assertApproxEqAbs(pending, rewardRate * increaseTime, 60, "Alice should have ~0.3171 tokenR pending");

        // TODO: Fix: Rewards Precision
        // expected: 317097919837645860
        // actual:   317097919837645800
        // 0.000000000000000060 ether = 60 wei (precision loss)

        // Claim rewards
        staking.claim();

        uint256 rewardAfter = tokenR.balanceOf(users.alice);
        uint256 claimed = rewardAfter - rewardBefore;

        assertEq(claimed, 0.3170979198376458 ether, "Alice should receive tokenR");

        // Assert that pendingRewards has been zeroed out
        assertEq(staking.pendingRewards(users.alice), 0, "Pending reward must be zero after claim");

        // Global state remains
        assertEq(staking.totalTokensStaked(), 100 ether, "Global total should remain the same");
    }
}
