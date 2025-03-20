pragma solidity ^0.8.26;

import {ZuETH} from "../src/ZuETH.sol";
import {IERC20x, IAaveMarket, IZuETH, AaveErrors} from "../src/Interfaces.sol";

import {ZuEthBaseTest} from "./ZuEthBaseTest.t.sol";
import {Handler} from "./ZuEthPlaybook.sol";

contract ZuEthAaveIntegration is ZuEthBaseTest {
    Handler public handler;

    function setUp() override public {
        super.setUp();
        handler = new Handler(zuETH, address(reserveToken));

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

    function invariant_totalSupplyEqualsATokenBalance() public {
        assertEq(zuETH.totalSupply(), zuETH.aToken().balanceOf(address(zuETH)));
    }

    // dont think we need this since we have enough assurances from 
    // WETH invariants + LTV tests to ensure user deposits are reasonably safe with credit risk 
    // and loan can always repay itself
    // function invariant_maxSelfRepayPeriodUnder5Years() public {
    //    someinth * interest rate * (100 / MIN_LTV_THREASHOLD = 1/6) <= 365 days * 5
    // }

    function invariant_deposit_increaseAToken() public {
        assertEq(handler.netDeposits(), zuETH.underlying());

        uint256 n = _depositZuEth(address(0xdead), 100, true);

        assertGe(zuETH.underlying(), handler.netDeposits() + n);
    }

    function invariant_deposit_aTokenEarnsYield() public {
        _depositZuEth(address(0xdead), 500 ether, true);
        uint256 aTokenBalance = zuETH.underlying();

        vm.warp(block.timestamp + 1 days);
        
        // need to interact with pool to update index on account and reflect in next scaledBalance
        // could do manual math to calculate or just add new 1 wei deposit to previous deposit amount
        _depositZuEth(address(0xdead), 1, true);


        // increases with time without any action from us
        assertGt(zuETH.underlying(), aTokenBalance + 1);
    }

    function test_lend_canDelegateCredit(address city, uint256 amount) public {
        vm.assume(city != address(0)); // prevent aave error sending to 0x0
        uint256 n = _depositZuEth(address(0xdead), amount, true);

        // todo expect call to zuETH.debtToken
        // bytes memory data = abi.encodeWithSelector(IERC20x.approveDelegation.selector, city, n); 
        // vm.expectCall(address(zuETH.debtToken()), data, 1);

        uint256 credit0 = debtToken.borrowAllowance(address(zuETH), city);
        assertEq(credit0, 0);
        assertEq(zuETH.getCityCredit(city), 0);

        address treasury = zuETH.ZU_CITY_TREASURY();
        (uint256 totalCredit, uint256 borrowable) = _borrowable(zuETH.totalSupply());

        vm.prank(treasury);
        vm.expectEmit(true, true, true, true);
        emit ZuETH.Lend(address(treasury), address(debtToken), city, borrowable);
        zuETH.lend(city, borrowable);
        
        uint256 credit = debtToken.borrowAllowance(address(zuETH), city);
        assertGt(credit, 0);
        assertEq(credit, borrowable);
        assertEq(zuETH.getCityCredit(city), credit); // ensure parity btw zueth and aave
    }
    
    function test_lend_canBorrowAgainst(address user, address city, uint256 amount) public {
        uint256 n = _depositZuEth(user, amount, true);
        (uint256 totalCredit, uint256 borrowable) = _borrowable(n);


        (,,uint256 availableBorrow,,,uint256 hf) = aave.getUserAccountData(address(zuETH));
        assertGe(borrowable + 1, availableBorrow / zuETH.MIN_RESERVE_FACTOR()); // TODO figure out rounding errors
        assertEq(zuETH.getAvailableCredit(), availableBorrow); // ensure smart contract has right impl too
        assertGt(hf, zuETH.MIN_RESERVE_FACTOR()); // condition cleared to borrow even without delegation

        _lend(city, borrowable);
    
        // check borrow actually works even if aave says we have credit
        // failing on borrow
        // Tried:
        // - no emode set = ERROR #36 - COLLATERAL_CANNOT_COVER_NEW_BORROW
        // - setting emode to 0 = ERROR #36 - COLLATERAL_CANNOT_COVER_NEW_BORROW
        // - setting emode to 1 = ERROR #100 - ASSET_NOT_BORROWABLE_IN_EMODE

        // aave.setUserEMode(aaveEMode);
        (,,uint256 availableToBorrow,,,) = aave.getUserAccountData(address(zuETH));
        emit log_named_uint("current borrow credit", availableToBorrow);
        uint256 credit = debtToken.borrowAllowance(address(zuETH), city);
        emit log_named_uint("current delegated credit", credit);

        vm.startPrank(city);
        aave.borrow(address(USDC), 1, 2, 0, address(zuETH));
        vm.stopPrank();
    }

    function test_getAvailableCredit_matchesAaveUserSummary() public {
        uint256 ltvConfig = 80; // TODO pull from Aave.reserveConfig or userAcccountData
        uint256 _deposit = 60 ether;
        uint256 deposit = _depositZuEth(address(0xdead), _deposit, true);


        (uint256 totalCredit, ) = _borrowable(deposit);
        assertEq(totalCredit, zuETH.getAvailableCredit());
    }

}