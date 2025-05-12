pragma solidity ^0.8.26;

import {Ownable} from "solady/auth/Ownable.sol";
import {FunETHBaseTest} from "./FunETHBaseTest.t.sol";
import {IERC20x, IAaveMarket, IFunETH, AaveErrors} from "../../src/Interfaces.sol";
import {FunETH} from "../../src/FunETH.sol";

contract FunETHCore is FunETHBaseTest {
    function test_initialize_mustHaveMultiSigDeployed() public view {
        address funCityTreasury = address(0xC958dEeAB982FDA21fC8922493d0CEDCD26287C3);
        address progfunCityTreasury = address(funETH.FUN_OPS());
        uint256 manualSize;
        uint256 configedSize;
        assembly {
            manualSize := extcodesize(funCityTreasury)
            configedSize := extcodesize(progfunCityTreasury)
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
        (,, uint256 availableBorrow,,, uint256 hf) = aave.getUserAccountData(address(funETH));
        assertGt(availableBorrow, 100000000);

        address rsa = factory.deployFunFunding(address(0), address(funETH.debtAsset()), 100, "test", "test");
        vm.startPrank(funETH.FUN_OPS());
        assertEq(funETH.totalCreditDelegated(), 0);
        funETH.lend(cities[0], rsa, amounts[0]);
        assertEq(funETH.totalCreditDelegated(), amounts[0]);
        funETH.lend(cities[1], rsa, amounts[1]);
        assertEq(funETH.totalCreditDelegated(), amounts[0] + amounts[1]);
        funETH.lend(cities[0], rsa, amounts[2]);
        assertEq(funETH.totalCreditDelegated(), amounts[2] + amounts[1]);
        funETH.lend(cities[1], rsa, amounts[3]);
        assertEq(funETH.totalCreditDelegated(), amounts[2] + amounts[3]);

        vm.stopPrank();
    }

    function test_initialize_configSetup() public virtual {
        assertEq(address(reserveToken), address(WETH));
        assertEq(address(debtToken), address(debtUSDC));
        assertEq(address(borrowToken), address(USDC));
    }

    function test_initialize_cantReinitialize() public {
        vm.expectRevert(Ownable.AlreadyInitialized.selector);
        funETH.initialize(address(reserveToken), address(aave), address(debtToken), "funCity Ethereum", "funETH");
    }

    function test_increaseAllowance_updatesAllowanceValue() public {
        vm.prank(funETH.FUN_OPS());
        funETH.increaseAllowance(address(0xbeef), 1000 ether);
        assertEq(funETH.allowance(funETH.FUN_OPS(), address(0xbeef)), 1000 ether);
        vm.prank(funETH.FUN_OPS());
        funETH.increaseAllowance(address(0xbeef), 1000 ether);
        assertEq(funETH.allowance(funETH.FUN_OPS(), address(0xbeef)), 2000 ether);
    }

    function test_increaseAllowance_emitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit IERC20x.Approval(funETH.FUN_OPS(), address(0xbeef), 1000 ether);
        vm.prank(funETH.FUN_OPS());
        funETH.increaseAllowance(address(0xbeef), 1000 ether);
        vm.expectEmit(true, true, true, true);
        emit IERC20x.Approval(funETH.FUN_OPS(), address(0xbeef), 2000 ether);
        vm.prank(funETH.FUN_OPS());
        funETH.increaseAllowance(address(0xbeef), 1000 ether);
    }

    function test_initialize_setsProperDepositToken() public view {
        if (address(funETH.reserveToken()) == address(WETH)) {
            assertEq(address(funETH.aToken()), address(0xD4a0e0b9149BCee3C920d2E00b5dE09138fd8bb7));
            return;
        } else if (address(funETH.reserveToken()) == address(USDC)) {
            assertEq(address(funETH.aToken()), address(0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB));
        } else {
            revert("Invalid reserve token");
        }
    }

    function test_deposit_revertsOn0AddressReceiver(address user, uint256 amount) public assumeValidAddress(user) {
        uint256 n = _depositnnEth(user, amount, true);
        vm.prank(user);
        reserveToken.approve(address(funETH), n);

        vm.expectRevert(FunETH.InvalidReceiver.selector);
        vm.prank(user);
        funETH.depositOnBehalfOf(n, address(0), makeAddr("boogawugi"));
    }

    function test_deposit_revertsOnBelowMinDeposit(address user, uint256 amount) public assumeValidAddress(user) {
        vm.assume(amount < funETH.MIN_DEPOSIT());

        vm.prank(user);
        reserveToken.approve(address(funETH), amount);

        vm.prank(user);
        vm.expectRevert(FunETH.BelowMinDeposit.selector);
        funETH.deposit(amount);
    }

    function test_deposit_emitsProperEvent(address user, uint256 amount) public assumeValidAddress(user) {
        uint256 n = _boundDepositAmount(amount, false);
        deal(address(reserveToken), user, n);

        vm.startPrank(user);
        reserveToken.approve(address(funETH), n);

        vm.expectEmit(true, true, true, true);
        emit FunETH.Deposit(user, user, n, funETH.FUN_OPS(), address(funETH));
        funETH.deposit(n);
        vm.stopPrank();
    }

    function test_depositOnBehalfOf_emitsProperEvent(address user, uint256 amount) public assumeValidAddress(user) {
        uint256 n = _boundDepositAmount(amount, false);
        deal(address(reserveToken), user, n);

        vm.startPrank(user);
        reserveToken.approve(address(funETH), n);

        vm.expectEmit(true, true, true, true);
        emit FunETH.Deposit(user, makeAddr("boogawugi"), n, funETH.FUN_OPS(), address(0xbeef));
        funETH.depositOnBehalfOf(n, makeAddr("boogawugi"), address(0xbeef));
        vm.stopPrank();
    }

    function test_depositOnBehalfOf_updatesProperRecipient(address user, uint256 amount)
        public
        assumeValidAddress(user)
    {
        uint256 n = _boundDepositAmount(amount, false);
        deal(address(reserveToken), user, n);

        vm.startPrank(user);
        reserveToken.approve(address(funETH), n);
        funETH.depositOnBehalfOf(n, address(0xbeef), makeAddr("boogawugi"));
        vm.stopPrank();

        assertEq(funETH.balanceOf(user), 0);
        assertEq(funETH.balanceOf(address(0xbeef)), n);
    }

    function test_depositWithPreference_emitsProperEvent(address user, uint256 amount)
        public
        assumeValidAddress(user)
    {
        uint256 n = _boundDepositAmount(amount, false);
        deal(address(reserveToken), user, n);

        vm.startPrank(user);
        reserveToken.approve(address(funETH), n);

        vm.expectEmit(true, true, true, true);
        emit FunETH.Deposit(user, user, n, funETH.FUN_OPS(), address(0xbeef));
        funETH.depositWithPreference(n, funETH.FUN_OPS(), address(0xbeef));
        vm.stopPrank();
    }

    function test_depositAndApprove_emitsProperEvent(address user, uint256 amount) public assumeValidAddress(user) {
        uint256 n = _boundDepositAmount(amount, false);
        deal(address(reserveToken), user, n);

        vm.startPrank(user);
        reserveToken.approve(address(funETH), n);

        vm.expectEmit(true, true, true, true);
        emit FunETH.Deposit(user, user, n, funETH.FUN_OPS(), address(funETH));
        funETH.depositAndApprove(address(0xbeef), n);
        vm.stopPrank();
    }

    function test_depositAndApprove_updatesAllowance(address user, uint256 amount) public assumeValidAddress(user) {
        uint256 n = _boundDepositAmount(amount, false);
        deal(address(reserveToken), user, n);
        vm.startPrank(user);
        reserveToken.approve(address(funETH), n);
        funETH.depositAndApprove(address(0xbeef), n);
        vm.stopPrank();
        assertEq(funETH.allowance(user, address(0xbeef)), n);
    }

    function test_pullReserves_revertNotfunCityTreasury(address caller, uint256 amount) public {
        vm.assume(caller != funETH.FUN_OPS());
        vm.prank(caller);
        vm.expectRevert(FunETH.NotfunCity.selector);
        funETH.pullReserves(amount, address(0));
    }

    function test_pullReserves_onlyfunCityTreasury(address depositor, address rando)
        public
        assumeValidAddress(rando)
        assumeValidAddress(depositor)
    {
        vm.assume(rando != funETH.FUN_OPS());

        // auth should work on 0 yield, 0 deposits
        vm.prank(funETH.FUN_OPS());
        funETH.pullReserves(0, address(0));

        vm.prank(rando);
        vm.expectRevert(FunETH.NotfunCity.selector);
        funETH.pullReserves(0, address(0));

        // auth should work w/ yield/deposits
        _depositnnEth(depositor, 10 ether, true);
        vm.warp(block.timestamp + 10 days);

        vm.prank(funETH.FUN_OPS());
        funETH.pullReserves(0.1 ether, address(0));

        vm.prank(rando);
        vm.expectRevert(FunETH.NotfunCity.selector);
        funETH.pullReserves(0.1 ether, address(0));
    }

    function invariant_getYieldEarned_aTokenVsTotalSupply() public {
        uint256 n = _depositnnEth(address(0x14632332), 100 ether, true);
        vm.warp(block.timestamp + 888888);

        // check raw aave values calculations
        uint256 diff =
            (funETH.aToken().balanceOf(address(funETH)) / funETH.reserveVsATokenDecimalOffset()) - funETH.totalSupply();

        // check internal decimaled calculations
        uint256 diff2 = funETH.underlying() - funETH.totalSupply();

        assertGt(diff, 0);
        // - 1 to account for rounding errors btw aave tokens
        assertGe(diff, diff2 - 1);
        assertGe(funETH.getYieldEarned(), diff - 1);
    }

    // TODO test reserveToken price goes down and becomes liquidatable
    // reserveToken price goes up and more credit available
    //

    function test_pullReserves_sendsATokenToTreasury(address depositor, uint256 amount)
        public
        assumeValidAddress(depositor)
    {
        uint256 n = _depositnnEth(depositor, amount, true);
        vm.warp(block.timestamp + 888888);

        uint256 yield = funETH.getYieldEarned();
        assertGt(yield, 0);

        emit log_named_uint("yield", yield);
        emit log_named_uint("supply", funETH.totalSupply());
        emit log_named_uint("underlying", funETH.underlying());

        vm.startPrank(funETH.FUN_OPS());
        funETH.pullReserves(yield, address(0));
        vm.stopPrank();

        assertGe(yield, funETH.aToken().balanceOf(funETH.FUN_OPS()) - 1);
        assertEq(0, funETH.reserveToken().balanceOf(funETH.FUN_OPS()));
    }

    // FunETH.invariant.t.sol tests this already but do it again
    function test_pullReserves_onlyWithdrawExcessReserves(address depositor, uint256 amount)
        public
        assumeValidAddress(depositor)
    {
        address funCity = funETH.FUN_OPS();
        assertEq(0, funETH.underlying());
        assertEq(0, funETH.aToken().balanceOf(funCity));
        assertEq(0, funETH.reserveToken().balanceOf(funCity));

        uint256 n = _depositnnEth(depositor, amount, true);
        vm.warp(block.timestamp + 888888);

        uint256 yield = funETH.getYieldEarned();
        assertGt(yield, 0);

        assertEq(0, funETH.aToken().balanceOf(funETH.FUN_OPS()));

        vm.startPrank(funCity);
        uint256 reservesToPull = yield / 2;
        funETH.pullReserves(reservesToPull, address(0));

        emit log_named_uint("interest earned", yield);
        emit log_named_uint("reserves", reservesToPull);

        // approximate bc i cant figure out this 1 wei yield from aave
        assertGe(reservesToPull + 5, funETH.aToken().balanceOf(funCity));

        emit log_named_uint("city bal 3", funETH.reserveToken().balanceOf(funCity));

        uint256 yield2 = funETH.getYieldEarned();
        emit log_named_uint("net interest 2", yield2);
        assertGe(yield2 + 1, yield - reservesToPull); // + 1 handle /2 rounding
    }

    function test_pullReserves_revertIfOverdrawn(address depositor, uint256 amount)
        public
        assumeValidAddress(depositor)
    {
        uint256 n = _depositnnEth(depositor, amount, true);
        vm.warp(block.timestamp + 888888);

        // assertGt(funETH.underlying(), funETH.totalSupply());
        // over/under flow not caused from this line

        uint256 diff = funETH.underlying() - funETH.totalSupply();
        assertGt(diff, 0);
        assertGt(n, diff);

        vm.startPrank(funETH.FUN_OPS());
        vm.expectRevert(FunETH.InsufficientReserves.selector);
        funETH.pullReserves(n, address(0));
    }

    function test_pullReserves_revertOverDebtRatio(address depositor, uint256 amount)
        public
        assumeValidAddress(depositor)
    {
        uint256 n = _depositForBorrowing(depositor, amount);
        (, uint256 borrowable) = _borrowable(n);
        // if(borrowable < 1000) return;

        vm.prank(address(funETH));
        debtToken.approveDelegation(depositor, borrowable * 10); // outside FunETH so doesnt affect getExpectedHF until borrow
        vm.prank(depositor);
        aave.borrow(borrowToken, borrowable * 2, 2, 200, address(funETH));

        uint256 totalUnderlying = funETH.underlying();
        uint256 unhealthyHF = funETH.getExpectedHF();
        assertGe(funETH.MIN_RESERVE_FACTOR(), unhealthyHF);
        assertLe(funETH.MIN_REDEEM_FACTOR(), unhealthyHF);

        vm.startPrank(funETH.FUN_OPS());
        vm.expectRevert(FunETH.InsufficientReserves.selector);
        funETH.pullReserves(10, address(0));
        vm.stopPrank();

        // no change bc cant withdraw
        assertEq(funETH.underlying(), totalUnderlying);
        assertEq(unhealthyHF, funETH.getExpectedHF());
    }

    function test_lend_borrowFailsIfOverDebtRatio(address city, uint256 _deposit) public assumeValidAddress(city) {
        uint256 deposit = _depositForBorrowing(makeAddr("boogawugi"), _deposit);
        (uint256 delegatedCredit, uint256 borrowable) = _borrowable(deposit);

        _lend(city, borrowable);

        vm.startPrank(city);
        aave.borrow(borrowToken, borrowable, 2, 200, address(funETH));

        // LTV above target
        (,, uint256 availableBorrow,, uint256 ltv, uint256 hf) = aave.getUserAccountData(address(funETH));
        assertGe(hf, funETH.MIN_RESERVE_FACTOR());

        // uint256 debtBalance1 = funETH.getDebt();
        // vm.expectRevert(bytes(AaveErrors.COLLATERAL_CANNOT_COVER_NEW_BORROW), address(aave));
        vm.expectRevert();
        aave.borrow(borrowToken, availableBorrow > 100 ? availableBorrow / 1e2 + 1 : 1, 2, 200, address(funETH)); // 1 wei over target LTV should revert

        // LTV still above target
        (,, uint256 availableBorrow2,, uint256 ltv2, uint256 hf2) = aave.getUserAccountData(address(funETH));
        assertGe(funETH.convertToDecimal(hf2, 18, 2), funETH.MIN_RESERVE_FACTOR());
        // assertEq(funETH.getDebt(), debtBalance1);
        vm.stopPrank();
    }

    function test_withdraw_redeemBelowReserveFactor(address user, uint256 amount) public assumeValidAddress(user) {
        uint256 n = _depositForBorrowing(user, amount);
        (, uint256 borrowable) = _borrowable(n);
        vm.warp(block.timestamp + 888);
        vm.prank(funETH.FUN_OPS());
        address rsa = factory.deployFunFunding(address(0), address(funETH.debtAsset()), 100, "test", "test");
        funETH.lend(makeAddr("boogawugi"), rsa, borrowable);

        uint256 safeWithdraw = (n * 3) / 4;
        vm.prank(user);
        // should be able withdraw more than reserve factor, less than redeem factor
        funETH.withdraw(safeWithdraw);

        assertLt(funETH.getExpectedHF(), funETH.MIN_RESERVE_FACTOR());
        assertGe(funETH.getExpectedHF(), funETH.MIN_REDEEM_FACTOR());
    }

    function test_withdraw_revertOnMaliciousWithdraws(address user, uint256 amount) public assumeValidAddress(user) {
        uint256 n = _depositForBorrowing(user, amount);
        (, uint256 borrowable) = _borrowable(n);
        vm.warp(block.timestamp + 888);

        address rsa = factory.deployFunFunding(address(0), address(funETH.debtAsset()), 100, "test", "test");
        vm.prank(funETH.FUN_OPS());
        funETH.lend(makeAddr("boogawugi"), rsa, borrowable);

        assertGe(funETH.getExpectedHF(), funETH.MIN_REDEEM_FACTOR());

        vm.expectRevert(FunETH.MaliciousWithdraw.selector);
        _withdrawnnEth(user, n);
        // still above min redeem factor bc withdraw failed
        assertGe(funETH.getExpectedHF(), funETH.MIN_REDEEM_FACTOR());
    }

    function test_withdrawTo_updatesProperBalances(address user, uint256 amount) public assumeValidAddress(user) {
        uint256 n = _depositnnEth(user, amount, true);
        assertEq(funETH.balanceOf(user), n);
        emit log_named_uint("recipient init balance ", funETH.balanceOf(makeAddr("boogawugi")));
        assertEq(funETH.balanceOf(makeAddr("boogawugi")), 0);
        assertEq(reserveToken.balanceOf(user), 0);
        emit log_named_uint("recipient init balance ", reserveToken.balanceOf(makeAddr("boogawugi")));
        assertEq(reserveToken.balanceOf(makeAddr("boogawugi")), 0);

        uint256 withdrawn = n / 2;
        vm.prank(user);
        funETH.withdrawTo(withdrawn, makeAddr("boogawugi"));

        emit log_named_uint("user remaining balance ", funETH.balanceOf(user));
        assertEq(reserveToken.balanceOf(user), 0);
        assertEq(funETH.balanceOf(user), n - withdrawn);

        emit log_named_address("reserve token ", address(reserveToken));
        assertEq(reserveToken.balanceOf(makeAddr("boogawugi")), withdrawn);
        emit log_named_uint("recipient remaining balance ", funETH.balanceOf(makeAddr("boogawugi")));
        assertEq(funETH.balanceOf(makeAddr("boogawugi")), 0);
    }
}
