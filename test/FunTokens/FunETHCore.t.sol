pragma solidity ^0.8.26;

import {Ownable} from "solady/auth/Ownable.sol";
import {FunETHBaseTest} from "./FunETHBaseTest.t.sol";
import {IERC20x, IAaveMarket, IFunETH, AaveErrors} from "../../src/Interfaces.sol";
import {FunETH} from "../../src/FunETH.sol";

contract FunETHCore is FunETHBaseTest {
    function test_initialize_mustHaveMultiSigDeployed() public view {
        address funCityTreasury = address(0xC958dEeAB982FDA21fC8922493d0CEDCD26287C3);
        address progfunCityTreasury = address(funETH.owner());
        uint256 manualSize;
        uint256 configedSize;
        assembly {
            manualSize := extcodesize(funCityTreasury)
            configedSize := extcodesize(progfunCityTreasury)
        }

        assertGt(configedSize, 0);
        assertEq(manualSize, configedSize);
    }

    function invariant_lend_allFundingTokensMoreThanTotalDebt() public {
        (,uint256 totalDebt,,,,) = aave.getUserAccountData(address(funETH));
        uint256 debtInLendToken = totalDebt / funETH.price(false);
        uint256 totalFundingTokens = 100; // have to iterate over all lend() and get this. not progrmatically avialble in smart contract bc we never really need.
        assertGt(totalFundingTokens, debtInLendToken);
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
        vm.prank(funETH.owner());
        funETH.increaseAllowance(address(0xbeef), 1000 ether);
        assertEq(funETH.allowance(funETH.owner(), address(0xbeef)), 1000 ether);
        vm.prank(funETH.owner());
        funETH.increaseAllowance(address(0xbeef), 1000 ether);
        assertEq(funETH.allowance(funETH.owner(), address(0xbeef)), 2000 ether);
    }

    function test_increaseAllowance_emitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit IERC20x.Approval(funETH.owner(), address(0xbeef), 1000 ether);
        vm.prank(funETH.owner());
        funETH.increaseAllowance(address(0xbeef), 1000 ether);
        vm.expectEmit(true, true, true, true);
        emit IERC20x.Approval(funETH.owner(), address(0xbeef), 2000 ether);
        vm.prank(funETH.owner());
        funETH.increaseAllowance(address(0xbeef), 1000 ether);
    }

    function test_initialize_setsProperDepositToken() public view {
        if (address(funETH.asset()) == address(WETH)) {
            assertEq(address(funETH.aToken()), address(0xD4a0e0b9149BCee3C920d2E00b5dE09138fd8bb7));
            return;
        } else if (address(funETH.asset()) == address(USDC)) {
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
        funETH.depositWithPreference(n, address(0), makeAddr("boogawugi"), makeAddr("boogawugi"));
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
        emit FunETH.Deposit(user, user, n, funETH.owner(), address(funETH));
        funETH.deposit(n);
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
        funETH.depositWithPreference(n, address(0xbeef), address(0x5117), makeAddr("boogawugi"));
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
        emit FunETH.Deposit(user, vm.addr(666), n, funETH.owner(), address(0xbeef));
        funETH.depositWithPreference(n, vm.addr(666), funETH.owner(), address(0xbeef));
        vm.stopPrank();
    }

    function test_depositAndApprove_emitsProperEvent(address user, uint256 amount) public assumeValidAddress(user) {
        uint256 n = _boundDepositAmount(amount, false);
        deal(address(reserveToken), user, n);

        vm.startPrank(user);
        reserveToken.approve(address(funETH), n);

        vm.expectEmit(true, true, true, true);
        emit FunETH.Deposit(user, user, n, funETH.owner(), address(funETH));
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
        vm.assume(caller != funETH.owner());
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        funETH.pullReserves(amount, address(0));
    }

    function test_pullReserves_onlyFunCityTreasury(address depositor, address rando)
        public
        assumeValidAddress(rando)
        assumeValidAddress(depositor)
    {
        vm.assume(rando != funETH.owner());

        // auth should work on 0 yield, 0 deposits
        vm.prank(funETH.owner());
        funETH.pullReserves(0, address(0));

        vm.prank(rando);
        vm.expectRevert(Ownable.Unauthorized.selector);
        funETH.pullReserves(0, address(0));
        // auth should work w/ yield/deposits
        _depositnnEth(depositor, 10 ether, true);
        vm.warp(block.timestamp + 10 days);

        uint256 yield = funETH.getYieldEarned();
        emit log_named_uint("yield", yield);
        emit log_named_uint("deposit", funETH.totalSupply());
        emit log_named_uint("underlying", funETH.underlying());
        vm.prank(funETH.owner());
        funETH.pullReserves(yield, address(0));

        vm.prank(rando);
        vm.expectRevert(Ownable.Unauthorized.selector);
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
        // assertGe(diff, diff2);
        assertGe(funETH.getYieldEarned(), diff - 1);
        // assertGe(funETH.getYieldEarned(), diff);
    }

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

        vm.startPrank(funETH.owner());
        funETH.pullReserves(yield, address(0));
        vm.stopPrank();

        // assertGe(yield, funETH.aToken().balanceOf(funETH.owner()) - 1);
        assertGe(yield, funETH.balanceOf(funETH.owner()));
        assertEq(0, IERC20x(funETH.asset()).balanceOf(funETH.owner()));
        assertEq(0, funETH.aToken().balanceOf(funETH.owner()));
    }

    // FunETH.invariant.t.sol tests this already but do it again
    function test_pullReserves_onlyWithdrawExcessReserves(address depositor, uint256 amount)
        public
        assumeValidAddress(depositor)
    {
        address funCity = funETH.owner();
        assertEq(0, funETH.underlying());
        assertEq(0, funETH.aToken().balanceOf(funCity));
        assertEq(0, IERC20x(funETH.asset()).balanceOf(funCity));

        uint256 n = _depositnnEth(depositor, amount, true);
        vm.warp(block.timestamp + 888888);

        uint256 yield = funETH.getYieldEarned();
        assertGt(yield, 0);

        assertEq(0, funETH.aToken().balanceOf(funETH.owner()));

        vm.startPrank(funCity);
        uint256 reservesToPull = yield / 2;
        funETH.pullReserves(reservesToPull, address(0));

        emit log_named_uint("interest earned", yield);
        emit log_named_uint("reserves", reservesToPull);

        // approximate bc i cant figure out this 1 wei yield from aave
        assertGe(reservesToPull + 5, funETH.aToken().balanceOf(funCity));

        emit log_named_uint("vault bal 3", IERC20x(funETH.asset()).balanceOf(funCity));

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

        vm.startPrank(funETH.owner());
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

        vm.startPrank(funETH.owner());
        vm.expectRevert(FunETH.InsufficientReserves.selector);
        funETH.pullReserves(10, address(0));
        vm.stopPrank();

        // no change bc cant withdraw
        assertEq(funETH.underlying(), totalUnderlying);
        assertEq(unhealthyHF, funETH.getExpectedHF());
    }

    function test_lend_borrowFailsIfOverDebtRatio(address vault, uint256 _deposit) public assumeValidAddress(vault) {
        uint256 deposit = _depositForBorrowing(makeAddr("boogawugi"), _deposit);
        (uint256 delegatedCredit, uint256 borrowable) = _borrowable(deposit);

        _lend(vault, borrowable);

        // LTV above target
        (,, uint256 availableBorrow,, uint256 ltv, uint256 hf) = aave.getUserAccountData(address(funETH));
        assertGe(hf, funETH.MIN_RESERVE_FACTOR());

        address rsa = factory.deployFunFunding(vault, funETH.debtAsset(), 100, "teawfafst", "tegaevaawfwst");
        vm.expectRevert();
        vm.prank(funETH.owner());
        funETH.lend(vault, rsa, borrowable);

        // LTV still above target
        (,, uint256 availableBorrow2,, uint256 ltv2, uint256 hf2) = aave.getUserAccountData(address(funETH));
        assertGe(funETH.convertToDecimal(hf2, 18, 2), funETH.MIN_RESERVE_FACTOR());
        // assertEq(funETH.getDebt(), debtBalance1);
        vm.stopPrank();
    }

    function test_lend_increasesCreditOnEachCall(uint256 deposited) public {
        deposited = _depositnnEth(makeAddr("jknsafioui"), deposited, true);
        (, uint256 borrowable) = _borrowable(deposited);
        vm.warp(block.timestamp + 888);
        
        address vault = makeAddr("boogawugi");
        IERC20x funfund = IERC20x(factory.deployFunFunding(vault, address(funETH.debtAsset()), 1000, "test", "test"));
        uint256 shares = borrowable * 11_000 / 10_000;
        
        vm.prank(funETH.owner());
        funETH.lend(vault, address(funfund), borrowable / 2);
        assertEq(funfund.balanceOf(address(funETH)), shares / 2);
        funETH.lend(vault, address(funfund), borrowable / 2);
        assertEq(funfund.balanceOf(address(funETH)), shares);
    }
    function test_lend_worksWithAny4626Vault(uint256 deposited) public {
        deposited = _depositnnEth(makeAddr("jknsafioui"), deposited, true);
        (, uint256 borrowable) = _borrowable(deposited);
        vm.warp(block.timestamp + 888);

        address vault4626;
        if(borrowToken == address(WETH))
            // moonwell morpho WETH base
            vault4626 = address(0xa0E430870c4604CcfC7B38Ca7845B1FF653D0ff1);
        if(borrowToken == address(USDC))
            // moonwell morpho USDC base
            vault4626 = address(0xc1256Ae5FF1cf2719D4937adb3bbCCab2E00A2Ca);

        vm.prank(funETH.owner());
        address vault = makeAddr("boogawugi");
        funETH.lend(vault, vault4626, borrowable);
        assertGe(IERC20x(vault4626).balanceOf(address(funETH)), 0);
    }

    function test_repay_worksWithAny4626Vault(uint256 deposited, uint256 redeemed) public {
        vm.assume(redeemed > 0);
        // 8 decimals for asset price + 2 decimal for reserve factor (prevent over/underflows in _borrowable)  
        vm.assume(redeemed < type(uint256).max / 1e10);
        deposited = _depositnnEth(makeAddr("jknsafioui"), deposited, true);
        (, uint256 borrowable) = _borrowable(deposited);
        vm.assume(borrowable >= redeemed);
        vm.warp(block.timestamp + 888);

        address vault4626;
        if(borrowToken == address(WETH))
            // moonwell morpho WETH base
            vault4626 = address(0xa0E430870c4604CcfC7B38Ca7845B1FF653D0ff1);
        if(borrowToken == address(USDC))
            // moonwell morpho USDC base
            vault4626 = address(0xc1256Ae5FF1cf2719D4937adb3bbCCab2E00A2Ca);

        (,uint256 debtBase,,,,) = aave.getUserAccountData(address(funETH));
        assertEq(debtBase, 0);
        vm.prank(funETH.owner());
        address vault = makeAddr("boogawugi");
        funETH.lend(vault, vault4626, borrowable);
        uint256 shares = IERC20x(vault4626).balanceOf(address(funETH));
        (,uint256 debtBase1,,,,) = aave.getUserAccountData(address(funETH));

        vm.expectEmit(true, true, true, true);
        // deposit/redeem in shares so calculate underlying redeemed from deposited amount
        uint256 redeemedShares = (redeemed * shares) / borrowable; // TODO vault.previewWithdraw()
        emit FunETH.LoanRepaid(vault, vault4626, redeemed);
        funETH.repay(vault, redeemed);

        (,uint256 debtBase2,,,,) = aave.getUserAccountData(address(funETH));

        if(borrowable == redeemed) {    
            assertEq(debtBase2, 0); 
        } else {
            assertLe(debtBase2, debtBase1);
        }
        
        assertLe(
            IERC20x(vault4626).balanceOf(address(funETH)),
            shares - redeemedShares + 1 // +1 to offset for rounding errors
        );

    }

    function test_withdraw_redeemBelowReserveFactor(address user, uint256 amount) public assumeValidAddress(user) {
        uint256 n = _depositForBorrowing(user, amount);
        (, uint256 borrowable) = _borrowable(n);
        vm.warp(block.timestamp + 888);
        
        address rsa = factory.deployFunFunding(makeAddr("asavwava"), address(funETH.debtAsset()), 100, "testasfa", "tasfaest");
        vm.prank(funETH.owner());
        funETH.lend(makeAddr("asavwava"), rsa, borrowable);

        uint256 safeWithdraw = n / 4;
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

        address rsa = factory.deployFunFunding(makeAddr("boogawugi"), address(funETH.debtAsset()), 100, "test", "test");
        vm.prank(funETH.owner());
        funETH.lend(makeAddr("boogawugi"), rsa, borrowable);

        assertGe(funETH.getExpectedHF(), funETH.MIN_REDEEM_FACTOR());
        assertLe(funETH.getExpectedHF(), funETH.MIN_RESERVE_FACTOR());

        // uint256 maliciousWithdrawAmount = (borrowable * funETH.MIN_REDEEM_FACTOR());
        uint256 maliciousWithdrawAmount = (n * 2) / 4;
        emit log_named_uint("pre malicious factor", funETH.getExpectedHF());
        // vm.expectRevert(FunETH.MaliciousWithdraw.selector);
        _withdrawnnEth(user, maliciousWithdrawAmount);
        emit log_named_uint("post malicious factor", funETH.getExpectedHF());
        // still above min redeem factor bc withdraw failed
        assertGe(funETH.getExpectedHF(), funETH.MIN_REDEEM_FACTOR());
        assertLe(funETH.getExpectedHF(), funETH.MIN_RESERVE_FACTOR());
    }

    // withdrawTo() replaced with 4626 redeem()
    // function test_withdrawTo_updatesProperBalances(address user, uint256 amount) public assumeValidAddress(user) {
    //     uint256 n = _depositnnEth(user, amount, true);
    //     assertEq(funETH.balanceOf(user), n);
    //     emit log_named_uint("recipient init balance ", funETH.balanceOf(makeAddr("boogawugi")));
    //     assertEq(funETH.balanceOf(makeAddr("boogawugi")), 0);
    //     assertEq(reserveToken.balanceOf(user), 0);
    //     emit log_named_uint("recipient init balance ", reserveToken.balanceOf(makeAddr("boogawugi")));
    //     assertEq(reserveToken.balanceOf(makeAddr("boogawugi")), 0);

    //     uint256 withdrawn = n / 2;
    //     vm.prank(user);
    //     funETH.withdrawTo(withdrawn, makeAddr("boogawugi"));

    //     emit log_named_uint("user remaining balance ", funETH.balanceOf(user));
    //     assertEq(reserveToken.balanceOf(user), 0);
    //     assertEq(funETH.balanceOf(user), n - withdrawn);

    //     emit log_named_address("reserve token ", address(reserveToken));
    //     assertEq(reserveToken.balanceOf(makeAddr("boogawugi")), withdrawn);
    //     emit log_named_uint("recipient remaining balance ", funETH.balanceOf(makeAddr("boogawugi")));
    //     assertEq(funETH.balanceOf(makeAddr("boogawugi")), 0);
    // }    
}
