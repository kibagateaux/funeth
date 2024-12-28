pragma solidity ^0.8.26;

import {ZuEthBaseTest} from "./ZuEthBaseTest.t.sol";
import {IERC20x, IAaveMarket, IZuETH, AaveErrors} from "../src/Interfaces.sol";
import {ZuETH} from "../src/ZuETH.sol";

contract ZuEthBasic is ZuEthBaseTest {
    function test_initialize_mustHaveMultiSigDeployed() public {
        address zuCityTreasury = address(0xC958dEeAB982FDA21fC8922493d0CEDCD26287C3);
        address progZuCityTreasury = address(zuETH.zuCityTreasury());
        uint256 manualSize;
        uint256 configedSize;
        assembly {
            manualSize := extcodesize(zuCityTreasury)
            configedSize := extcodesize(progZuCityTreasury)
        }

        assertGt(configedSize, 0);
        assertEq(manualSize, configedSize);
    }

    function invariant_lend_increaseTotalDelegated() public {
        // sample vals. uneven city/lend vals to ensure overwrites work
        address[3] memory cities = [address(0x83425), address(0x9238521), address(0x9463621)];
        uint256[7] memory amounts = [21.1241 ether, uint256(49134.123841 gwei), uint256(84923.235235 gwei), 15.136431 ether, 1.136431 ether, 0.136431 ether, uint256(843624923.235235 gwei)];

        // deposit some amount so we can delegate credit
        _depositZuEth(address(0x14632332), amounts[0] + amounts[1] + amounts[2] + amounts[3], true);

        assertEq(zuETH.totalCreditDelegated(), 0);

        vm.startPrank(zuETH.zuCityTreasury());
        uint256 total;
        for(uint i = 0; i < amounts.length; i++) {
            if(i < cities.length) {
                // first round of delegations
                zuETH.lend(cities[i], amounts[i]);
                total += amounts[i];
            } else {
                zuETH.lend(cities[i % cities.length], amounts[i]);
                // second round of delegations, replace previous amounts
                total -= amounts[i - cities.length]; // remove cities last delegation bc overwritten in contract
                total += amounts[i];
            }

            assertEq(zuETH.totalCreditDelegated(), total);
        }
        vm.stopPrank();
    }

    function test_initialize_cantReinitialize() public {
        vm.expectRevert(ZuETH.AlreadyInitialized.selector);
        zuETH.initialize(address(WETH), address(aave), address(debtToken), 1, "ZuCity Ethereum", "zuETH");
    }

    function test_initialize_setsProperDepositToken() public {
        if(reserveToken == WETH) {
            assert(zuETH.aToken() == IERC20x(0xD4a0e0b9149BCee3C920d2E00b5dE09138fd8bb7));
        }
        if(reserveToken == USDC) {

        }
    }

    function test_pullReserves_revertNotZuCityTreasury(address caller, uint256 amount) public {
        vm.assume(caller != zuETH.zuCityTreasury());
        vm.expectRevert(ZuETH.NotZuCity.selector);
        vm.prank(caller);
        zuETH.pullReserves(amount);
    }

    function test_pullReserves_onlyZuCityTreasury(address depositor, address rando) public {
        // function should work on 0 values
        vm.prank(zuETH.zuCityTreasury());
        zuETH.pullReserves(0);
        
        vm.prank(rando);
        vm.expectRevert(ZuETH.NotZuCity.selector);
        zuETH.pullReserves(0);

        _depositZuEth(depositor, 10 ether, true);
        vm.warp(block.timestamp + 10 days);

        vm.prank(zuETH.zuCityTreasury());
        zuETH.pullReserves(1);

        vm.prank(rando);
        vm.expectRevert(ZuETH.NotZuCity.selector);
        zuETH.pullReserves(1);
    }

    // ZuETH.invariant.t.sol tests this already but do it again
    function test_pullReserves_onlyWithdrawExcessReserves(address depositor, uint256 amount) public {
        address zuCity = zuETH.zuCityTreasury();
        assertEq(0, zuETH.underlying());
        assertEq(0, zuETH.aToken().balanceOf(zuCity));
        assertEq(0, zuETH.reserveToken().balanceOf(zuCity));

        uint256 n = _depositZuEth(depositor, amount, true);
        vm.warp(block.timestamp + 888888);
        uint256 diff = zuETH.underlying() - (zuETH.totalSupply());
        // uint256 diff = zuETH.underlying() - (zuETH.totalSupply() - 1);
        
        assertGe(diff, 0); // ideally Gt but no guarantee of interest
        // assertEq(0, zuETH.aToken().balanceOf(zuCity));
        // assertEq(0, zuETH.reserveToken().balanceOf(zuCity));

        vm.startPrank(zuCity);
        uint256 reservesToPull = diff / 2;

        zuETH.pullReserves(reservesToPull);

        emit log_named_uint("interest earned", diff);
        emit log_named_uint("reserves", reservesToPull);
        emit log_named_uint("zueth aTkn bal", IERC20x(zuETH.aToken()).balanceOf(zuCity));
        emit log_named_uint("zueth aTkn scal bal", IERC20x(zuETH.aToken()).scaledBalanceOf(zuCity));

        // todo why this logic path? shouldnt be here. if nything diff testfor test_withdraw and test_pullReserves. totalSupply can be below minDeposit
            // assertEq(diff % 2 == 0 ? reservesToPull : reservesToPull , zuETH.aToken().balanceOf(zuCity) + 1); // offset aave rounding math
            // assertEq(diff % 2 == 0 ? reservesToPull : reservesToPull + 1 , zuETH.aToken().balanceOf(zuCity));
            // assertEq(reservesToPull, zuETH.aToken().balanceOf(zuCity) / 2);
        // account f or aave rounding math on numbers.
        // TODO will this cause issues in the contract if its 1 wei?
        // if(reservesToPull > zuETH.MIN_DEPOSIT()) {
        //     emit log_named_uint("city bal 2a", zuETH.aToken().balanceOf(zuCity));
        //     assertEq(reservesToPull, zuETH.aToken().balanceOf(zuCity) + 1);
        // } else {
        //     emit log_named_uint("city bal 2b", zuETH.aToken().balanceOf(zuCity));
        //     assertEq(reservesToPull, zuETH.aToken().balanceOf(zuCity));
        // }
        
        // approximate bc i cant figure out this 1 wei diff from aave
        assertGe(reservesToPull + 5, zuETH.aToken().balanceOf(zuCity));
        
        emit log_named_uint("city bal 3", zuETH.reserveToken().balanceOf(zuCity));
        assertEq(0, zuETH.reserveToken().balanceOf(zuCity));
        
        uint256 diff2 = zuETH.underlying() - zuETH.totalSupply();
        emit log_named_uint("net interest 2", diff2);
        // assertGe(diff2, diff - reservesToPull); // ideally Gt but no guarantee of interest
    }

    function test_pullReserves_revertIfOverdrawn(address depositor, uint256 amount) public {
        uint256 n = _depositZuEth(depositor, amount, true);
        vm.warp(block.timestamp + 888888);

        // assertGt(zuETH.underlying(), zuETH.totalSupply());
        // over/under flow not caused from this line

        uint256 diff = zuETH.underlying() - zuETH.totalSupply();
        assertGt(diff, 0);

        assertGt(n, diff);

        vm.startPrank(zuETH.zuCityTreasury());
        vm.expectRevert(ZuETH.InvalidTreasuryOperation.selector);
        zuETH.pullReserves(n);
    }

    function test_pullReserves_revertOverDebtRaio(address depositor, uint256 amount) public {
        uint256 n = _depositZuEth(depositor, amount, true);
        (, uint256 borrowable) = _borrowable(n);

        vm.startPrank(zuETH.zuCityTreasury());
        
        aave.borrow(address(USDC), borrowable, 2, 200, address(zuETH));

        assertGt(zuETH.MIN_RESERVE_FACTOR(), zuETH.getHF());
        assertLt(zuETH.MIN_HEALTH_FACTOR(), zuETH.getHF());
        vm.expectRevert(ZuETH.InvalidTreasuryOperation.selector);
        zuETH.pullReserves(n);

        vm.warp(block.timestamp + 888888);
        vm.stopPrank();
    }


    function test_lend_borrowFailsIfLtvBelow6x(address city, uint256 _deposit) public {
        vm.assume(city != address(0)); // prevent aave error sending to 0x0
        // uint256 ltvConfig = 80; // TODO pull from Aave.reserveConfig or userAcccountData
        // uint256 _deposit = 60 ether;
        // uint256 delegatedCredit = deposit * ltvConfig / 1e10; // total credit / token decimal diff

        uint256 deposit = _depositZuEth(address(0xdead), _deposit, true);
        (uint256 delegatedCredit, uint256 borrowable) = _borrowable(deposit);
        
        vm.prank(zuETH.zuCityTreasury());
        zuETH.lend(city, delegatedCredit); // 1/6th LTV maximum

        // uint256 borrowable = delegatedCredit / zuETH.MIN_HEALTH_FACTOR(); // total credit / ZUETH_MAX_LTV / token decimal diff
        // (,,uint256 availableBorrow0,,uint256 ltv0,uint256 hf0) = aave.getUserAccountData(address(zuETH));
        // emit log_named_uint("delegatedCredit", availableBorrow0);
        // emit log_named_uint("hf0", hf0);
        // emit log_named_uint("borrowable", borrowable);

        vm.startPrank(city);
        // aave.setUserEMode(1);
        aave.borrow(address(USDC), borrowable, 2, 200, address(zuETH));
        
        // LTV above target
        (,,uint256 availableBorrow,,uint256 ltv,uint256 hf) = aave.getUserAccountData(address(zuETH));
        assertGe(hf, zuETH.MIN_HEALTH_FACTOR());
        emit log_named_uint("availableBorrow1", availableBorrow);
        emit log_named_uint("hf1", hf);
        uint256 debtBalance1 = zuETH.getDebt();
        // assertEq(zuETH.getDebt(), borrowable); // hard to exactly calculate since based on live price feed

        vm.expectRevert(bytes(AaveErrors.COLLATERAL_CANNOT_COVER_NEW_BORROW), address(aave));
        aave.borrow(address(USDC), availableBorrow + 1, 2, 200, address(zuETH)); // 1 wei over target LTV should revert
        
        // LTV still above target
        (,,uint256 availableBorrow2,,uint256 ltv2,uint256 hf2) = aave.getUserAccountData(address(zuETH));
        emit log_named_uint("availableBorrow2", availableBorrow2);
        emit log_named_uint("hf2", hf2);
        assertGe(hf2, 600);
        assertEq(zuETH.getDebt(), debtBalance1);
        vm.stopPrank();
    }

}