// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23 <0.9.0;

import { console2 } from "forge-std/src/console2.sol";
import { Base_Test } from "./Base.t.sol";
import { stdError } from "forge-std/src/StdError.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { Staking } from "../src/Staking.sol";

contract Staking_Test is Base_Test {
    function setUp() public override {
        Base_Test.setUp();
    }

    function test_RewardRatePerSecond() public view {
        uint256 expectedRewardRate = 31_709_791_983_764_586; // 0.031709791983764586 tokenR per second
        uint256 actualRewardRate = staking.REWARD_RATE_PER_SECOND();
        assertEq(actualRewardRate, expectedRewardRate, "Reward rate per second should match expected value");
    }

    function test_RewardEndTime() public view {
        uint256 expectedEndTime = APRIL_1_2025 + 365 days;
        uint256 actualEndTime = staking.REWARDS_END_TIME();
        assertEq(actualEndTime, expectedEndTime, "Reward end time should match expected value");
    }

    function test_GetUserPendingRewardReturnsZeroWithoutDeposit() public view {
        uint256 pending = staking.getTotalEarnedReward(users.eve);
        assertEq(pending, 0, "User with no deposit should have 0 pending rewards");
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

        // Check: Alice's stake is correctly updated
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

    function test_WithdrawReducesBalance() public {
        resetPrank(users.alice);

        uint256 depositAmount = 100 ether;
        tokenT.approve(address(staking), depositAmount);
        staking.deposit(depositAmount);

        // Warp 5 seconds (so some rewards accumulate)
        vm.warp(block.timestamp + 5);

        // Withdraw half
        uint256 withdrawAmount = 50 ether;
        staking.withdraw(withdrawAmount);

        // Check balances
        assertEq(staking.stakedBalances(users.alice), 50 ether, "Alice's stake should reduce");
        assertEq(staking.totalTokensStaked(), 50 ether, "Total staked should reduce");

        // Reward must not be auto-claimed
        uint256 pending = staking.storedRewardBalances(users.alice);
        assertGt(pending, 0, "Reward should still be pending after withdraw");

        // Claim to finalize test
        staking.claim();
        assertEq(staking.storedRewardBalances(users.alice), 0, "Should be zero after explicit claim");
    }

    function test_RevertWhen_WithdrawWithoutDeposit() public {
        // Eve has never deposited
        resetPrank(users.eve);

        // Expect panic: arithmetic underflow or overflow
        vm.expectRevert(stdError.arithmeticError);
        staking.withdraw(1 ether);
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
        uint256 pending = staking.getTotalEarnedReward(users.alice);
        uint256 rewardRate = staking.REWARD_RATE_PER_SECOND();

        assertEq(pending, rewardRate * increaseTime, "Alice should have ~0.3171 tokenR pending");

        // Claim rewards
        staking.claim();

        uint256 rewardAfter = tokenR.balanceOf(users.alice);
        uint256 claimed = rewardAfter - rewardBefore;

        uint256 expectedReward = 317_097_919_837_645_860;
        assertEq(claimed, expectedReward, "Alice should receive tokenR");

        // Assert that storedRewardBalance has been zeroed out
        assertEq(staking.storedRewardBalances(users.alice), 0, "Pending reward must be zero after claim");

        // Global state remains
        assertEq(staking.totalTokensStaked(), 100 ether, "Global total should remain the same");
    }

    function test_ClaimThenReDepositUpdatesCheckpoint() public {
        resetPrank(users.alice);
        uint256 amount = 100 ether;
        tokenT.approve(address(staking), amount);
        staking.deposit(amount);

        vm.warp(block.timestamp + 10);
        staking.claim();

        uint256 checkpointAfterClaim = staking.userRewardCheckpoints(users.alice);

        vm.warp(block.timestamp + 5);

        tokenT.approve(address(staking), amount);
        staking.deposit(amount);

        uint256 checkpointAfterReDeposit = staking.userRewardCheckpoints(users.alice);
        assertGt(checkpointAfterReDeposit, checkpointAfterClaim, "Checkpoint should be updated after re-deposit");
    }

    function test_RevertWhen_ClaimWithoutPendingRewards() public {
        // Alice has deposited but no rewards have been accrued
        resetPrank(users.alice);

        uint256 depositAmount = 100 ether;
        tokenT.approve(address(staking), depositAmount);
        staking.deposit(depositAmount);

        assertEq(staking.storedRewardBalances(users.alice), 0, "Alice should have no pending rewards");

        vm.expectRevert(abi.encodeWithSelector(Staking.NoPendingRewardsToClaim.selector));
        staking.claim();
    }

    function test_AccumulatorIncreasesOverTime() public {
        tokenT.approve(address(staking), 100 ether);
        staking.deposit(100 ether);

        uint256 acc1 = staking.getCumulativeRewardPerToken();
        vm.warp(block.timestamp + 5);
        uint256 acc2 = staking.getCumulativeRewardPerToken();

        assertGe(acc2, acc1, "Accumulator must not decrease over time");
    }

    function test_RewardStopsAfterEnd() public {
        tokenT.approve(address(staking), 100 ether);
        staking.deposit(100 ether);

        // Warp past rewards end
        vm.warp(staking.REWARDS_END_TIME() + 100);

        uint256 accBefore = staking.getCumulativeRewardPerToken();
        vm.warp(block.timestamp + 10);
        uint256 accAfter = staking.getCumulativeRewardPerToken();

        assertEq(accAfter, accBefore, "Accumulator should stop increasing after rewards end");

        uint256 pending = staking.getTotalEarnedReward(users.sender);
        assertGt(pending, 0, "Should still be able to claim reward after end");

        staking.claim();
        assertEq(staking.storedRewardBalances(users.sender), 0, "Claim should clear pending rewards");
    }

    function test_PrecisionWithSmallStakes() public {
        tokenT.approve(address(staking), 1);
        staking.deposit(1); // 1 wei

        vm.warp(block.timestamp + 10);
        uint256 reward = staking.getTotalEarnedReward(users.sender);
        uint256 expectedReward = 317_097_919_837_645_860;
        assertEq(reward, expectedReward, "Should earn non-zero reward even for small stake");
    }

    function test_MultiUser_StaggeredDepositsRewardSplit() public {
        // === Time 0 ===
        resetPrank(users.alice);
        uint256 aliceStake = 100 ether;
        tokenT.approve(address(staking), aliceStake);
        staking.deposit(aliceStake);

        // Warp to t = 10s
        vm.warp(block.timestamp + 10);

        // === Time 10s ===
        resetPrank(users.bob);
        uint256 bobStake = 300 ether;
        tokenT.approve(address(staking), bobStake);
        staking.deposit(bobStake);

        // Warp to t = 20s
        vm.warp(block.timestamp + 10);

        uint256 rewardRate = staking.REWARD_RATE_PER_SECOND();

        uint256 expectedAliceReward = 396_372_399_797_057_325;
        uint256 expectedBobReward = 237_823_439_878_234_395;

        // === Alice Claims ===
        resetPrank(users.alice);
        uint256 alicePending = staking.getTotalEarnedReward(users.alice);
        staking.claim();
        uint256 aliceReceived = tokenR.balanceOf(users.alice);

        /*
        alice stakes: 100e18 tokens
        bob stakes: 300e18 tokens

        reward rate: 31709791983764586 tokenR / sec

        Period      | Who   | Stake    | Reward Calculation                                    | Result (wei)
        ------------|-------|----------|-------------------------------------------------------|------------------
        0s - 10s    | Alice | 100e18   | 10s * 31709791983764586                               | 317097919837645860
        10s - 20s   | Alice | 100e18   | (10s * 31709791983764586 * 100e18 / 400e18)           | 79274479959411465
        10s - 20s   | Bob   | 300e18   | (10s * 31709791983764586 * 300e18 / 400e18)           | 237823439878234395

        Total Alice |       |          | 317097919837645860 + 79274479959411465                | 396372399797057325
        Total Bob   |       |          | 237823439878234395                                    | 237823439878234395
        Distributed | All   |          | 396372399797057325 + 237823439878234395               | 634195839675291720
        */

        assertEq(alicePending, expectedAliceReward, "Alice pending reward mismatch");
        assertEq(aliceReceived, expectedAliceReward, "Alice received reward mismatch");

        // === Bob Claims ===
        resetPrank(users.bob);
        uint256 bobPending = staking.getTotalEarnedReward(users.bob);
        staking.claim();
        uint256 bobReceived = tokenR.balanceOf(users.bob);

        assertEq(bobPending, expectedBobReward, "Bob pending reward mismatch");
        assertEq(bobReceived, expectedBobReward, "Bob received reward mismatch");

        // === Sanity Check ===
        uint256 totalDistributed = aliceReceived + bobReceived;
        assertApproxEqAbs(totalDistributed, rewardRate * 20, 1e12, "Total distributed rewards mismatch");

        // === Total Rewards Distributed ===
        uint256 totalRewardsDistributed = staking.totalRewardsDistributed();
        uint256 expectedTotalRewardsDistributed = 634_195_839_675_291_720;
        assertEq(totalRewardsDistributed, expectedTotalRewardsDistributed, "Total rewards distributed mismatch");
    }

    function test_MultipleDepositsWithGaps() public {
        // === Time 0: Alice deposits ===
        resetPrank(users.alice);
        uint256 aliceStake = 100 ether;
        tokenT.approve(address(staking), aliceStake);
        staking.deposit(aliceStake);

        // Warp to t = 30
        vm.warp(block.timestamp + 30);

        // === Time 30: Alice withdraws all ===
        staking.withdraw(aliceStake);

        // === t = 30–40: No staking ===
        vm.warp(block.timestamp + 10);

        // === Time 40: Bob deposits ===
        resetPrank(users.bob);
        uint256 bobStake = 200 ether;
        tokenT.approve(address(staking), bobStake);
        staking.deposit(bobStake);

        // Warp to t = 70 (30s passed)
        vm.warp(block.timestamp + 30);

        // === Time 70: Eve deposits (now Bob + Eve are both staked) ===
        resetPrank(users.eve);
        uint256 eveStake = 300 ether;
        tokenT.approve(address(staking), eveStake);
        staking.deposit(eveStake);

        // Warp to t = 100 (30s passed)
        vm.warp(block.timestamp + 30);

        uint256 rewardRate = staking.REWARD_RATE_PER_SECOND();

        // === Expected Calculations ===
        // Alice: 0–30s
        uint256 expectedAlice = rewardRate * 30;

        // Bob: 40–70s alone
        uint256 bobPart1 = rewardRate * 30;

        // Bob: 70–100s with Eve (200/500 of rewards)
        uint256 bobPart2 = FullMath.mulDiv(rewardRate * 30, 200 ether, 500 ether);
        uint256 expectedBob = bobPart1 + bobPart2;

        // Eve: 70–100s with Bob (300/500 of rewards)
        uint256 expectedEve = FullMath.mulDiv(rewardRate * 30, 300 ether, 500 ether);

        // === Alice Claim ===
        resetPrank(users.alice);
        uint256 aliceEarned = staking.getTotalEarnedReward(users.alice);
        assertEq(aliceEarned, expectedAlice, "Alice reward mismatch");
        staking.claim();
        assertEq(tokenR.balanceOf(users.alice), expectedAlice, "Alice balance mismatch");

        // === Bob Claim ===
        resetPrank(users.bob);
        uint256 bobEarned = staking.getTotalEarnedReward(users.bob);
        assertEq(bobEarned, expectedBob, "Bob reward mismatch");
        staking.claim();
        assertEq(tokenR.balanceOf(users.bob), expectedBob, "Bob balance mismatch");

        // === Eve Claim ===
        resetPrank(users.eve);
        uint256 eveEarned = staking.getTotalEarnedReward(users.eve);
        assertEq(eveEarned, expectedEve, "Eve reward mismatch");
        staking.claim();
        assertEq(tokenR.balanceOf(users.eve), expectedEve, "Eve balance mismatch");

        // === Total Check ===
        uint256 expectedTotal = expectedAlice + expectedBob + expectedEve;
        assertEq(staking.totalRewardsDistributed(), expectedTotal, "Total rewards distributed mismatch");

        /*
        alice stakes: 100e18 tokens
        bob stakes: 200e18 tokens
        eve stakes: 300e18 tokens

        reward rate: 31709791983764586 tokenR / sec

        Period      | Who         | Stake   | Reward Calculation                              | Result (wei)
        ------------|-------------|---------|-------------------------------------------------|-------------------------
        0s–30s      | Alice       | 100e18  | 30s * 31709791983764586                         | 951293759512937580
        30s–40s     | None        | 0       | No staking                                      | 0
        40s–70s     | Bob         | 200e18  | 30s * 31709791983764586                         | 951293759512937580
        70s–100s    | Bob         | 200/500 | 30s * 31709791983764586 * 200e18 / 500e18       | 380517503805175032
        70s–100s    | Eve         | 300/500 | 30s * 31709791983764586 * 300e18 / 500e18       | 570776255707762548

        Total Alice               |         |                                                 | 951293759512937580
        Total Bob                 |         | 951293759512937580 + 380517503805175032         | 1331811263318112612
        Total Eve                 |         |                                                 | 570776255707762548
        Total Distributed         |         |                                                 | 2853881278538812740
        */
    }
}
