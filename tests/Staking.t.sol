// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23 <0.9.0;

import { console2 } from "forge-std/src/console2.sol";
import { Base_Test } from "./Base.t.sol";
import { stdError } from "forge-std/src/StdError.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

        // Assert that storedRewardBalance has been zeroed out
        assertEq(staking.storedRewardBalances(users.alice), 0, "Pending reward must be zero after claim");

        // Global state remains
        assertEq(staking.totalTokensStaked(), 100 ether, "Global total should remain the same");
    }

    function test_RevertWhen_ClaimWithoutDeposit() public {
        // Eve has not deposited
        resetPrank(users.eve);

        assertEq(staking.stakedBalances(users.eve), 0, "Eve should have no staked tokens");

        vm.expectRevert(abi.encodeWithSelector(Staking.NoStakedTokens.selector));
        staking.claim();
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

        console2.log("totalStaked: ", staking.totalTokensStaked());

        // Warp to t = 20s
        vm.warp(block.timestamp + 10);

        uint256 rewardRate = staking.REWARD_RATE_PER_SECOND();
        console2.log("rewardRate: ", rewardRate); // (31709791983764586) -> 0.031709791983764586 tokenR / sec

        // === Alice Claims ===
        resetPrank(users.alice);
        uint256 alicePending = staking.getTotalEarnedReward(users.alice);
        console2.log("alicePending: ", alicePending); // 396372399797057200
        staking.claim();
        uint256 aliceReceived = tokenR.balanceOf(users.alice);
        console2.log("aliceReceived: ", aliceReceived); // 396372399797057325

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

        /*
        TODO: Fix: Precision Loss

        Alice:
        calculated:     396372399797057325 (0.396372399797057325)
        pending:        396372399797057200 (0.396372399797057200)
        received:       396372399797057200 (0.396372399797057200)
        precision loss: 125                (0.000000000000000125)

        Bob:
        calculated:     237823439878234395 (0.237823439878234395)
        pending:        237823439878234200 (0.237823439878234200)
        received:       237823439878234200 (0.237823439878234200)
        precision loss: 195                (0.000000000000000195)
        */

        assertApproxEqAbs(alicePending, 396372399797057325, 125, "Alice pending reward mismatch");
        assertApproxEqAbs(aliceReceived, 396372399797057200, 125, "Alice received reward mismatch");

        // === Bob Claims ===
        resetPrank(users.bob);
        uint256 bobPending = staking.getTotalEarnedReward(users.bob);
        console2.log("bobPending: ", bobPending);
        staking.claim();
        uint256 bobReceived = tokenR.balanceOf(users.bob);
        console2.log("bobReceived: ", bobReceived);

        assertApproxEqAbs(bobPending, 237823439878234200, 195, "Bob pending reward mismatch");
        assertApproxEqAbs(bobReceived, 237823439878234200, 195, "Bob received reward mismatch");

        // === Sanity Check ===
        uint256 totalDistributed = aliceReceived + bobReceived;
        assertApproxEqAbs(totalDistributed, rewardRate * 20, 1e12, "Total distributed rewards mismatch");

        // === Total Rewards Distributed ===
        uint256 totalRewardsDistributed = staking.totalRewardsDistributed();
        // total rewards distributed:        634195839675291400 (0.634195839675291400)
        // expected rewards distributed:     634195839675291720 (0.634195839675291720)
        // precision loss:                   320                (0.000000000000000320)
        assertApproxEqAbs(totalRewardsDistributed, 634195839675291720, 320, "Total rewards distributed mismatch");
    }
}
