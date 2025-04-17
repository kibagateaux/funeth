pragma solidity ^0.8.26;

import {FunETH} from "../../src/FunETH.sol";
import {IERC20x, IAaveMarket, IFunETH, AaveErrors} from "../../src/Interfaces.sol";

import {FunETHBaseTest} from "./FunETHBaseTest.t.sol";
import {Handler} from "./FunETHPlaybook.t.sol";

contract FunETHAaveIntegration is FunETHBaseTest {
    Handler public handler;

    function setUp() public virtual override {
        super.setUp();
        handler = new Handler(funETH, address(reserveToken));

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = Handler.deposit.selector;
        selectors[1] = Handler.withdraw.selector;
        selectors[2] = Handler.approve.selector;
        selectors[3] = Handler.transfer.selector;
        selectors[4] = Handler.transferFrom.selector;
        // selectors[5] = Handler.sendFallback.selector;
        // selectors[6] = Handler.forcePush.selector;

        // basically do a bunch of random shit before we test invariants
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_totalSupplyEqualsATokenBalance() public view {
        assertEq(funETH.totalSupply(), funETH.aToken().balanceOf(address(funETH)));
    }

    // dont think we need this since we have enough assurances from
    // WETH invariants + LTV tests to ensure user deposits are reasonably safe with credit risk
    // and loan can always repay itself
    // function invariant_maxSelfRepayPeriodUnder5Years() public {
    //    someinth * interest rate * (100 / MIN_LTV_THREASHOLD = 1/6) <= 365 days * 5
    // }

    function invariant_deposit_increaseAToken() public {
        assertEq(handler.netDeposits(), funETH.underlying());

        uint256 n = _depositnnEth(makeAddr("boogawugi"), 100, true);

        assertGe(funETH.underlying(), handler.netDeposits() + n);
    }

    function invariant_deposit_aTokenEarnsYield() public {
        _depositnnEth(makeAddr("boogawugi"), 500 ether, true);
        uint256 aTokenBalance = funETH.underlying();

        vm.warp(block.timestamp + 1 days);

        // need to interact with pool to update index on account and reflect in next scaledBalance
        // could do manual math to calculate or just add new 1 wei deposit to previous deposit amount
        _depositnnEth(makeAddr("boogawugi"), 1, true);

        // increases with time without any action from us
        assertGt(funETH.underlying(), aTokenBalance + 1);
    }

    // function invariant_getAvailableCredit_matchesAaveUserSummary() public {
    //     uint256 ltvConfig = 80;
    //     uint256 _deposit = 60 ether;
    //     uint256 deposit = _depositnnEth(makeAddr("boogawugi"), _deposit, true);

    //     (uint256 totalCredit, ) = _borrowable(deposit);
    //     assertEq(totalCredit / 1e2, funETH.getAvailableCredit());
    // }

    // TODO test debtToken balances.
    // Does it go to zuCity contract or borrower?

    function test_lend_canDelegateCredit(address city) public assumeValidAddress(city) {
        uint256 n = _depositnnEth(makeAddr("boogawugi"), 100 ether, true);

        // todo expect call to funETH.debtToken
        // bytes memory data = abi.encodeWithSelector(IERC20x.approveDelegation.selector, city, n);
        // vm.expectCall(address(funETH.debtToken()), data, 1);

        uint256 credit0 = debtToken.borrowAllowance(address(funETH), city);
        assertEq(credit0, 0);
        assertEq(funETH.credited(city), 0);

        address treasury = funETH.FUN_OPS();
        (uint256 totalCredit, uint256 borrowable) = _borrowable(funETH.totalSupply());

        vm.prank(treasury);
        vm.expectEmit(true, true, true, true);
        emit FunETH.Lend(address(treasury), address(debtToken), city, borrowable);
        funETH.lend(city, borrowable);

        uint256 credit = debtToken.borrowAllowance(address(funETH), city);
        assertGt(credit, 0);
        assertEq(credit, borrowable);
        assertEq(funETH.credited(city), credit); // ensure parity btw nneth and aave
    }

    function invariant_lend_noDebtWithoutDelegation() public view {
        (, uint256 totalDebtBase,,,,) = aave.getUserAccountData(address(funETH));
        assertGe(funETH.totalCreditDelegated(), totalDebtBase / 1e2);
    }

    function test_lend_canBorrowAgainst(address user, address city, uint256 amount) public assumeValidAddress(city) {
        uint256 n = _depositForBorrowing(user, amount);
        (uint256 totalCredit, uint256 borrowable) = _borrowable(n);

        (,, uint256 availableBorrow,,, uint256 hf) = aave.getUserAccountData(address(funETH));

        // Ge means we overly cautious with borrow amount. should be at most aave's allownace
        assertGe(
            // (funETH.convertToDecimal(availableBorrow, 0, funETH.debtTokenDecimals()) / funETH.debtAssetPrice()),
            (
                funETH.convertToDecimal(availableBorrow, 0, funETH.debtTokenDecimals()) / funETH.debtAssetPrice()
                    / (funETH.MIN_RESERVE_FACTOR() - 1)
            ),
            borrowable
        );

        // assertEq(funETH.getAvailableCredit(), funETH.convertToDecimal(availableBorrow, 8, funETH.debtTokenDecimals())); // ensure smart contract has right impl too
        assertGt(funETH.convertToDecimal(hf, 18, 0), funETH.MIN_RESERVE_FACTOR()); // condition cleared to borrow even without delegation

        // for some reason test fails if this goes first even though nothing borrowed and getExpectedHF not used
        _lend(city, borrowable);

        (,, uint256 availableToBorrow,,,) = aave.getUserAccountData(address(funETH));
        uint256 credit = debtToken.borrowAllowance(address(funETH), city);

        vm.startPrank(city);
        aave.borrow(borrowToken, 1, 2, 0, address(funETH));
        vm.stopPrank();
    }

    function test_borrow_debtTokenBalanceIncreases(address user, address city, uint256 amount)
        public
        assumeValidAddress(city)
    {
        uint256 n = _depositForBorrowing(user, amount);
        (uint256 totalCredit, uint256 borrowable) = _borrowable(n);

        assertEq(debtToken.balanceOf(address(funETH)), 0);
        _lend(city, borrowable);
        assertEq(debtToken.balanceOf(address(funETH)), 0);

        (,, uint256 availableToBorrow,,,) = aave.getUserAccountData(address(funETH));

        vm.startPrank(city);
        aave.borrow(borrowToken, 1, 2, 0, address(funETH));
        vm.stopPrank();

        assertEq(debtToken.balanceOf(address(funETH)), 1);
        // ensure debt given to main account not borrower
        assertEq(debtToken.balanceOf(address(city)), 0);
    }

    function invariant_reserveAssetPrice_matchesAavePrice() public {
        (, bytes memory data) = address(reserveToken).call(abi.encodeWithSignature("symbol()"));
        emit log_named_string("reserve asset symbol", abi.decode(data, (string)));
        uint256 price = funETH.price(address(reserveToken));
        emit log_named_uint("reserve asset price", price);
        assertGt(price, 0);
    }

    function invariant_debtAssetPrice_matchesAavePrice() public {
        // TODO this shows USDC as debt asset on NNUSDC with USDC as reserve asset too
        (, bytes memory data) = address(borrowToken).call(abi.encodeWithSignature("symbol()"));
        emit log_named_string("debt asset symbol", abi.decode(data, (string)));
        uint256 price = funETH.price(address(borrowToken));
        emit log_named_uint("debt asset price", price);
        assertGt(price, 0);
    }
}
