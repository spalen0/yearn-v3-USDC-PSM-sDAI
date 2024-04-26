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
        uint256 toAirdrop = 10e6;
        airdrop(asset, address(strategy), toAirdrop);
        console.log("airdrop done");

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        checkStrategyInvariants(strategy);

        // Check return Values
        assertGe(profit, toAirdrop, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        vm.prank(management);
        strategy.setMaxAcceptableFeeOutPSM(0);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user, 50);

        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");
    }

        function test_operation_NoFees(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        setFees(0, 0);
        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
          
        // Earn Interest
        skip(1 days);
        uint256 toAirdrop = 10e6;
        airdrop(asset, address(strategy), toAirdrop);
        console.log("airdrop done");

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        checkStrategyInvariants(strategy);

        // Check return Values
        assertGe(profit, toAirdrop, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user, 0);

         

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
        assertGt(profit, _profit, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        console.log("BEFORE USER REDEEM", strategy.totalAssets());
        vm.prank(user);
        strategy.redeem(_amount, user, user, 0);
        console.log("AFTER USER REDEEM", strategy.totalAssets());

        assertGe(asset.balanceOf(user), balanceBefore + _amount + _profit, "!final balance");

        uint256 strategistShares = strategy.balanceOf(performanceFeeRecipient);
        if (strategistShares > 0) {
            // empty complete strategy
            vm.prank(performanceFeeRecipient);
            strategy.redeem(strategistShares, performanceFeeRecipient, performanceFeeRecipient, 0);
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
        strategy.redeem(_amount, user, user, 0);

        // TODO: Adjust if there are fees
        assertGe(asset.balanceOf(user), (balanceBefore + _amount + toAirdrop) * (MAX_BPS - 10_00 ) / MAX_BPS, "!final balance");

        vm.prank(performanceFeeRecipient);
        strategy.redeem(expectedShares, performanceFeeRecipient, performanceFeeRecipient, 0);

         

        assertGe(asset.balanceOf(performanceFeeRecipient), expectedShares, "!perf fee out");
    }

    function test_profitableReport_NoFees_MultipleUsers_FixedProfit(
        uint256 _amount,
        uint16 _divider
    ) public {
        uint256 maxDivider = 100;
        vm.assume(_amount > minFuzzAmount * maxDivider && _amount < maxFuzzAmount / 2);
        _divider = uint16(bound(uint256(_divider), 1, maxDivider));

        setFees(0, 0);
        
        address secondUser = address(22);
        address thirdUser = address(33);
        uint256 secondUserAmount = _amount / _divider;
        uint256 thirdUserAmount = _amount / (_divider * 10);
        uint256 profit;
        uint256 loss;
        uint256 redeemAmount;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        mintAndDepositIntoStrategy(strategy, secondUser, secondUserAmount);
        mintAndDepositIntoStrategy(strategy, thirdUser, thirdUserAmount);

        // Report
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariants(strategy);
        // Check return Values
        assertGe(profit, 0, "!profit");
        assertLe(loss, 2, "!loss");
         
        //profit simulation:
        skip(31536000);

        // Report profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariants(strategy);
        assertGe(profit, (_amount + secondUserAmount + thirdUserAmount) * 10 / 100 , "!profit");
        console.log("total investment: ", _amount + secondUserAmount + thirdUserAmount);
        console.log("profit after second report", profit);
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // Withdraw part of funds user
        redeemAmount = strategy.balanceOf(user) / 8;
        vm.prank(user);
        strategy.redeem(redeemAmount, user, user, 0);
        checkStrategyInvariantsAfterRedeem(strategy);

        // Withdraw part of funds secondUser
        redeemAmount = strategy.balanceOf(secondUser) / 6;
        vm.prank(secondUser);
        strategy.redeem(redeemAmount, secondUser, secondUser, 0);
        checkStrategyInvariantsAfterRedeem(strategy);

        // Withdraw part of funds thirdUser
        redeemAmount = strategy.balanceOf(thirdUser) / 4;
        vm.prank(thirdUser);
        strategy.redeem(redeemAmount, thirdUser, thirdUser, 0);
        checkStrategyInvariantsAfterRedeem(strategy);

        // Report profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariants(strategy);
        skip(strategy.profitMaxUnlockTime());
        console.log("total investment: ", _amount + secondUserAmount + thirdUserAmount);
        console.log("profit after third report", profit);
        console.log("loss after third report", loss);

        depositIntoStrategy(strategy, secondUser, asset.balanceOf(secondUser), asset);
        // withdraw all funds
        console.log("user shares: ", strategy.balanceOf(user));
        console.log("user2 shares: ", strategy.balanceOf(secondUser));
        console.log("user3 shares: ", strategy.balanceOf(thirdUser));
        redeemAmount = strategy.balanceOf(user);
        if (redeemAmount > 0){
            vm.prank(user);
            strategy.redeem(redeemAmount, user, user, 0);
            checkStrategyInvariantsAfterRedeem(strategy);
        }
        redeemAmount = strategy.balanceOf(secondUser);
        if (redeemAmount > 0){
            vm.prank(secondUser);
            strategy.redeem(redeemAmount, secondUser, secondUser, 0);
            checkStrategyInvariantsAfterRedeem(strategy);
        }
        redeemAmount = strategy.balanceOf(thirdUser);
        if (redeemAmount > 0){
            vm.prank(thirdUser);
            strategy.redeem(redeemAmount, thirdUser, thirdUser, 0);
            checkStrategyInvariantsAfterRedeem(strategy);
        }
        // verify users earned profit
        assertGe(asset.balanceOf(user) * 110 / 100, _amount, "!final balance user");
        assertGe(asset.balanceOf(secondUser) * 110 / 100, secondUserAmount, "!final balance secondUser");
        assertGe(asset.balanceOf(thirdUser) * 110 / 100, thirdUserAmount, "!final balance thirdUser");

        checkStrategyTotals(strategy, 0, 0, 0);
    }

    function test_profitableReport_NoFees_MultipleUsers_PSMfee(
        uint256 _amount,
        uint16 _divider
    ) public {
        uint256 maxDivider = 100;
        vm.assume(_amount > minFuzzAmount * maxDivider && _amount < maxFuzzAmount/10);
        _divider = uint16(bound(uint256(_divider), 1, maxDivider));

        setFees(0, 0);
        
        address secondUser = address(22);
        address thirdUser = address(33);
        uint256 secondUserAmount = _amount / _divider;
        uint256 thirdUserAmount = _amount / (_divider * 10);
        uint256 profit;
        uint256 loss;
        uint256 redeemAmount;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        mintAndDepositIntoStrategy(strategy, secondUser, secondUserAmount);
        mintAndDepositIntoStrategy(strategy, thirdUser, thirdUserAmount);

        skip(1000);

        // Report
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariants(strategy);
        // Check return Values
        assertGe(profit, 0, "!profit");
        assertLe(loss, 2, "!loss");
         
        //profit simulation:
        skip(31536000);

        // Report profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariants(strategy);
        assertGe(profit, (_amount + secondUserAmount + thirdUserAmount) * 10 / 100 , "!profit");
        console.log("total investment: ", _amount + secondUserAmount + thirdUserAmount);
        console.log("profit after second report", profit);
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // Withdraw part of funds user
        redeemAmount = strategy.balanceOf(user) / 8;
        vm.prank(user);
        strategy.redeem(redeemAmount, user, user, 0);
        checkStrategyInvariantsAfterRedeem(strategy);

        // Withdraw part of funds secondUser
        redeemAmount = strategy.balanceOf(secondUser) / 6;
        vm.prank(secondUser);
        strategy.redeem(redeemAmount, secondUser, secondUser, 0);
        checkStrategyInvariantsAfterRedeem(strategy);

        // Withdraw part of funds thirdUser
        redeemAmount = strategy.balanceOf(thirdUser) / 4;
        vm.prank(thirdUser);
        strategy.redeem(redeemAmount, thirdUser, thirdUser, 0);
        checkStrategyInvariantsAfterRedeem(strategy);

        // Report profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariants(strategy);
        skip(strategy.profitMaxUnlockTime());
        console.log("total investment: ", _amount + secondUserAmount + thirdUserAmount);
        console.log("profit after third report", profit);
        console.log("loss after third report", loss);

        depositIntoStrategy(strategy, secondUser, asset.balanceOf(secondUser), asset);

        //PSM fee increase:
        address maker = 0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB;
        address PSM = 0x89B78CfA322F6C5dE0aBcEecab66Aee45393cC5A;
        vm.prank(maker);
        IPSMfee(PSM).file("tout", 100000000000000000); //add extreme feeOut of 10%

        // withdraw all funds
        console.log("user shares: ", strategy.balanceOf(user));
        console.log("user2 shares: ", strategy.balanceOf(secondUser));
        console.log("user3 shares: ", strategy.balanceOf(thirdUser));
        redeemAmount = strategy.balanceOf(user);
        if (redeemAmount > 0){
            vm.prank(user);
            strategy.redeem(redeemAmount, user, user, 5);
            checkStrategyInvariantsAfterRedeem(strategy);
        }
        redeemAmount = strategy.balanceOf(secondUser);
        if (redeemAmount > 0){
            vm.prank(secondUser);
            strategy.redeem(redeemAmount, secondUser, secondUser, 5);
            checkStrategyInvariantsAfterRedeem(strategy);
        }
        redeemAmount = strategy.balanceOf(thirdUser);
        if (redeemAmount > 0){
            vm.prank(thirdUser);
            strategy.redeem(redeemAmount, thirdUser, thirdUser, 5);
            checkStrategyInvariantsAfterRedeem(strategy);
        }
        // verify users earned profit
        assertGe(asset.balanceOf(user) * 110 / 100, _amount, "!final balance user");
        assertGe(asset.balanceOf(secondUser) * 110 / 100, secondUserAmount, "!final balance secondUser");
        assertGe(asset.balanceOf(thirdUser) * 110 / 100, thirdUserAmount, "!final balance thirdUser");

        checkStrategyTotals(strategy, 0, 0, 0);
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
        strategy.redeem(_amount, user, user, 0);
        // verify users earned profit
        assertGt(asset.balanceOf(user), _amount, "!final balance");

         
    }
}

interface IPSMfee {
    function file(bytes32 what, uint256 data) external;
}
