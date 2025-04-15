// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23 <0.9.0;

import { Test } from "forge-std/src/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockTokenR } from "./mocks/MockTokenR.sol";
import { MockTokenT } from "./mocks/MockTokenT.sol";

import { Staking } from "../src/Staking.sol";

import { Users } from "./utils/Types.sol";

/// @notice Common contract members needed across test contracts
abstract contract Base_Test is Test {
    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint40 internal constant APRIL_1_2025 = 1_743_462_000;
    uint256 internal constant TOTAL_REWARD = 1_000_000 ether;
    uint256 internal constant REWARD_DURATION = 365 days;
    uint256 internal constant PRECISION = 1e18;

    Users internal users;

    /*//////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    //////////////////////////////////////////////////////////////*/

    IERC20 internal tokenR;
    IERC20 internal tokenT;
    Staking internal staking;

    /*//////////////////////////////////////////////////////////////
                            SET-UP FUNCTION
    //////////////////////////////////////////////////////////////*/

    /// @dev A setup function invoked before each test case
    function setUp() public virtual {
        // Warp to April 1, 2025 at 00:00 UTC to provide a more realistic testing environment
        vm.warp({ newTimestamp: APRIL_1_2025 });

        // Deploy the mock tokens
        tokenR = new MockTokenR();
        tokenT = new MockTokenT();

        // Label the deployed mock tokens
        vm.label(address(tokenR), "TokenR");
        vm.label(address(tokenT), "TokenT");

        // Create users for testing.
        users = Users({
            deployer: createUser("Deployer"),
            sender: createUser("Sender"),
            alice: createUser("Alice"),
            bob: createUser("Bob"),
            eve: createUser("Eve")
        });

        // Set deployer as the default caller for this setUp
        vm.startPrank({ msgSender: users.deployer });

        // Deploy the staking reward contract
        staking = new Staking({
            _stakedToken: tokenT,
            _rewardToken: tokenR,
            _totalReward: TOTAL_REWARD,
            _rewardDuration: REWARD_DURATION
        });

        // Label the deployed staking reward contract
        vm.label(address(staking), "Staking");

        // Deal total reward tokenR to the Staking contract
        deal({ token: address(tokenR), to: address(staking), give: TOTAL_REWARD, adjust: true });

        // Set sender as the default caller for the tests
        resetPrank({ msgSender: users.sender });
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Generates a user, labels its address, and funds it with test eth and tokenT balance
    function createUser(string memory name) internal returns (address payable) {
        address payable user = payable(makeAddr(name));
        vm.deal({ account: user, newBalance: 1000 ether });
        deal({ token: address(tokenT), to: user, give: 100_000 ether, adjust: true });
        return user;
    }

    /// @dev Stops the active prank and sets a new one
    function resetPrank(address msgSender) internal {
        vm.stopPrank();
        vm.startPrank(msgSender);
    }
}
