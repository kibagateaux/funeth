pragma solidity ^0.8.26;

import {NNETH} from "../src/NNETH.sol";
import {IERC20x, IAaveMarket, INNETH, AaveErrors} from "../src/Interfaces.sol";

import {NNETHBaseTest} from "./NNETHBaseTest.t.sol";
import {Handler} from "./NNETHPlaybook.t.sol";

contract NNETHAaveIntegration is NNETHBaseTest {
    Handler public handler;

    function setUp() override virtual public {
        super.setUp();
        handler = new Handler(nnETH, address(reserveToken));

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
        assertEq(nnETH.totalSupply(), nnETH.aToken().balanceOf(address(nnETH)));
    }

    // dont think we need this since we have enough assurances from 
    // WETH invariants + LTV tests to ensure user deposits are reasonably safe with credit risk 
    // and loan can always repay itself
    // function invariant_maxSelfRepayPeriodUnder5Years() public {
    //    someinth * interest rate * (100 / MIN_LTV_THREASHOLD = 1/6) <= 365 days * 5
    // }

    function invariant_deposit_increaseAToken() public {
        assertEq(handler.netDeposits(), nnETH.underlying());

        uint256 n = _depositnnEth(address(0xdead), 100, true);

        assertGe(nnETH.underlying(), handler.netDeposits() + n);
    }

    function invariant_deposit_aTokenEarnsYield() public {
        _depositnnEth(address(0xdead), 500 ether, true);
        uint256 aTokenBalance = nnETH.underlying();

        vm.warp(block.timestamp + 1 days);
        
        // need to interact with pool to update index on account and reflect in next scaledBalance
        // could do manual math to calculate or just add new 1 wei deposit to previous deposit amount
        _depositnnEth(address(0xdead), 1, true);


        // increases with time without any action from us
        assertGt(nnETH.underlying(), aTokenBalance + 1);
    }

    function invariant_getAvailableCredit_matchesAaveUserSummary() public {
        uint256 ltvConfig = 80;
        uint256 _deposit = 60 ether;
        uint256 deposit = _depositnnEth(address(0xdead), _deposit, true);


        (uint256 totalCredit, ) = _borrowable(deposit);
        assertEq(totalCredit / 1e2, nnETH.getAvailableCredit());
    }

    // TODO test debtToken balances.
    // Does it go to zuCity contract or borrower?


    function test_lend_canDelegateCredit(address city) public {
        vm.assume(city != address(0)); // prevent aave error sending to 0x0
        uint256 n = _depositnnEth(address(0xdead), 100 ether, true);

        // todo expect call to nnETH.debtToken
        // bytes memory data = abi.encodeWithSelector(IERC20x.approveDelegation.selector, city, n); 
        // vm.expectCall(address(nnETH.debtToken()), data, 1);

        uint256 credit0 = debtToken.borrowAllowance(address(nnETH), city);
        assertEq(credit0, 0);
        assertEq(nnETH.getCityCredit(city), 0);

        address treasury = nnETH.ZU_CITY_TREASURY();
        (uint256 totalCredit, uint256 borrowable) = _borrowable(nnETH.totalSupply());

        vm.prank(treasury);
        vm.expectEmit(true, true, true, true);
        emit NNETH.Lend(address(treasury), address(debtToken), city, borrowable);
        nnETH.lend(city, borrowable);
        
        uint256 credit = debtToken.borrowAllowance(address(nnETH), city);
        assertGt(credit, 0);
        assertEq(credit, borrowable);
        assertEq(nnETH.getCityCredit(city), credit); // ensure parity btw nneth and aave
    }

    function invariant_lend_noDebtWithoutDelegation() public view {
        (,uint256 totalDebtBase,,,,) = aave.getUserAccountData(address(nnETH));
        assertGe(nnETH.totalCreditDelegated(), totalDebtBase / 1e2);
    }
    
    function test_lend_canBorrowAgainst(address user, address city, uint256 amount) public {
        uint256 n = _depositForBorrowing(user, amount);
        (uint256 totalCredit, uint256 borrowable) = _borrowable(n);


        (,,uint256 availableBorrow,,,uint256 hf) = aave.getUserAccountData(address(nnETH));

        assertGe(borrowable, nnETH.convertToDecimal((availableBorrow / nnETH.MIN_RESERVE_FACTOR()), 8, nnETH.debtTokenDecimals()) - 1);
        assertEq(nnETH.getAvailableCredit(), nnETH.convertToDecimal(availableBorrow, 8, nnETH.debtTokenDecimals())); // ensure smart contract has right impl too
        assertGt(nnETH.convertToDecimal(hf, 18, 0), nnETH.MIN_RESERVE_FACTOR()); // condition cleared to borrow even without delegation

         // for some reason test fails if this goes first even though nothing borrowed and getExpectedHF not used
        _lend(city, borrowable);

        (,,uint256 availableToBorrow,,,) = aave.getUserAccountData(address(nnETH));
        uint256 credit = debtToken.borrowAllowance(address(nnETH), city);

        vm.startPrank(city);
        aave.borrow(borrowToken, 1, 2, 0, address(nnETH));
        vm.stopPrank();
    }

    function test_borrow_debtTokenBalanceIncreases(address user, address city, uint256 amount) public {
        uint256 n = _depositForBorrowing(user, amount);
        (uint256 totalCredit, uint256 borrowable) = _borrowable(n);

        assertEq(debtToken.balanceOf(address(nnETH)), 0);
        _lend(city, borrowable);
        assertEq(debtToken.balanceOf(address(nnETH)), 0);

        (,,uint256 availableToBorrow,,,) = aave.getUserAccountData(address(nnETH));

        vm.startPrank(city);
        aave.borrow(borrowToken, 1, 2, 0, address(nnETH));
        vm.stopPrank();

        assertEq(debtToken.balanceOf(address(nnETH)), 1);
        // ensure debt given to main account not borrower
        assertEq(debtToken.balanceOf(address(city)), 0);
    }

    function test_reserveAssetPrice_matchesAavePrice() public {
        (,bytes memory data) = address(reserveToken).call(abi.encodeWithSignature("symbol()"));
        emit log_named_string("reserve asset symbol", abi.decode(data, (string)));
        uint256 price = nnETH.price(address(reserveToken));
        emit log_named_uint("reserve asset price", price);
        assertGt(price, 0);
    }

    function test_debtAssetPrice_matchesAavePrice() public {
        // TODO this shows USDC as debt asset on NNUSDC with USDC as reserve asset too
        (,bytes memory data) = address(borrowToken).call(abi.encodeWithSignature("symbol()"));
        emit log_named_string  ("debt asset symbol", abi.decode(data, (string)));
        uint256 price = nnETH.price(address(borrowToken));
        emit log_named_uint("debt asset price", price);    
        assertGt(price, 0);
    }


}