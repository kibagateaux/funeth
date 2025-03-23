pragma solidity ^0.8.26;

import {NNETHBaseTest} from "./NNETHBaseTest.t.sol";
import {IERC20x, IAaveMarket, INNETH, AaveErrors} from "../src/Interfaces.sol";
import {NNETH} from "../src/NNETH.sol";

contract NNETHCore is NNETHBaseTest {
    function test_initialize_mustHaveMultiSigDeployed() public view {
        address nnCityTreasury = address(0xC958dEeAB982FDA21fC8922493d0CEDCD26287C3);
        address prognnCityTreasury = address(nnETH.ZU_CITY_TREASURY());
        uint256 manualSize;
        uint256 configedSize;
        assembly {
            manualSize := extcodesize(nnCityTreasury)
            configedSize := extcodesize(prognnCityTreasury)
        }

        assertGt(configedSize, 0);
        assertEq(manualSize, configedSize);
    }

    function invariant_lend_increaseTotalDelegated() public {
        // sample vals. uneven city/lend vals to ensure overwrites work
        address[2] memory cities = [address(0x83425), address(0x9238521)];
        // wei not ether bc usdc only has 8 decimals
        uint256[4] memory amounts = [uint256(11241 wei), uint256(49134 wei), uint256(84923 wei), uint256(84923 wei)];
        

        // deposit some amount so we can delegate credit
        _depositnnEth(address(0x14632332), 1000 ether, true);
        (,,uint256 availableBorrow,,,uint256 hf) = aave.getUserAccountData(address(nnETH));
        assertGt(availableBorrow, 100000000);

        vm.startPrank(nnETH.ZU_CITY_TREASURY());

        assertEq(nnETH.totalCreditDelegated(), 0);
        nnETH.lend(cities[0], amounts[0]);
        assertEq(nnETH.totalCreditDelegated(), amounts[0]);
        nnETH.lend(cities[1], amounts[1]);
        assertEq(nnETH.totalCreditDelegated(), amounts[0] + amounts[1]);
        nnETH.lend(cities[0], amounts[2]);
        assertEq(nnETH.totalCreditDelegated(), amounts[2] + amounts[1]);
        nnETH.lend(cities[1], amounts[3]);
        assertEq(nnETH.totalCreditDelegated(), amounts[2] + amounts[3]);

        vm.stopPrank();
    }

    function test_initialize_cantReinitialize() public {
        vm.expectRevert(NNETH.AlreadyInitialized.selector);
        nnETH.initialize(address(WETH), address(aave), address(debtToken), 1, "nnCity Ethereum", "nnETH");
    }

    function test_initialize_setsProperDepositToken() public view {
        if(address(nnETH.reserveToken()) == address(WETH)) {
            assertEq(address(nnETH.aToken()), address(0xD4a0e0b9149BCee3C920d2E00b5dE09138fd8bb7));
            return;
        } else if(address(nnETH.reserveToken()) == address(USDC)) {
            assertEq(address(nnETH.aToken()), address(0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB));
        } else {
            revert("Invalid reserve token");
        }
    }

    function test_pullReserves_revertNotnnCityTreasury(address caller, uint256 amount) public {
        vm.assume(caller != nnETH.ZU_CITY_TREASURY());
        vm.expectRevert(NNETH.NotnnCity.selector);
        vm.prank(caller);
        nnETH.pullReserves(amount);
    }

    function test_pullReserves_onlynnCityTreasury(address depositor, address rando) public {
        // function should work on 0 values
        vm.prank(nnETH.ZU_CITY_TREASURY());
        nnETH.pullReserves(0);
        
        vm.prank(rando);
        vm.expectRevert(NNETH.NotnnCity.selector);
        nnETH.pullReserves(0);

        _depositnnEth(depositor, 10 ether, true);
        vm.warp(block.timestamp + 10 days);

        vm.prank(nnETH.ZU_CITY_TREASURY());
        nnETH.pullReserves(1);

        vm.prank(rando);
        vm.expectRevert(NNETH.NotnnCity.selector);
        nnETH.pullReserves(1);
    }
    function invariant_getYieldEarned_aTokenVsTotalSupply() public {
        uint256 n = _depositnnEth(address(0x14632332), 100 ether, true);
        vm.warp(block.timestamp + 888888);
        
        // check raw aave values calculations
        uint256 diff = (nnETH.aToken().balanceOf(address(nnETH)) / nnETH.reserveVsATokenDecimalOffset()) - nnETH.totalSupply();

        // check internal decimaled calculations
        uint256 diff2 = nnETH.underlying() - nnETH.totalSupply();
        
        assertGt(diff, 0);
        // - 1 to account for rounding errors btw aave tokens
        assertGe(diff, diff2 - 1);
        assertGe(nnETH.getYieldEarned(), diff - 1);
    }

    function test_pullReserves_sendsATokenToTreasury(address depositor, uint256 amount) public {
        uint256 n = _depositnnEth(depositor, amount, true);
        vm.warp(block.timestamp + 888888);
        
        uint256 yield = nnETH.getYieldEarned();
        assertGt(yield, 0);

        emit log_named_uint("yield", yield);
        emit log_named_uint("supply", nnETH.totalSupply());
        emit log_named_uint("underlying", nnETH.underlying());

        vm.startPrank(nnETH.ZU_CITY_TREASURY());
        nnETH.pullReserves(yield);
        vm.stopPrank();

        assertGe(yield, nnETH.aToken().balanceOf(nnETH.ZU_CITY_TREASURY()) - 1);
        assertEq(0, nnETH.reserveToken().balanceOf(nnETH.ZU_CITY_TREASURY()));
    }

    // NNETH.invariant.t.sol tests this already but do it again
    function test_pullReserves_onlyWithdrawExcessReserves(address depositor, uint256 amount) public {
        address nnCity = nnETH.ZU_CITY_TREASURY();
        assertEq(0, nnETH.underlying());
        assertEq(0, nnETH.aToken().balanceOf(nnCity));
        assertEq(0, nnETH.reserveToken().balanceOf(nnCity));

        uint256 n = _depositnnEth(depositor, amount, true);
        vm.warp(block.timestamp + 888888);
        
        uint256 yield = nnETH.getYieldEarned();
        assertGt(yield, 0);
        
        assertEq(0, nnETH.aToken().balanceOf(nnETH.ZU_CITY_TREASURY()));

        vm.startPrank(nnCity);
        uint256 reservesToPull = yield / 2;
        nnETH.pullReserves(reservesToPull);

        emit log_named_uint("interest earned", yield);
        emit log_named_uint("reserves", reservesToPull);

        // approximate bc i cant figure out this 1 wei yield from aave
        assertGe(reservesToPull + 5, nnETH.aToken().balanceOf(nnCity));
        
        emit log_named_uint("city bal 3", nnETH.reserveToken().balanceOf(nnCity));
        
        uint256 yield2 = nnETH.getYieldEarned();
        emit log_named_uint("net interest 2", yield2);
        assertGe(yield2 + 1, yield - reservesToPull); // + 1 handle /2 rounding
    }

    function test_pullReserves_revertIfOverdrawn(address depositor, uint256 amount) public {
        uint256 n = _depositnnEth(depositor, amount, true);
        vm.warp(block.timestamp + 888888);

        // assertGt(nnETH.underlying(), nnETH.totalSupply());
        // over/under flow not caused from this line

        uint256 diff = nnETH.underlying() - nnETH.totalSupply();
        assertGt(diff, 0);
        assertGt(n, diff);

        vm.startPrank(nnETH.ZU_CITY_TREASURY());
        vm.expectRevert(NNETH.InsufficientReserves.selector);
        nnETH.pullReserves(n);
    }

    function test_pullReserves_revertOverDebtRatio(address depositor, uint256 amount) public {
        uint256 n = _depositForBorrowing(depositor, amount);
        (, uint256 borrowable) = _borrowable(n);
        if(depositor == address(0x0)) return;
        if(borrowable < 1000) return;

        vm.prank(address(nnETH));
        debtUSDC.approveDelegation(depositor, n);
        vm.prank(depositor);
        aave.borrow(address(USDC), (borrowable * 2), 2, 200, address(nnETH));

        uint256 totalUnderlying = nnETH.underlying();
        uint256 unhealthyHF = nnETH.getExpectedHF();
        assertGe(nnETH.MIN_RESERVE_FACTOR(), unhealthyHF);
        assertLe(nnETH.MIN_REDEEM_FACTOR(), unhealthyHF);

        vm.startPrank(nnETH.ZU_CITY_TREASURY());
        vm.expectRevert(NNETH.InsufficientReserves.selector);
        nnETH.pullReserves(10);
        vm.stopPrank();

        // no change bc cant withdraw 
        assertEq(nnETH.underlying(), totalUnderlying);
        assertEq(unhealthyHF, nnETH.getExpectedHF());
    }


    function test_lend_borrowFailsIfOverDebtRatio(address city, uint256 _deposit) public {
        uint256 deposit = _depositForBorrowing(address(0xdead), _deposit);
        (uint256 delegatedCredit, uint256 borrowable) = _borrowable(deposit);
        
        _lend(city, borrowable);

        vm.startPrank(city);
        aave.borrow(address(USDC), borrowable, 2, 200, address(nnETH));
        
        // LTV above target
        (,,uint256 availableBorrow,,uint256 ltv,uint256 hf) = aave.getUserAccountData(address(nnETH));
        assertGe(hf, nnETH.MIN_RESERVE_FACTOR());

        uint256 debtBalance1 = nnETH.getDebt();
        // vm.expectRevert(bytes(AaveErrors.COLLATERAL_CANNOT_COVER_NEW_BORROW), address(aave));
        vm.expectRevert();
        aave.borrow(address(USDC), availableBorrow > 100 ? availableBorrow / 1e2 + 1 : 1, 2, 200, address(nnETH)); // 1 wei over target LTV should revert

        // LTV still above target
        (,,uint256 availableBorrow2,,uint256 ltv2,uint256 hf2) = aave.getUserAccountData(address(nnETH));
        assertGe(nnETH.convertToDecimal(hf2, 18, 2), nnETH.MIN_RESERVE_FACTOR());
        assertEq(nnETH.getDebt(), debtBalance1);
        vm.stopPrank();
    }

    function test_withdraw_redeemBelowReserveFactor(address user, uint256 amount) public {
        uint256 n = _depositForBorrowing(user, amount);
        (, uint256 borrowable) = _borrowable(n);
        vm.warp(block.timestamp + 888);
        vm.prank(nnETH.ZU_CITY_TREASURY());
        nnETH.lend(address(0xdead), borrowable); 
        
        uint256 safeWithdraw = (n * 3) / 4;
        vm.prank(user);
        // should be able withdraw more than reserve factor, less than redeem factor
        nnETH.withdraw(safeWithdraw);
        
        assertLt(nnETH.getExpectedHF(), nnETH.MIN_RESERVE_FACTOR());
        assertGe(nnETH.getExpectedHF(), nnETH.MIN_REDEEM_FACTOR());
    }

    function test_withdraw_revertOnMaliciousWithdraws(address user, uint256 amount) public {
        uint256 n = _depositForBorrowing(user, amount);
        (, uint256 borrowable) = _borrowable(n);
        vm.warp(block.timestamp + 888);

        vm.prank(nnETH.ZU_CITY_TREASURY());
        nnETH.lend(address(0xdead), borrowable); 

        assertGe(nnETH.getExpectedHF(), nnETH.MIN_REDEEM_FACTOR());
        
        vm.prank(user);
        vm.expectRevert(NNETH.MaliciousWithdraw.selector);
        nnETH.withdraw(n);

        // still above min redeem factor bc withdraw failed
        assertGe(nnETH.getExpectedHF(), nnETH.MIN_REDEEM_FACTOR());
    }
}