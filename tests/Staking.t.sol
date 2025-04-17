// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23 <0.9.0;

import { Base_Test } from "./Base.t.sol";
import { stdError } from "forge-std/src/StdError.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { Staking } from "../src/Staking.sol";
import { Errors } from "../src/libraries/Errors.sol";

contract Staking_Test is Base_Test {
    function setUp() public override {
        Base_Test.setUp();
    }

    function test_RewardRateMatchesExpectedValue() public view {
        uint256 expectedRewardRate = 31_709_791_983_764_586; // 0.031709791983764586 tokenR per second
        uint256 actualRewardRate = staking.REWARD_RATE_PER_SECOND();
        assertEq(actualRewardRate, expectedRewardRate, "Reward rate per second should match expected value");
    }

    function test_RewardEndTimeMatchesExpectedTimestamp() public view {
        uint256 expectedEndTime = APRIL_1_2025 + 365 days;
        uint256 actualEndTime = staking.REWARDS_END_TIME();
        assertEq(actualEndTime, expectedEndTime, "Reward end time should match expected value");
    }

    function test_PendingRewardIsZeroForUserWithoutDeposit() public view {
        uint256 pending = staking.getTotalEarnedReward(users.eve);
        assertEq(pending, 0, "User with no deposit should have 0 pending rewards");
    }

    function test_RevertWhen_UserDepositsZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AmountIsZero.selector));
        staking.deposit(0);
    }

    function test_DepositIncreasesUserBalanceAndTotalStakedCorrectly() public {
        // Set Alice as the active user
        resetPrank(users.alice);

        uint128 depositAmount = 100 ether;

        // Approve staking contract to transfer Alice's tokenT
        IERC20(tokenT).approve(address(staking), depositAmount);

        // Capture timestamp before deposit
        uint256 timestampBefore = block.timestamp;

        // Deposit tokenT into the staking contract
        staking.deposit(depositAmount);

        // Check: Alice's stake is correctly updated
        (uint128 stakedBalance,,) = staking.userInfos(users.alice);
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

    function test_WithdrawReducesUserAndTotalStakedBalancesAndPreservesRewards() public {
        resetPrank(users.alice);

        uint128 depositAmount = 100 ether;
        tokenT.approve(address(staking), depositAmount);
        staking.deposit(depositAmount);

        // Warp 5 seconds (so some rewards accumulate)
        vm.warp(block.timestamp + 5);

        // Withdraw half
        uint128 withdrawAmount = 50 ether;
        staking.withdraw(withdrawAmount);

        // Check balances
        (uint128 stakedBalance, uint128 pendingReward,) = staking.userInfos(users.alice);

        assertEq(stakedBalance, 50 ether, "Alice's stake should reduce");
        assertEq(staking.totalTokensStaked(), 50 ether, "Total staked should reduce");

        // Reward must not be auto-claimed
        assertGt(pendingReward, 0, "Reward should still be pending after withdraw");

        // Claim to finalize test
        staking.claim();
        (, uint128 pendingRewardAfterClaim,) = staking.userInfos(users.alice);
        assertEq(pendingRewardAfterClaim, 0, "Should be zero after explicit claim");
    }

    function test_RevertWhen_UserWithdrawsWithoutDeposit() public {
        // Eve has never deposited
        resetPrank(users.eve);

        // Expect panic: arithmetic underflow or overflow
        vm.expectRevert(stdError.arithmeticError);
        staking.withdraw(1 ether);
    }

    function test_ClaimTransfersAccruedRewardsAndResetsStoredBalance() public {
        resetPrank(users.alice);

        uint128 depositAmount = 100 ether;
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
        (, uint128 storedRewardBalanceAfterClaim,) = staking.userInfos(users.alice);
        assertEq(storedRewardBalanceAfterClaim, 0, "Pending reward must be zero after claim");

        // Global state remains
        assertEq(staking.totalTokensStaked(), 100 ether, "Global total should remain the same");
    }

    function test_RewardsCheckpointUpdatesCorrectlyAfterClaimAndReDeposit() public {
        resetPrank(users.alice);
        uint128 amount = 100 ether;
        tokenT.approve(address(staking), amount);
        staking.deposit(amount);

        vm.warp(block.timestamp + 10);
        staking.claim();

        (,, uint256 rewardCheckpointAfterClaim) = staking.userInfos(users.alice);

        vm.warp(block.timestamp + 5);

        tokenT.approve(address(staking), amount);
        staking.deposit(amount);

        (,, uint256 rewardCheckpointAfterReDeposit) = staking.userInfos(users.alice);
        assertGt(
            rewardCheckpointAfterReDeposit, rewardCheckpointAfterClaim, "Checkpoint should be updated after re-deposit"
        );
    }

    function test_RevertWhen_ClaimIsCalledWithoutAnyPendingRewards() public {
        // Alice has deposited but no rewards have been accrued
        resetPrank(users.alice);

        uint128 depositAmount = 100 ether;
        tokenT.approve(address(staking), depositAmount);
        staking.deposit(depositAmount);

        (, uint128 storedRewardBalance,) = staking.userInfos(users.alice);
        assertEq(storedRewardBalance, 0, "Alice should have no pending rewards");

        vm.expectRevert(abi.encodeWithSelector(Errors.NoPendingRewardsToClaim.selector));
        staking.claim();
    }

    function test_RewardAccumulatorIncreasesMonotonicallyWithTime() public {
        tokenT.approve(address(staking), 100 ether);
        staking.deposit(100 ether);

        uint256 acc1 = staking.getCumulativeRewardPerToken();
        vm.warp(block.timestamp + 5);
        uint256 acc2 = staking.getCumulativeRewardPerToken();

        assertGe(acc2, acc1, "Accumulator must not decrease over time");
    }

    function test_RewardAccumulatorStopsIncreasingAfterRewardsEndTime() public {
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
        (, uint128 storedRewardBalanceAfterClaim,) = staking.userInfos(users.sender);
        assertEq(storedRewardBalanceAfterClaim, 0, "Claim should clear pending rewards");
    }

    function test_SingleWeiStakeAccruesNonZeroRewards() public {
        tokenT.approve(address(staking), 1);
        staking.deposit(1); // 1 wei

        vm.warp(block.timestamp + 10);
        uint256 reward = staking.getTotalEarnedReward(users.sender);
        uint256 expectedReward = 317_097_919_837_645_860;
        assertEq(reward, expectedReward, "Should earn non-zero reward even for small stake");
    }

    function test_RewardSplitBetweenMultipleUsersWithStaggeredDeposits() public {
        // === Time 0 ===
        resetPrank(users.alice);
        uint128 aliceStake = 100 ether;
        tokenT.approve(address(staking), aliceStake);
        staking.deposit(aliceStake);

        // Warp to t = 10s
        vm.warp(block.timestamp + 10);

        // === Time 10s ===
        resetPrank(users.bob);
        uint128 bobStake = 300 ether;
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

    function test_AccurateRewardDistributionAfterGapsInStakingActivity() public {
        // === Time 0: Alice deposits ===
        resetPrank(users.alice);
        uint128 aliceStake = 100 ether;
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
        uint128 bobStake = 200 ether;
        tokenT.approve(address(staking), bobStake);
        staking.deposit(bobStake);

        // Warp to t = 70 (30s passed)
        vm.warp(block.timestamp + 30);

        // === Time 70: Eve deposits (now Bob + Eve are both staked) ===
        resetPrank(users.eve);
        uint128 eveStake = 300 ether;
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

    function testFuzz_ClaimedRewardIsProportionalToStakedTime(uint96 rawAmount, uint40 warpTime) public {
        // === Bounds ===
        // Max ONE_MILLION_TOKENS = 1 million tokens (assuming 18 decimals)
        uint128 amount = uint128(bound(uint256(rawAmount), WAD, ONE_MILLION_TOKENS)); // at least 1 token
        uint256 time = uint256(bound(uint256(warpTime), ONE_SECOND, 30 days)); // at least 1s

        // mint tokens to alice
        tokenT.mint(users.alice, amount);

        resetPrank(users.alice);
        tokenT.approve(address(staking), amount);
        staking.deposit(amount);

        // Warp forward in time
        vm.warp(block.timestamp + time);

        // Get expected reward
        uint256 rewardRate = staking.REWARD_RATE_PER_SECOND();
        uint256 expectedReward = rewardRate * time;

        // Check pending reward is approximately what we expect
        uint256 pending = staking.getTotalEarnedReward(users.alice);
        assertApproxEqAbs(pending, expectedReward, 1, "Pending reward mismatch");

        // Claim and check token balance
        staking.claim();
        uint256 actual = tokenR.balanceOf(users.alice);
        assertApproxEqAbs(actual, expectedReward, 1, "Claimed reward mismatch");

        // Ensure reward balance cleared
        (, uint128 storedRewardBalanceAfterClaim,) = staking.userInfos(users.alice);
        assertEq(storedRewardBalanceAfterClaim, 0, "Stored reward not cleared");
    }

    function testFuzz_FairRewardSplitBetweenUsersStakingAtDifferentTimes(
        uint96 aliceAmount,
        uint96 bobAmount,
        uint40 gapTime,
        uint40 finalTime
    )
        public
    {
        aliceAmount = uint96(bound(aliceAmount, WAD, ONE_MILLION_TOKENS)); // 1 to 1M tokens
        bobAmount = uint96(bound(bobAmount, WAD, ONE_MILLION_TOKENS)); // 1 to 1M tokens
        gapTime = uint40(bound(gapTime, ONE_SECOND, 1 days));
        finalTime = uint40(bound(finalTime, gapTime + ONE_SECOND, 2 days)); // ensure it's after bob stake

        // === Mint tokens ===
        tokenT.mint(users.alice, aliceAmount);
        tokenT.mint(users.bob, bobAmount);

        // === Alice stakes at t=0 ===
        resetPrank(users.alice);
        tokenT.approve(address(staking), aliceAmount);
        staking.deposit(aliceAmount);

        // === Warp to gapTime, then Bob stakes ===
        vm.warp(block.timestamp + gapTime);
        resetPrank(users.bob);
        tokenT.approve(address(staking), bobAmount);
        staking.deposit(bobAmount);

        // === Warp to finalTime ===
        vm.warp(block.timestamp + (finalTime - gapTime));

        uint256 rewardRate = staking.REWARD_RATE_PER_SECOND();

        // === Expected rewards ===
        uint256 totalReward = rewardRate * finalTime;

        // Alice's share:
        // - From 0 to gapTime: full reward (she's the only staker)
        // - From gapTime to finalTime: weighted by share
        uint256 rewardPart1 = rewardRate * gapTime;

        uint256 sharedReward = rewardRate * (finalTime - gapTime);
        uint256 totalStaked = uint256(aliceAmount) + uint256(bobAmount);
        uint256 rewardPart2Alice = FullMath.mulDiv(sharedReward, aliceAmount, totalStaked);
        uint256 expectedAlice = rewardPart1 + rewardPart2Alice;

        uint256 expectedBob = FullMath.mulDiv(sharedReward, bobAmount, totalStaked);

        // === Alice Claims ===
        resetPrank(users.alice);
        uint256 actualAlice = staking.getTotalEarnedReward(users.alice);
        staking.claim();
        assertApproxEqAbs(actualAlice, expectedAlice, 1, "Alice reward mismatch");
        assertEq(tokenR.balanceOf(users.alice), actualAlice);

        // === Bob Claims ===
        resetPrank(users.bob);
        uint256 actualBob = staking.getTotalEarnedReward(users.bob);
        staking.claim();
        assertApproxEqAbs(actualBob, expectedBob, 1, "Bob reward mismatch");
        assertEq(tokenR.balanceOf(users.bob), actualBob);

        // === Sanity Check ===
        uint256 totalClaimed = actualAlice + actualBob;
        assertApproxEqAbs(totalClaimed, totalReward, 2, "Total rewards must equal emitted rewards");
    }

    function testFuzz_ClaimAfterWithdrawAccruesCorrectReward(uint96 amount, uint40 withdrawTime) public {
        amount = uint96(bound(amount, WAD, ONE_MILLION_TOKENS)); // 1 tokenT to 1M tokenT
        withdrawTime = uint40(bound(withdrawTime, ONE_SECOND, 2 days)); // 1s to 2 days

        // === Mint tokens to sender ===
        tokenT.mint(users.sender, amount);

        // === Time 0: Deposit ===
        tokenT.approve(address(staking), amount);
        staking.deposit(amount);

        // Warp to `withdrawTime`
        vm.warp(block.timestamp + withdrawTime);

        // Withdraw full amount
        staking.withdraw(amount);

        // Check internal state
        (uint128 stakedBalanceAfterWithdraw,,) = staking.userInfos(users.sender);
        assertEq(stakedBalanceAfterWithdraw, 0, "Stake should be 0 after full withdraw");

        // Rewards should be stored internally
        uint256 rewardRate = staking.REWARD_RATE_PER_SECOND();
        uint256 expectedReward = rewardRate * withdrawTime;

        // === Now Claim ===
        staking.claim();
        uint256 received = tokenR.balanceOf(users.sender);

        // Should be the same as if she had claimed without withdrawing
        assertApproxEqAbs(received, expectedReward, 1, "Withdraw before claim shouldn't affect rewards");

        // Final check: pending must be 0
        (, uint128 storedRewardBalanceAfterClaim,) = staking.userInfos(users.sender);
        assertEq(storedRewardBalanceAfterClaim, 0, "Reward must be cleared after claim");
    }
}
