// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23 <0.9.0;

import { Base_Test } from "./Base.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StakingReward_Test is Base_Test {
    function setUp() public override {
        Base_Test.setUp();
    }

    function test_DepositUpdatesBalanceAndGlobalState() public {
        // Set Alice as the active user
        resetPrank(users.alice);

        uint256 depositAmount = 100 ether;

        // Approve staking contract to transfer Alice's tokenT
        IERC20(tokenT).approve(address(stakingReward), depositAmount);

        // Capture timestamp before deposit
        uint256 timestampBefore = block.timestamp;

        // Deposit tokenT into the staking contract
        stakingReward.deposit(depositAmount);

        // Check: Alice’s stake is correctly updated
        uint256 stakedBalance = stakingReward.stakedBalances(users.alice);
        assertEq(stakedBalance, depositAmount, "Alice's staked balance should match deposit amount");

        // Check: totalTokensStaked is updated
        uint256 totalStaked = stakingReward.totalTokensStaked();
        assertEq(totalStaked, depositAmount, "Total staked should equal Alice's deposit");

        // Check: lastRewardUpdateTime equals current block timestamp
        uint256 lastUpdate = stakingReward.lastRewardUpdateTime();
        assertEq(lastUpdate, timestampBefore, "lastRewardUpdateTime should match block.timestamp at deposit");

        // Check: cumulativeRewardPerToken remains zero (no one was staking before)
        uint256 cumulativeReward = stakingReward.getCumulativeRewardPerToken();
        assertEq(cumulativeReward, 0, "cumulativeRewardPerToken should remain 0 on first deposit");
    }
}
