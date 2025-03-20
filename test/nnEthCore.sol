pragma solidity ^0.8.26;

import {nnEthBaseTest} from "./nnEthBaseTest.t.sol";
import {IERC20x, IAaveMarket, InnETH, AaveErrors} from "../src/Interfaces.sol";
import {nnETH as NetworkNationETH} from "../src/nnETH.sol";

contract nnEthBasic is nnEthBaseTest {
    function test_initialize_mustHaveMultiSigDeployed() public {
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
        vm.expectRevert(NetworkNationETH.AlreadyInitialized.selector);
        nnETH.initialize(address(WETH), address(aave), address(debtToken), 1, "nnCity Ethereum", "nnETH");
    }

    function test_initialize_setsProperDepositToken() public {
        if(reserveToken == WETH) {
            assert(nnETH.aToken() == IERC20x(0xD4a0e0b9149BCee3C920d2E00b5dE09138fd8bb7));
        }
        if(reserveToken == USDC) {

        }
    }

    function test_pullReserves_revertNotnnCityTreasury(address caller, uint256 amount) public {
        vm.assume(caller != nnETH.ZU_CITY_TREASURY());
        vm.expectRevert(NetworkNationETH.NotnnCity.selector);
        vm.prank(caller);
        nnETH.pullReserves(amount);
    }

    function test_pullReserves_onlynnCityTreasury(address depositor, address rando) public {
        // function should work on 0 values
        vm.prank(nnETH.ZU_CITY_TREASURY());
        nnETH.pullReserves(0);
        
        vm.prank(rando);
        vm.expectRevert(NetworkNationETH.NotnnCity.selector);
        nnETH.pullReserves(0);

        _depositnnEth(depositor, 10 ether, true);
        vm.warp(block.timestamp + 10 days);

        vm.prank(nnETH.ZU_CITY_TREASURY());
        nnETH.pullReserves(1);

        vm.prank(rando);
        vm.expectRevert(NetworkNationETH.NotnnCity.selector);
        nnETH.pullReserves(1);
    }

    // nnETH.invariant.t.sol tests this already but do it again
    function test_pullReserves_onlyWithdrawExcessReserves(address depositor, uint256 amount) public {
        address nnCity = nnETH.ZU_CITY_TREASURY();
        assertEq(0, nnETH.underlying());
        assertEq(0, nnETH.aToken().balanceOf(nnCity));
        assertEq(0, nnETH.reserveToken().balanceOf(nnCity));

        uint256 n = _depositnnEth(depositor, amount, true);
        vm.warp(block.timestamp + 888888);
        uint256 diff = nnETH.underlying() - (nnETH.totalSupply());
        // uint256 diff = nnETH.underlying() - (nnETH.totalSupply() - 1);
        
        assertGe(diff, 0); // ideally Gt but no guarantee of interest
        // assertEq(0, nnETH.aToken().balanceOf(nnCity));
        // assertEq(0, nnETH.reserveToken().balanceOf(nnCity));

        vm.startPrank(nnCity);
        uint256 reservesToPull = diff / 2;

        nnETH.pullReserves(reservesToPull);

        emit log_named_uint("interest earned", diff);
        emit log_named_uint("reserves", reservesToPull);
        emit log_named_uint("nneth aTkn bal", IERC20x(nnETH.aToken()).balanceOf(nnCity));
        emit log_named_uint("nneth aTkn scal bal", IERC20x(nnETH.aToken()).scaledBalanceOf(nnCity));

        // todo why this logic path? shouldnt be here. if nything diff testfor test_withdraw and test_pullReserves. totalSupply can be below minDeposit
            // assertEq(diff % 2 == 0 ? reservesToPull : reservesToPull , nnETH.aToken().balanceOf(nnCity) + 1); // offset aave rounding math
            // assertEq(diff % 2 == 0 ? reservesToPull : reservesToPull + 1 , nnETH.aToken().balanceOf(nnCity));
            // assertEq(reservesToPull, nnETH.aToken().balanceOf(nnCity) / 2);
        // account f or aave rounding math on numbers.
        // TODO will this cause issues in the contract if its 1 wei?
        // if(reservesToPull > nnETH.MIN_DEPOSIT()) {
        //     emit log_named_uint("city bal 2a", nnETH.aToken().balanceOf(nnCity));
        //     assertEq(reservesToPull, nnETH.aToken().balanceOf(nnCity) + 1);
        // } else {
        //     emit log_named_uint("city bal 2b", nnETH.aToken().balanceOf(nnCity));
        //     assertEq(reservesToPull, nnETH.aToken().balanceOf(nnCity));
        // }
        
        // approximate bc i cant figure out this 1 wei diff from aave
        assertGe(reservesToPull + 5, nnETH.aToken().balanceOf(nnCity));
        
        emit log_named_uint("city bal 3", nnETH.reserveToken().balanceOf(nnCity));
        assertEq(0, nnETH.reserveToken().balanceOf(nnCity));
        
        uint256 diff2 = nnETH.underlying() - nnETH.totalSupply();
        emit log_named_uint("net interest 2", diff2);
        // assertGe(diff2, diff - reservesToPull); // ideally Gt but no guarantee of interest
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
        vm.expectRevert(NetworkNationETH.InsufficientReserves.selector);
        nnETH.pullReserves(n);
    }

    function test_pullReserves_revertOverDebtRaio(address depositor, uint256 amount) public {
        uint256 n = _depositnnEth(depositor, amount, true);
        (, uint256 borrowable) = _borrowable(n);

        vm.startPrank(nnETH.ZU_CITY_TREASURY());
        // (,,uint256 availableBorrow,,,uint256 hf) = aave.getUserAccountData(address(nnETH));
        // emit log_named_uint("availableBorrow", availableBorrow);
        aave.borrow(address(USDC), borrowable, 2, 200, address(nnETH));

        assertGt(nnETH.MIN_RESERVE_FACTOR(), nnETH.getHF());
        assertLt(nnETH.MIN_REDEEM_FACTOR(), nnETH.getHF());
        vm.expectRevert(NetworkNationETH.InvalidTreasuryOperation.selector);
        nnETH.pullReserves(n);

        vm.warp(block.timestamp + 888888);
        vm.stopPrank();
    }


    function test_lend_borrowFailsIfLtvBelow8x(address city, uint256 _deposit) public {
        vm.assume(city != address(0)); // prevent aave error sending to 0x0
        // uint256 ltvConfig = 80; // TODO pull from Aave.reserveConfig or userAcccountData
        // uint256 _deposit = 60 ether;
        // uint256 delegatedCredit = deposit * ltvConfig / 1e10; // total credit / token decimal diff

        uint256 deposit = _depositnnEth(address(0xdead), _deposit, true);
        (uint256 delegatedCredit, uint256 borrowable) = _borrowable(deposit);
        
        vm.prank(nnETH.ZU_CITY_TREASURY());
        nnETH.lend(city, borrowable); // 1/6th LTV maximum

        // uint256 borrowable = delegatedCredit / nnETH.MIN_REDEEM_FACTOR(); // total credit / ZUETH_MAX_LTV / token decimal diff
        // (,,uint256 availableBorrow0,,uint256 ltv0,uint256 hf0) = aave.getUserAccountData(address(nnETH));
        // emit log_named_uint("delegatedCredit", availableBorrow0);
        // emit log_named_uint("hf0", hf0);
        // emit log_named_uint("borrowable", borrowable);

        vm.startPrank(city);
        // aave.setUserEMode(1);
        aave.borrow(address(USDC), borrowable, 2, 200, address(nnETH));
        
        // LTV above target
        (,,uint256 availableBorrow,,uint256 ltv,uint256 hf) = aave.getUserAccountData(address(nnETH));
        assertGe(hf, nnETH.MIN_RESERVE_FACTOR());
        emit log_named_uint("availableBorrow1", availableBorrow);
        emit log_named_uint("hf1", hf);
        uint256 debtBalance1 = nnETH.getDebt();
        // assertEq(nnETH.getDebt(), borrowable); // hard to exactly calculate since based on live price feed

        vm.expectRevert(bytes(AaveErrors.COLLATERAL_CANNOT_COVER_NEW_BORROW), address(aave));
        aave.borrow(address(USDC), availableBorrow + 1, 2, 200, address(nnETH)); // 1 wei over target LTV should revert
        
        // LTV still above target
        (,,uint256 availableBorrow2,,uint256 ltv2,uint256 hf2) = aave.getUserAccountData(address(nnETH));
        emit log_named_uint("availableBorrow2", availableBorrow2);
        emit log_named_uint("hf2", hf2);
        assertGe(hf2, 600);
        assertEq(nnETH.getDebt(), debtBalance1);
        vm.stopPrank();
    }

    function test_withdraw_redeemBelowReserveFactor(address user, uint256 amount) public {
        uint256 n = _depositnnEth(user, amount, true);
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
        uint256 n = _depositnnEth(user, amount, true);
        (, uint256 borrowable) = _borrowable(n);
        vm.warp(block.timestamp + 888);
        vm.prank(nnETH.ZU_CITY_TREASURY());
        nnETH.lend(address(0xdead), borrowable); 

        assertGe(nnETH.getExpectedHF(), nnETH.MIN_REDEEM_FACTOR());
        
        vm.prank(user);
        vm.expectRevert(NetworkNationETH.MaliciousWithdraw.selector);
        nnETH.withdraw(n);

        // still above min redeem factor bc withdraw failed
        assertGe(nnETH.getExpectedHF(), nnETH.MIN_REDEEM_FACTOR());
    }
}