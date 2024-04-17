// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract OperationTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function testSetupStrategyOK() public {
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
        // TODO: add additional check on strat params
    }

    function test_operation_NoFees_ForceSwap(uint256 _amount) public {
        maxFuzzAmount = 1e6 * 1e6;
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        setFees(0, 0);
        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
          
        // Earn Interest
        skip(1 days);
        airdrop(asset, address(strategy), 10e6);
        console.log("airdrop done");

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        checkStrategyInvariants(strategy);

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        vm.prank(management);
        strategy.setMaxAcceptableFeeOutPSM(0);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");
    }

        function test_operation_NoFees(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        setFees(0, 0);
        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
          

        // Earn Interest
        skip(1 days);
        airdrop(asset, address(strategy), 10e6);
        console.log("airdrop done");

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        checkStrategyInvariants(strategy);

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

         

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_profitableReport_expectedFees(
        uint256 _amount,
        uint256 _profit
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        //_profitFactor = uint16(bound(uint256(_profitFactor), 10, 1_00));
        //_profit = uint16(bound(uint256(_profit), 1e10, 10000e18));
        _profit = bound(_profit, 1e4, 1000e6);
        setFees(0, 0);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
          

        // Earn Interest
        skip(1 days);

        //toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), _profit);
        
        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        checkStrategyInvariants(strategy);

        // Check return Values
        //assertGe(profit, toAirdrop, "!profit");
        if (forceProfit == false) {
            assertGt(profit, 0, "!profit");
        }
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        console.log("BEFORE USER REDEEM", strategy.totalAssets());
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        console.log("AFTER USER REDEEM", strategy.totalAssets());

        //uint256 expectedFees = (profit * strategy.performanceFee()) / MAX_BPS;

        assertGe(asset.balanceOf(user), balanceBefore + _amount + _profit, "!final balance");

        uint256 strategistShares = strategy.balanceOf(performanceFeeRecipient);
        if (strategistShares > 0) {
            // empty complete strategy
            vm.prank(performanceFeeRecipient);
            strategy.redeem(strategistShares, performanceFeeRecipient, performanceFeeRecipient);
            assertGt(asset.balanceOf(performanceFeeRecipient), 0, "fees too low!");
        }
        
    }

    function test_profitableReport_expectedShares(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));
        
        // Set protofol fee to 0 and perf fee to 10%
        setFees(0, 1_000);
        
        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        
        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
          
        
        // Earn Interest
        skip(1 days);

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;

        airdrop(asset, address(strategy), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        
        checkStrategyInvariants(strategy);

        // Check return Values
        assertGe(profit, toAirdrop, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // Get the expected fee
        uint256 expectedShares = (profit * 1_000) / MAX_BPS;

        assertEq(strategy.balanceOf(performanceFeeRecipient), expectedShares, "shares not same");

        uint256 balanceBefore = asset.balanceOf(user);
        
        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // TODO: Adjust if there are fees
        assertGe(asset.balanceOf(user), (balanceBefore + _amount + toAirdrop) * (MAX_BPS - 10_00 ) / MAX_BPS, "!final balance");

        vm.prank(performanceFeeRecipient);
        strategy.redeem(expectedShares, performanceFeeRecipient, performanceFeeRecipient);

         

        assertGe(asset.balanceOf(performanceFeeRecipient), expectedShares, "!perf fee out");
    }

    function test_emergencyWithdrawAll(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        setFees(0, 0);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Skip some time
        airdrop(asset, address(strategy), 100e6);

        vm.prank(keeper);
        (uint profit, uint loss) = strategy.report();
        checkStrategyInvariants(strategy);
        assertGt(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        vm.prank(management);
        strategy.shutdownStrategy();
        vm.prank(management); 
        strategy.emergencyWithdraw(type(uint256).max);
        assertGe(asset.balanceOf(address(strategy)) + 1, _amount + 100e6, "!all in asset");

        vm.prank(keeper);
        (profit, loss) = strategy.report();
        assertEq(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        // Unlock Profits
        skip(strategy.profitMaxUnlockTime());

        vm.prank(user);
        strategy.redeem(_amount, user, user);
        // verify users earned profit
        assertGt(asset.balanceOf(user), _amount, "!final balance");

         
    }
}