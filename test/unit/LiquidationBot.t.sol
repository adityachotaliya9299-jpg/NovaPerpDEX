// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Phase4Base} from "../Phase4Base.sol";
import {LiquidationBot} from "../../src/core/LiquidationBot.sol";

/// @title LiquidationBotTest
/// @notice Tests for batch liquidation and keeper-reward attribution.
contract LiquidationBotTest is Phase4Base {
    function _setupTwoUnderwater() internal {
        _deposit(alice, 100_000e18);
        _deposit(bob, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        _openLong(bob, 10_000e18, 1_000e18);
        _setPrice(1_820e18);
    }

    function test_BatchLiquidatesAllEligible() public {
        _setupTwoUnderwater();
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;

        uint256 count = bot.liquidateBatch(accounts, ETH_USD, LONG);
        assertEq(count, 2);
        assertEq(mm.longOpenInterest(ETH_USD), 0);
    }

    function test_BatchRewardsGoToBeneficiary() public {
        _setupTwoUnderwater();
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;
        bot.liquidateBatch(accounts, ETH_USD, LONG);
        // 20 reward each => 40 to the bot's beneficiary
        assertEq(vault.balanceOf(botBeneficiary), 40e18);
    }

    function test_BatchSkipsHealthyAccounts() public {
        _deposit(alice, 100_000e18);
        _deposit(bob, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18); // healthy
        _openLong(bob, 10_000e18, 1_000e18);
        _setPrice(1_820e18); // both become underwater
        // re-add collateral to alice to make her healthy again
        vm.prank(alice);
        mm.addCollateral(ETH_USD, LONG, 5_000e18);

        address[] memory accounts = new address[](2);
        accounts[0] = alice; // now healthy
        accounts[1] = bob; // underwater

        uint256 count = bot.liquidateBatch(accounts, ETH_USD, LONG);
        assertEq(count, 1);
        assertGt(mm.getPosition(alice, ETH_USD, LONG).size, 0); // alice survived
        assertEq(mm.getPosition(bob, ETH_USD, LONG).size, 0); // bob liquidated
    }

    function test_BatchWithNoEligibleReturnsZero() public {
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18); // healthy
        address[] memory accounts = new address[](1);
        accounts[0] = alice;
        assertEq(bot.liquidateBatch(accounts, ETH_USD, LONG), 0);
    }

    function test_LiquidatableAccountsView() public {
        _setupTwoUnderwater();
        address[] memory accounts = new address[](3);
        accounts[0] = alice;
        accounts[1] = bob;
        accounts[2] = makeAddr("flat"); // no position

        address[] memory eligible = bot.liquidatableAccounts(accounts, ETH_USD, LONG);
        assertEq(eligible.length, 2);
        assertEq(eligible[0], alice);
        assertEq(eligible[1], bob);
    }

    function test_RevertWhen_ConstructedWithZeroRecipient() public {
        vm.expectRevert("BOT: zero recipient");
        new LiquidationBot(address(mm), address(engine), address(0));
    }

    function test_RevertWhen_ConstructedWithZeroEngine() public {
        vm.expectRevert("BOT: zero engine");
        new LiquidationBot(address(mm), address(0), botBeneficiary);
    }

    function test_EmptyArrayReturnsZero() public {
        address[] memory accounts = new address[](0);
        assertEq(bot.liquidateBatch(accounts, ETH_USD, LONG), 0);
    }

    function test_SingleAccountBatch() public {
        _deposit(alice, 100_000e18);
        _openLong(alice, 10_000e18, 1_000e18);
        _setPrice(1_820e18);
        address[] memory accounts = new address[](1);
        accounts[0] = alice;
        assertEq(bot.liquidateBatch(accounts, ETH_USD, LONG), 1);
    }

    function test_BatchEmitsEvent() public {
        _setupTwoUnderwater();
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;
        vm.expectEmit(true, false, false, true);
        emit LiquidationBot.BatchLiquidated(ETH_USD, LONG, 2);
        bot.liquidateBatch(accounts, ETH_USD, LONG);
    }
}