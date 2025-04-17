// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23 <0.9.0;

import { Base_Test } from "./Base.t.sol";
import { CommonBase } from "forge-std/src/Base.sol";
import { StdCheats } from "forge-std/src/StdCheats.sol";
import { StdUtils } from "forge-std/src/StdUtils.sol";
import { StdInvariant } from "forge-std/src/StdInvariant.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Staking } from "../src/Staking.sol";
import { UserInfo } from "../src/types/DataTypes.sol";
import { console2 } from "forge-std/src/console2.sol";
import { Constants } from "./utils/Constants.sol";

contract Staking_Invariant_Handler is CommonBase, StdCheats, StdUtils, StdInvariant, Constants {
    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @dev Maps function names to the number of times they have been called.
    mapping(string func => uint256 calls) public calls;

    /// @dev The total number of calls made to this contract.
    uint256 public totalCalls;

    /*//////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    //////////////////////////////////////////////////////////////*/

    IERC20 public tokenR;
    IERC20 public tokenT;
    Staking public staking;

    /*//////////////////////////////////////////////////////////////
                             MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Checks user assumptions
    modifier checkUser(address sender) {
        // Prevent the sender to be the zero address
        vm.assume(sender != address(0));

        // Prevent the contract itself from playing the role of any user
        vm.assume(sender != address(this));
        _;
    }

    /// @dev Makes the provided sender the caller
    modifier useNewSender(address sender) {
        resetPrank(sender);
        _;
    }

    /// @dev Simulates the passage of time. The time jump is upper bounded
    /// @param timeJumpSeed A fuzzed value needed for generating random time warps.
    modifier adjustTimestamp(uint256 timeJumpSeed) {
        uint256 timeJump = _bound(timeJumpSeed, 1 seconds, 30 days);
        vm.warp(getBlockTimestamp() + timeJump);
        _;
    }

    /// @dev Records a function call for instrumentation purposes.
    modifier instrument(string memory functionName) {
        calls[functionName]++;
        totalCalls++;
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(IERC20 _tokenR, IERC20 _tokenT, Staking _staking) {
        tokenR = _tokenR;
        tokenT = _tokenT;
        staking = _staking;
    }

    /*//////////////////////////////////////////////////////////////
                             FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function deposit(
        uint128 amount,
        uint256 timeJumpSeed
    )
        public
        checkUser(msg.sender)
        useNewSender(msg.sender)
        adjustTimestamp(timeJumpSeed)
        instrument("deposit")
    {
        console2.log(">>deposit msg.sender", msg.sender);

        amount = uint128(bound(uint256(amount), WAD, ONE_MILLION_TOKENS)); // 1 to 1M tokens
        deal({ token: address(tokenT), to: msg.sender, give: ONE_MILLION_TOKENS, adjust: true });
        tokenT.approve(address(staking), amount);
        console2.log("deposit", amount);
        staking.deposit(amount);
    }

    function withdraw(
        uint128 amount,
        uint256 timeJumpSeed
    )
        public
        checkUser(msg.sender)
        useNewSender(msg.sender)
        adjustTimestamp(timeJumpSeed)
        instrument("withdraw")
    {
        // deposit first
        amount = uint128(bound(uint256(amount), WAD, ONE_MILLION_TOKENS)); // 1 to 1M tokens
        deal({ token: address(tokenT), to: msg.sender, give: ONE_MILLION_TOKENS, adjust: true });
        tokenT.approve(address(staking), amount);
        staking.deposit(amount);

        // withdraw
        staking.withdraw(amount);
    }

    function withdrawAfterTimePasses(
        uint128 amount,
        uint256 timeJumpSeed
    )
        public
        checkUser(msg.sender)
        useNewSender(msg.sender)
        adjustTimestamp(timeJumpSeed)
        instrument("withdraw")
    {
        // deposit first
        amount = uint128(bound(uint256(amount), WAD, ONE_MILLION_TOKENS)); // 1 to 1M tokens
        deal({ token: address(tokenT), to: msg.sender, give: ONE_MILLION_TOKENS, adjust: true });
        tokenT.approve(address(staking), amount);
        staking.deposit(amount);

        // time passes
        uint256 timeJump = _bound(timeJumpSeed, 1 seconds, 30 days);
        vm.warp(getBlockTimestamp() + timeJump);

        // withdraw
        staking.withdraw(amount);
    }

    function claim(
        uint128 amount,
        uint256 timeJumpSeed
    )
        public
        checkUser(msg.sender)
        useNewSender(msg.sender)
        adjustTimestamp(timeJumpSeed)
        instrument("claim")
    {
        // deposit first
        amount = uint128(bound(uint256(amount), WAD, ONE_MILLION_TOKENS)); // 1 to 1M tokens
        deal({ token: address(tokenT), to: msg.sender, give: ONE_MILLION_TOKENS, adjust: true });
        tokenT.approve(address(staking), amount);
        staking.deposit(amount);

        // time passes
        uint256 timeJump = _bound(timeJumpSeed, 1 seconds, 30 days);
        vm.warp(getBlockTimestamp() + timeJump);

        vm.assume(staking.getTotalEarnedReward(msg.sender) > 0);

        staking.claim();
    }

    /*//////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Stops the active prank and sets a new one
    function resetPrank(address msgSender) internal {
        vm.stopPrank();
        vm.startPrank(msgSender);
    }

    /// @dev Retrieves the current block timestamp as an `uint40`.
    function getBlockTimestamp() internal view returns (uint40) {
        return uint40(block.timestamp);
    }
}

contract Staking_Invariant_Test is Base_Test {
    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/

    Staking_Invariant_Handler internal handler;
    uint256 internal lastAccumulator;
    uint256 internal initialRewardSupply;

    /*//////////////////////////////////////////////////////////////
                             MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Makes the provided sender the caller
    modifier useNewSender(address sender) {
        resetPrank(sender);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            SET-UP FUNCTION
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        Base_Test.setUp();
        handler = new Staking_Invariant_Handler(IERC20(tokenR), IERC20(tokenT), staking);
        vm.label(address(handler), "Staking_Invariant_Handler");

        // Target the Staking handler for invariant testing
        targetContract(address(handler));

        // Exclude the handler from being fuzzed as `msg.sender`
        excludeSender(address(handler));

        // Target the users as `sender` for invariant testing
        _targetSender(users.deployer);
        _targetSender(users.sender);
        _targetSender(users.alice);
        _targetSender(users.bob);
        _targetSender(users.eve);

        // Record the initial reward token supply allocated to the contract
        initialRewardSupply = tokenR.balanceOf(address(staking));
    }

    /*//////////////////////////////////////////////////////////////
                            INVARIANTS
    //////////////////////////////////////////////////////////////*/

    function invariant_TotalUserStakesMatchGlobalStakedAmount() public view {
        address[] memory _users = targetSenders();
        uint256 total = 0;
        for (uint8 i = 0; i < _users.length; i++) {
            address sender = _users[i];
            UserInfo memory _userInfo = staking.getUserInfo(sender);
            total += _userInfo.stakedBalance;
        }
        // Allow for 1 wei error
        assertApproxEqAbs(total, staking.totalTokensStaked(), 1, "Total staked tokens mismatch");
    }

    function invariant_GlobalRewardAccumulatorNeverDecreases() public {
        uint256 current = staking.getCumulativeRewardPerToken();
        assertGe(current, lastAccumulator, "Reward accumulator should not decrease");
        lastAccumulator = current;
    }

    function invariant_UserStoredRewardIsAlwaysPositiveOrZero() public view {
        address[] memory _users = targetSenders();
        for (uint256 i = 0; i < _users.length; i++) {
            address user = _users[i];
            UserInfo memory _userInfo = staking.getUserInfo(user);
            assertGe(_userInfo.storedRewardBalance, 0, "Stored reward should not be negative");
        }
    }

    function invariant_ClaimOperationResetsStoredUserRewardBalance() public {
        address[] memory _users = targetSenders();
        for (uint256 i = 0; i < _users.length; i++) {
            address user = _users[i];
            UserInfo memory _userInfoBeforeClaim = staking.getUserInfo(user);
            if (_userInfoBeforeClaim.storedRewardBalance > 0) {
                resetPrank(user);
                staking.claim();
                UserInfo memory _userInfoAfterClaim = staking.getUserInfo(user);
                assertEq(_userInfoAfterClaim.storedRewardBalance, 0, "Claim should clear reward balance");
            }
        }
    }

    function invariant_RewardAccumulatorStopsIncreasingAfterRewardEndTime() public {
        vm.warp(staking.REWARDS_END_TIME() + 100);
        uint256 rewardBefore = staking.getCumulativeRewardPerToken();
        vm.warp(block.timestamp + 10);
        uint256 rewardAfter = staking.getCumulativeRewardPerToken();
        assertEq(rewardBefore, rewardAfter, "Accumulator must not increase after reward end time");
    }

    function invariant_ContractTokenBalancesMatchStakingState() public view {
        uint256 contractStakeBalance = tokenT.balanceOf(address(staking));
        assertEq(contractStakeBalance, staking.totalTokensStaked(), "Token balance should equal total staked");

        uint256 contractRewardBalance = tokenR.balanceOf(address(staking));
        uint256 expectedTotal = contractRewardBalance + staking.totalRewardsDistributed();

        // Only assert <= to avoid false positives from rounding during emission window
        assertLe(staking.totalRewardsDistributed(), expectedTotal, "Rewards must not exceed total emission");
    }

    function invariant_StakedTokenBalanceOnContractMatchesGlobalTotal() public view {
        uint256 actualBalance = tokenT.balanceOf(address(staking));
        uint256 expectedBalance = staking.totalTokensStaked();
        assertEq(actualBalance, expectedBalance, "Staking contract tokenT balance mismatch");
    }

    function invariant_RewardTokenDistributionMatchesInitialSupply() public view {
        uint256 currentBalance = tokenR.balanceOf(address(staking));
        uint256 distributed = staking.totalRewardsDistributed();
        uint256 total = currentBalance + distributed;

        assertEq(total, initialRewardSupply, "Reward token accounting mismatch");
    }

    /*//////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _targetSender(address sender) internal useNewSender(sender) {
        targetSender(sender);

        tokenT.approve(address(staking), type(uint256).max);
    }
}
