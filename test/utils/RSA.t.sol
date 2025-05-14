pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {MockToken} from "../helpers/MockToken.sol";
import {FunFactory} from "../../src/utils/FunFactory.sol";
import {FunFunding} from "../../src/utils/FunFunding.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {MockFeeGenerator} from "../helpers/MockFeeGenerator.sol";

import {GPv2Order} from "../../src/lib/GPv2.sol";
import {IERC20x, IFunFunding} from "../../src/Interfaces.sol";

// TODO add general 4626 test
// https://github.com/a16z/erc4626-tests

// deposit
// mints more tokens than deposited at reward rate

// redeem
// if INIT or CANCELED returns at original amount
// if ACTIVE returns at reward rate

// initiateTerm
// initaiteTermBelowAsk
// updates totalOwed properly
// rewardRate is unchanged
// fee is based on new totalOwed not original
// only callable by borrower
// status must be INIT
// if balance == totalOwed then equivalent to initiateTerm

// invariants
//  totalOwed == totalSupply

// TODO totalOwed() will be bigger than i expect bc fees, can just do Qe bc we have math for the exact conversion

contract FunFundingTest is Test {
    using GPv2Order for GPv2Order.Data;

    address private constant ETH = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    IERC20x public constant WETH = IERC20x(0x4200000000000000000000000000000000000006);
    IERC20x public constant USDC = IERC20x(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    uint256 public constant BPS_COEFFICIENT = 10_000;

    // spigot contracts/configurations to test against
    IERC20x private feeToken;
    IERC20x private creditToken;

    // Named vars for common inputs
    uint256 constant MAX_UINT = type(uint256).max;
    uint256 constant MAX_REVENUE = type(uint256).max / 100;
    uint256 constant MAX_TRADE_DEADLINE = 1 days;

    bytes4 internal constant ERC_1271_MAGIC_VALUE = 0x1626ba7e;
    bytes4 internal constant ERC_1271_NON_MAGIC_VALUE = 0xffffffff;
    /// @dev The settlement contract's EIP-712 domain separator. Milkman uses this to verify that a provided UID matches provided order parameters.
    bytes32 internal constant COWSWAP_DOMAIN_SEPARATOR =
        0xc078f884a2676e1345748b1feace7b0abee5d00ecadb6e574dcdd109a63e8943;

    // RSA + Spigot stakeholder
    FunFactory factory;
    FunFunding private rsa;
    uint16 private apr;
    address public funNetwork;
    address private borrower;
    address private depositor;
    address private rando; // random address for ACL testing

    uint256 private baseFork;

    function setUp() public {
        baseFork = vm.createSelectFork(vm.rpcUrl("base"), 23_502_225);

        funNetwork = makeAddr("2");
        borrower = makeAddr("3");
        depositor = makeAddr("4");
        rando = makeAddr("69");
        factory = new FunFactory(
            address(0), // TODO aave market
            address(0) // TODO weth
        );
        factory.transferOwnership(funNetwork);

        feeToken = WETH;
        creditToken = USDC;

        apr = 500; // 5%
        rsa = _initRSA(address(creditToken), apr);
    }

    /**
     *
     *
     * FunFactory/Proxy & Initialization Tests
     *
     * Unit Tests
     *
     *
     *
     */
    function test_initialize_setsValuesProperly() public {
        // set in _initRSA
        assertEq("Revenue Share: RSA Revenue Stream Token", rsa.name());
        assertEq("RSA-rsaCLAIM", rsa.symbol());
        // stakeholder addresses
        assertEq(borrower, rsa.owner());
        assertEq(funNetwork, rsa.networkFeeRecipient());

        // deal terms
        assertEq(address(creditToken), address(rsa.asset()));
        assertEq(uint8(rsa.status()), uint8(FunFunding.STATUS.INIT));
        assertEq(rsa.rewardRate(), apr + 10_000);
        // TODO accurate until fees added. make more explicit?
        assertEq(0, rsa.totalOwed());
        assertEq(0, rsa.totalSupply());
    }

    function test_initialize_mustBorrowNonNullAddress() public {
        vm.expectRevert(FunFunding.InvalidBorrowerAddress.selector);
        factory.deployFunFunding(address(0), address(creditToken), 52, "RSA Revenue Stream Token0", "rsaCLAIM0");
    }

    function test_initialize_cantInitializeTwice() public {
        vm.prank(borrower);
        vm.expectRevert(Ownable.AlreadyInitialized.selector);
        rsa.initialize(borrower, address(WETH), address(creditToken), 37, "RSA Revenue Stream Token 2", "rsaCLAIM2");

        vm.prank(depositor);
        vm.expectRevert(Ownable.AlreadyInitialized.selector);
        rsa.initialize(borrower, address(WETH), address(creditToken), 37, "RSA Revenue Stream Token3", "rsaCLAIM3");

        vm.prank(rando);
        vm.expectRevert(Ownable.AlreadyInitialized.selector);
        rsa.initialize(borrower, address(WETH), address(creditToken), 37, "RSA Revenue Stream Token4", "rsaCLAIM4");
    }

    function test_initialize_canSetAPRTo0() public {
        _initRSA(address(creditToken), 0);
    }

    // TODO any tets for Proxy that we need to check e.g. same byte code for all deployed contracts?]

    /**
     *
     *
     *
     * RSA System Invariants
     *
     * Unit Tests
     *
     *
     *
     */

    /// @dev TODO: pretty sure this isnt running as i expect even though it passes
    function invariant_totalSupply_equalsTotalOwedMinusTotalClaimable() public {
        if (rsa.totalSupply() != 0) {
            assertEq(rsa.totalSupply(), rsa.totalOwed() - rsa.claimableAmount());
        } else {
            // totalSupply == 0 until deposit() called
            assertGe(rsa.claimableAmount(), rsa.totalSupply());
            assertGe(rsa.totalOwed(), rsa.totalSupply());
        }
    }

    function invariant_deposit_reverIfNotInitStatus() public {
        if (uint8(rsa.status()) != uint8(FunFunding.STATUS.INIT)) {
            vm.expectRevert(FunFunding.InvalidStatus.selector);
        }
        _depositRSA(rando, rsa, 100);
    }

    function invariant_redeem_anyStatus() public {
        vm.assume(uint8(rsa.status()) == uint8(FunFunding.STATUS.INIT));

        _depositRSA(rando, rsa, 100);
        rsa.redeem(100, rando, rando);

        _depositRSA(rando, rsa, 100);
        _initRSA(rsa);
        _generateRevenue(creditToken, 100);
        // rsa.repay();
        rsa.redeem(100, rando, rando);
    }

    /**
     *
     *
     *
     * RSA deposit() and redeem()
     *
     * Unit Tests
     *
     *
     *
     */

    /// @notice manually recreate _depositRSA helper to test each step
    function test_deposit_depositorMustSendInitialPrincipal(uint256 amount) public {
        amount = bound(amount, 100, MAX_UINT / rsa.rewardRate());
        deal(address(creditToken), depositor, amount);

        uint256 depositorBalance0 = creditToken.balanceOf(depositor);
        uint256 rsaBalance0 = creditToken.balanceOf(address(rsa));

        vm.prank(depositor);
        creditToken.approve(address(rsa), amount);
        vm.prank(depositor);
        uint256 shares = rsa.deposit(amount, depositor);

        uint256 depositorBalance1 = creditToken.balanceOf(depositor);
        uint256 rsaBalance1 = creditToken.balanceOf(address(rsa));

        // ensure proper amount moved to borrower
        assertEq(depositorBalance1, depositorBalance0 - amount);

        // RSA should hold sent tokens
        assertEq(rsaBalance1, rsaBalance0 + amount, "bad post deposit() rsa balance");
    }

    function test_deposit_increasesTotalSupplyByTotalClaims(uint256 amount) public {
        amount = bound(amount, 100, MAX_UINT / rsa.rewardRate());
        uint256 rsaSupply0 = rsa.totalSupply();
        assertEq(rsaSupply0, 0);

        _depositRSA(depositor, rsa, amount);

        uint256 rsaSupply1 = rsa.totalSupply();
        assertEq(rsaSupply1, amount * rsa.rewardRate() / 10_000);
    }

    function test_deposit_updatesDepositorBalance(uint256 amount) public {
        amount = bound(amount, 100, MAX_UINT / rsa.rewardRate() / 3);
        deal(address(creditToken), depositor, amount);
        deal(address(creditToken), rando, amount);

        uint256 minDeposit = amount / 2;
        uint256 baseShares = (minDeposit * rsa.rewardRate()) / BPS_COEFFICIENT;

        vm.startPrank(depositor);
        creditToken.approve(address(rsa), minDeposit);
        rsa.deposit(minDeposit, depositor);
        vm.stopPrank();

        assertEq(rsa.balanceOf(depositor), baseShares);

        vm.startPrank(rando);
        creditToken.approve(address(rsa), minDeposit);
        rsa.deposit(minDeposit, rando);
        vm.stopPrank();

        assertEq(rsa.balanceOf(rando), baseShares);

        vm.startPrank(rando);
        creditToken.approve(address(rsa), minDeposit);
        rsa.deposit(minDeposit, depositor);
        vm.stopPrank();

        assertEq(rsa.balanceOf(rando), baseShares);
        assertEq(rsa.balanceOf(depositor), baseShares * 2);
    }

    // TODO more initiateTerm() and cancelTerm() tests
    function test_initiateTerm_borrowerGetsInitialPrincipalOnDeposit(uint256 _amount) public {
        _amount = bound(_amount, 100, MAX_UINT / rsa.rewardRate());
        uint256 balance1 = creditToken.balanceOf(borrower);
        _depositRSA(depositor, rsa, _amount);
        _initRSA(rsa);
        uint256 balance2 = creditToken.balanceOf(borrower);
        assertEq(balance2 - balance1, _amount);
    }

    function test_initiateTerm_increasesTotalSupplyAndOwedByNetworkFees(uint256 _amount) public {
        _amount = bound(_amount, 100, MAX_UINT / rsa.rewardRate());

        uint256 shares = _depositRSA(depositor, rsa, _amount);
        _initRSA(rsa);

        uint16 feeRate = rsa.NETWORK_FEE_BPS();
        uint256 feeAssets;
        if (feeRate == 0) {
            assertEq(0, rsa.balanceOf(funNetwork));
        } else {
            feeAssets = (_amount * rsa.NETWORK_FEE_BPS()) / 10_000;
            assertEq(rsa.totalSupply(), shares + feeAssets);
        }

        assertEq(rsa.totalSupply(), shares + feeAssets);
        assertEq(rsa.totalOwed(), shares + feeAssets);
    }

    function test_initiateTerm_mintsNetworkFeeToRecipient(uint256 _amount) public {
        _amount = bound(_amount, 100, MAX_UINT / rsa.rewardRate());
        uint256 shares = _depositRSA(depositor, rsa, _amount);
        _initRSA(rsa);
        assertEq(rsa.balanceOf(funNetwork), (shares * rsa.NETWORK_FEE_BPS()) / 10_000);
    }

    function test_redeem_mustRedeemLessThanClaimableRevenue(uint256 _revenue, uint256 _redeemed) public {
        uint256 revenue = bound(_revenue, 100, MAX_UINT / rsa.rewardRate());
        uint256 redeemed = bound(_redeemed, 100, MAX_UINT / rsa.rewardRate());

        _depositRSA(depositor, rsa, redeemed);
        _initRSA(rsa);
        _generateRevenue(creditToken, revenue);

        vm.prank(depositor);
        if (redeemed > revenue) {
            vm.expectRevert(abi.encodeWithSelector(FunFunding.ExceedClaimableTokens.selector, revenue));
        }
        rsa.redeem(redeemed, depositor, depositor);
        vm.stopPrank();
    }

    function test_redeem_reducesClaimsTotalSupply(uint256 _redeemed) public {
        uint256 redeemed = bound(_redeemed, 100, MAX_UINT / rsa.rewardRate());
        assertEq(rsa.totalSupply(), 0);

        uint256 shares = _depositRSA(depositor, rsa, redeemed);
        _initRSA(rsa);
        assertGe(rsa.totalSupply(), redeemed);
        // checkpoint depositor underlying balance after depositing to assert redeemed amount
        uint256 depositorBalance0 = creditToken.balanceOf(depositor);

        _generateRevenue(creditToken, redeemed);

        vm.prank(depositor);
        rsa.redeem(redeemed, depositor, depositor);
        vm.stopPrank();

        assertGe(rsa.totalSupply(), shares - redeemed);
        uint256 depositorBalance1 = creditToken.balanceOf(depositor);
        assertEq(depositorBalance1, depositorBalance0 + redeemed);
    }

    function test_redeem_reducesClaimsAvailable(uint256 _redeemed) public {
        uint256 redeemed = bound(_redeemed, 100, MAX_UINT / rsa.rewardRate());
        assertEq(rsa.totalSupply(), 0);

        uint256 shares = _depositRSA(depositor, rsa, redeemed);
        _initRSA(rsa);
        assertGe(rsa.totalSupply(), shares);
        // checkpoint depositor underlying balance after depositing to assert redeemed amount
        uint256 claimable0 = rsa.claimableAmount();
        assertEq(claimable0, 0); // no rev claimed to rsa yet

        _generateRevenue(creditToken, redeemed);

        uint256 claimable1 = rsa.claimableAmount();
        assertEq(claimable1, redeemed); // all rev generated is claimable

        vm.prank(depositor);
        rsa.redeem(redeemed, depositor, depositor);
        vm.stopPrank();

        uint256 claimable2 = rsa.claimableAmount();
        assertEq(claimable2, claimable1 - redeemed);
    }

    function test_redeem_reducesClaimsAsDepositor(uint256 _redeemed) public {
        uint256 redeemed = bound(_redeemed, 100, MAX_UINT / rsa.rewardRate());
        assertEq(rsa.totalSupply(), 0);

        _depositRSA(depositor, rsa, redeemed);
        _initRSA(rsa);
        assertEq(rsa.totalSupply(), redeemed * rsa.rewardRate() / 10_000);
        // checkpoint depositor underlying balance after depositing to assert redeemed amount
        uint256 depositorClaims0 = rsa.balanceOf(depositor);
        assertEq(depositorClaims0, redeemed * rsa.rewardRate() / 10_000);

        _generateRevenue(creditToken, redeemed);

        vm.prank(depositor);
        rsa.redeem(redeemed, depositor, depositor);
        vm.stopPrank();

        uint256 depositorClaims1 = rsa.balanceOf(depositor);
        assertEq(depositorClaims1, depositorClaims0 - redeemed);
    }

    function test_redeem_reducesClaimsAsNonDepositor(uint256 _redeemed) public {
        uint256 redeemed = bound(_redeemed, 100, MAX_UINT / rsa.rewardRate());
        assertEq(rsa.totalSupply(), 0);

        _depositRSA(depositor, rsa, redeemed);
        _initRSA(rsa);
        assertEq(rsa.totalSupply(), redeemed * rsa.rewardRate() / 10_000);
        // checkpoint depositor underlying balance after depositing to assert redeemed amount
        uint256 depositorClaims0 = rsa.balanceOf(depositor);
        assertEq(depositorClaims0, redeemed * rsa.rewardRate() / 10_000);

        _generateRevenue(creditToken, redeemed);

        // transfer RSA claims to someone else and let them redeem
        vm.prank(depositor);
        rsa.transfer(rando, redeemed);
        vm.stopPrank();

        uint256 depositorClaims1 = rsa.balanceOf(depositor);
        assertEq(depositorClaims1, depositorClaims0 - redeemed);

        uint256 randoClaims0 = rsa.balanceOf(rando);
        uint256 randoBalance0 = creditToken.balanceOf(rando);
        assertEq(randoClaims0, redeemed);

        vm.prank(rando);
        rsa.redeem(redeemed, rando, rando);
        vm.stopPrank();

        uint256 randoClaims1 = rsa.balanceOf(rando);
        assertEq(randoClaims1, randoClaims0 - redeemed);
        uint256 randoBalance1 = creditToken.balanceOf(rando);
        assertEq(randoBalance1, randoBalance0 + redeemed);
    }

    function test_redeem_mustApproveReferrer(uint256 _redeemed) public {
        uint256 redeemed = bound(_redeemed, 100, MAX_UINT / rsa.rewardRate());
        assertEq(rsa.totalSupply(), 0);

        _depositRSA(depositor, rsa, redeemed);
        _initRSA(rsa);
        assertEq(rsa.totalSupply(), redeemed * rsa.rewardRate() / 10_000);
        // checkpoint depositor underlying balance after depositing to assert redeemed amount
        uint256 depositorClaims0 = rsa.balanceOf(depositor);
        assertEq(depositorClaims0, redeemed * rsa.rewardRate() / 10_000);

        _generateRevenue(creditToken, redeemed);

        uint256 randoAllowance0 = rsa.allowance(depositor, rando);
        assertEq(randoAllowance0, 0);

        vm.prank(rando);
        vm.expectRevert();
        rsa.redeem(redeemed, depositor, depositor);
        vm.stopPrank();

        // transfer RSA claims to someone else and let them redeem
        vm.prank(depositor);
        rsa.approve(rando, redeemed);
        vm.stopPrank();

        uint256 randoAllowance1 = rsa.allowance(depositor, rando);
        assertEq(randoAllowance1, randoAllowance0 + redeemed);

        vm.prank(rando);
        rsa.redeem(redeemed, depositor, depositor);
        vm.stopPrank();

        uint256 randoAllowance2 = rsa.allowance(depositor, rando);
        assertEq(randoAllowance2, randoAllowance1 - redeemed);
    }

    function test_redeem_reducesApprovalAsReferrer(uint256 _redeemed) public {
        uint256 redeemed = bound(_redeemed, 100, MAX_UINT / rsa.rewardRate());
        assertEq(rsa.totalSupply(), 0);

        uint256 shares = _depositRSA(depositor, rsa, redeemed);
        _initRSA(rsa);

        assertEq(rsa.totalSupply(), shares);
        // checkpoint depositor underlying balance after depositing to assert redeemed amount
        uint256 depositorClaims0 = rsa.balanceOf(depositor);
        assertEq(depositorClaims0, shares);

        _generateRevenue(creditToken, shares);

        // transfer RSA claims to someone else and let them redeem
        vm.prank(depositor);
        rsa.approve(rando, shares);
        vm.stopPrank();

        uint256 randoAllowance0 = rsa.allowance(depositor, rando);

        vm.prank(rando);
        rsa.redeem(shares, depositor, depositor);
        vm.stopPrank();

        uint256 randoAllowance1 = rsa.allowance(depositor, rando);
        assertEq(randoAllowance1, randoAllowance0 - shares);
    }

    /**
     * @notice - allowing functionality bc could be used as a new crowdfunding method
     * with principal = 0, can bootstrap your own token as claims on future revenue instead of equity
     * so you deposit() yourself and get RSA tokens and sell those to investors for capital
     * probably at a deep discount e.g 1/5th of the value of the underlying revenue
     */
    function test_deposit_with0APR() public {
        FunFunding _rsa = FunFunding(_initRSA(address(creditToken), uint16(0)));
        uint256 amount = 0.1 ether;
        uint256 shares = _depositRSA(depositor, _rsa, amount);

        assertEq(shares, amount); // no increase in tokens
        assertEq(_rsa.rewardRate(), 10_000); // no apr
    }

    function test_repay_revertsBeforeInitiateTerm() public {
        _depositRSA(depositor, rsa, 0.1 ether);
        vm.expectRevert(FunFunding.InvalidStatus.selector);
        rsa.repay();
        
        // fails if has tokens bc no debt yet
        deal(address(creditToken), address(rsa), rsa.totalOwed());
        vm.expectRevert(FunFunding.InvalidStatus.selector);
        rsa.repay();

        _initRSA(rsa);
        
        rsa.repay();
    }

    function test_repay_acceptsDirectCreditTokenPayments() public {
        _depositRSA(depositor, rsa, 0.1 ether);
        _initRSA(rsa);
        deal(address(creditToken), address(rsa), rsa.totalOwed());
        rsa.repay();
    }

    function test_repay_acceptsTradedRevenueRepayments(uint128 _revenue, uint256 _amount) public {
        uint256 revenue = bound(_revenue, 100, MAX_UINT);
        _depositRSA(depositor, rsa, _amount);
        _initRSA(rsa);

        _generateRevenue(feeToken, revenue);

        // now have revenue but no claimableCredits credit tokens
        assertEq(feeToken.balanceOf(address(rsa)), revenue, "bad pre trade rev token balance");
        assertEq(creditToken.balanceOf(address(rsa)), 0, "bad pre trade cred token balance");
        assertEq(rsa.claimableAmount(), 0);
        assertEq(rsa.totalOwed(), _amount);

        uint256 bought = _tradeRevenue(address(feeToken), revenue, _amount);
        uint256 claimableCredits = bound(bought, 0, _amount);

        // debt hasnt been updated even though we traded revenue
        // should only update in repay() call
        assertEq(feeToken.balanceOf(address(rsa)), 0, "bad prepay rev token RSA balance");
        assertEq(creditToken.balanceOf(address(rsa)), bought, "bad prepay credit token RSA balance");
        assertEq(rsa.claimableAmount(), 0);
        assertEq(rsa.totalOwed(), _amount);

        rsa.repay();

        assertEq(feeToken.balanceOf(address(rsa)), 0, "bad final rev token RSA balance");
        assertEq(creditToken.balanceOf(address(rsa)), bought, "bad final credit token RSA balance");
        assertEq(rsa.claimableAmount(), claimableCredits);
        assertEq(rsa.totalOwed(), _amount - bought);
    }

    function test_repay_storesPaymentInRSA() public {
        // ensure we do not send token to depositor either as a negative case
        _depositRSA(depositor, rsa, 0.1 ether);
        _initRSA(rsa);
        _generateRevenue(creditToken, MAX_REVENUE);
        // RSA holds full revenue amount even if greater than owed for borrowerto sweep after depositor claims
        assertEq(creditToken.balanceOf(address(rsa)), MAX_REVENUE);
        assertEq(creditToken.balanceOf(depositor), 0);
        assertEq(creditToken.balanceOf(borrower), 0.1 ether);
    }

    function test_repay_mustIncreaseClaimableAmount() public {
        // ensure we do not send token to depositor either as a negative case
        assertEq(rsa.claimableAmount(), 0);

        uint256 amount = 0.1 ether;
        _depositRSA(depositor, rsa, amount);
        assertEq(rsa.claimableAmount(), 0);

        _initRSA(rsa);
        assertEq(rsa.claimableAmount(), 0);

        _generateRevenue(creditToken, MAX_REVENUE);
        uint256 claimable = MAX_REVENUE > amount ? amount : MAX_REVENUE;

        assertEq(creditToken.balanceOf(address(rsa)), MAX_REVENUE);
        assertGe(rsa.claimableAmount(), claimable); // btw amount and totalOwed()
    }

    /// @dev invariant
    function test_repay_increasesClaimableAmountByCurrentBalanceMinusExistingClaimable() public {
        uint256 amount = 0.1 ether;
        uint256 shares = _depositRSA(depositor, rsa, amount);
        _initRSA(rsa);
        assertEq(creditToken.balanceOf(address(rsa)), 0); // all sent out in initTerm

        emit log_named_uint("amount", amount);
        _generateRevenue(creditToken, amount / 2);
        emit log_named_uint("creditToken.balanceOf(address(rsa)) 0 ", creditToken.balanceOf(address(rsa)));
        assertEq(creditToken.balanceOf(address(rsa)), amount / 2);
        assertEq(rsa.claimableAmount(), amount / 2);

        _generateRevenue(creditToken, amount);
        emit log_named_uint("creditToken.balanceOf(address(rsa)) 1 ", creditToken.balanceOf(address(rsa)));
        assertEq(creditToken.balanceOf(address(rsa)), amount);
        assertEq(rsa.claimableAmount(), amount); // updated claimable properly

        _generateRevenue(creditToken, amount * 2);
        emit log_named_uint("creditToken.balanceOf(address(rsa)) 2", creditToken.balanceOf(address(rsa)));
        assertEq(creditToken.balanceOf(address(rsa)), amount * 2);
        assertEq(rsa.claimableAmount(), shares); // stops accumulating at totalOwed
            // TODO in test_repay_mustCapClaimableRepaymentsToTotalOwed()
    }

    function test_repay_partialAmountsMultipleTimes(uint256 _revenue) public {
        uint256 amount = 0.1 ether;
        _depositRSA(depositor, rsa, amount);
        _initRSA(rsa);
        uint256 totalRevenue;
        while (amount > 0) {
            assertEq(amount, rsa.totalOwed());
            uint256 revenue = bound(_revenue, amount / 5, amount / 3);
            _generateRevenue(creditToken, revenue);

            // update testing param
            totalRevenue += revenue;
            if (revenue > amount) {
                amount = 0;
            } else {
                amount -= revenue;
            }
            // clear operator tokens so _assertSpigot in _generateRevenue passes on multiple invocations
            // hoax(operator);
            // rsa.claimOperatorTokens(address(creditToken));

            // rsa.repay(); // claimRev auto calls repay() for us
            // TODO test actual repay()?
            // ensure we have tokens that we think were repaid
            assertEq(creditToken.balanceOf(address(rsa)), totalRevenue);
        }
    }

    function test_repay_mustCapClaimableRepaymentsToTotalOwed(uint256 _amount) public {
        vm.assume(_amount < 100 ether);
        uint256 amount = _depositRSA(depositor, rsa, _amount);
        _initRSA(rsa);
        uint256 total = rsa.totalOwed();
        assertGe(total, amount); // Ge for potential network fees added on 
        // first payment in full
        assertEq(uint8(rsa.status()), uint8(FunFunding.STATUS.ACTIVE));
        vm.expectEmit(true, true, true, true);
        // status auto change from ACTIVE -> REPAID when all debt gone
        emit FunFunding.Repay(total);
        _generateRevenue(creditToken, total);
        assertEq(amount, rsa.claimableAmount());
        assertEq(rsa.claimableAmount(), total);

        // double check we claimed more than owed for later math

        deal(address(creditToken), address(rsa), total * 2);
        vm.expectRevert(FunFunding.InvalidStatus.selector);
        rsa.repay();

        // prove that claimable doesnt exceed owed w/ extra credit tokens
        assertEq(rsa.claimableAmount(), total);
        // yet still have extra tokens in contract
        assertEq(total * 2, creditToken.balanceOf(address(rsa)));
        assertEq(amount, rsa.claimableAmount(), "claimable vs owed not valid");
    }

    /// @dev invariant
    function invariant_repay_mustHaveClaimableAmountAsMinimumCreditTokenBalance() public {
        assertGe(creditToken.balanceOf(address(rsa)), rsa.claimableAmount());
    }

    function test_sweep_onlyBorrower() public {
        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.startPrank(rando);
        rsa.sweep(address(feeToken), rando);
        vm.stopPrank();

        vm.startPrank(borrower);
        rsa.sweep(address(feeToken), borrower);
        vm.stopPrank();

        // set depositor so to test that role
        _depositRSA(depositor, rsa, 0.1 ether);
        _initRSA(rsa);

        // still cant sweep() once they depost and become the ofificial depositor
        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.startPrank(depositor);
        rsa.sweep(address(feeToken), depositor);
        vm.stopPrank();
    }

    function test_sweep_sendsFullRandomTokenBalance() public {
        deal(address(feeToken), address(rsa), 1000);
        uint256 preBalance = feeToken.balanceOf(address(rsa));

        vm.startPrank(borrower);
        rsa.sweep(address(feeToken), rando);

        uint256 postBalance = feeToken.balanceOf(address(rsa));
        uint256 sweeperBalance2 = feeToken.balanceOf(address(rando));
        assertEq(postBalance, 0);
        assertEq(sweeperBalance2, 1000);
    }

    function test_sweep_retainsCreditTokensEqualToClaims(uint256 _amount) public {
        deal(address(creditToken), address(rsa), 1000);
        uint256 preBalance = creditToken.balanceOf(address(rsa));

        assertEq(rsa.totalSupply(), 0, "invariant Failed: no deposit() == no claims == no supply");
        vm.startPrank(borrower);
        // no depositor so totalSupply == 0 == can sweep full amount
        rsa.sweep(address(creditToken), rando);
        vm.stopPrank();

        uint256 postBalance = creditToken.balanceOf(address(rsa));
        // cant seep bc there are still totalOwed() amount of outstanding claims to retain creditTokens for
        assertEq(postBalance, 0);
        assertEq(preBalance - postBalance, 1000, "1st no-debt sweep failed on RSA balance");
        assertEq(creditToken.balanceOf(address(rando)), 1000, "1st no-debt sweep failed to receipien");

        uint256 shares = _depositRSA(depositor, rsa, _amount); // now totalSupply == totalOwed && totalSupply >, 0.1 ether 0
        _initRSA(rsa);
        // totalSupply still equal original supply because no redeems yet
        assertEq(rsa.totalSupply(), shares);

        deal(address(creditToken), address(rsa), rsa.totalOwed() + 1000);
        rsa.repay();
        assertEq(rsa.totalOwed(), 0, "All debt mustve been repaid");
        assertEq(rsa.totalSupply(), shares); //  still no redeems so full suopply exists

        uint256 preBalance2 = creditToken.balanceOf(address(rsa));
        assertEq(preBalance2, _amount + 1000);

        vm.startPrank(borrower);
        // no debt so sweep works
        rsa.sweep(address(creditToken), rando);
        uint256 sweeperBalance1 = creditToken.balanceOf(rando);
        assertEq(2000, sweeperBalance1); // 1000 from original sweep + 1000 from second sweep
        vm.stopPrank();

        uint256 postBalance2 = creditToken.balanceOf(address(rsa));
        assertEq(postBalance2, _amount);
        assertEq(preBalance2 - postBalance2, 1000);

        vm.startPrank(depositor);
        uint256 redeemedAmount = 5000;
        rsa.redeem(redeemedAmount, depositor, depositor);
        vm.stopPrank();
        uint256 postBalance3 = creditToken.balanceOf(address(rsa));
        assertEq(postBalance3, shares - redeemedAmount, "bad post deposit + redeem balances");
        assertEq(postBalance2 - postBalance3, redeemedAmount);

        vm.startPrank(borrower);
        // already swept excess so cant sweep more since balance == claims still
        rsa.sweep(address(creditToken), rando);
        uint256 sweeperBalance2 = creditToken.balanceOf(rando);
        assertEq(2000, sweeperBalance2, "sweeper failed"); // 1000 == original sweep
        assertEq(postBalance3, creditToken.balanceOf(address(rsa)));

        deal(address(creditToken), address(rsa), 1000);
        assertEq(postBalance3 + 1000, creditToken.balanceOf(address(rsa)));
        rsa.sweep(address(creditToken), rando);
        uint256 sweeperBalance3 = creditToken.balanceOf(rando);
        assertEq(3000, sweeperBalance3, "bad end sweeper balances"); // 2000 == original sweep + final sweep

        // ensure we still have right claimable amount of underlying tokens in contract
        assertEq(postBalance3, creditToken.balanceOf(address(rsa)));
        assertEq(postBalance3, shares - redeemedAmount);

        vm.stopPrank();
    }

    function test_sweep_mustDisperseIfNoDebt() public {
        // TODO split between tests for sweep in init/cancel vs repaid
        deal(address(feeToken), address(rsa), 1000);
        uint256 preBalance = feeToken.balanceOf(address(rsa));

        // no depositor so no debt
        assertEq(rsa.totalOwed(), 0); // totalOwed not updated because not init and no deposits
        assertEq(uint8(rsa.status()), uint8(FunFunding.STATUS.INIT));

        vm.startPrank(borrower);
        rsa.sweep(address(feeToken), borrower);
        assertEq(0, feeToken.balanceOf(address(rsa)));
        vm.stopPrank();

        uint256 postBalance = feeToken.balanceOf(address(rsa));
        assertEq(postBalance, 0);
        assertEq(preBalance - postBalance, 1000);

        _depositRSA(depositor, rsa, 0.1 ether);
        _initRSA(rsa);
        assertEq(uint8(rsa.status()), uint8(FunFunding.STATUS.ACTIVE));

        vm.prank(rsa.owner());
        vm.expectRevert(FunFunding.InvalidStatus.selector);
        rsa.sweep(address(feeToken), borrower);

        emit log_named_uint("totalOwed", rsa.totalOwed());
        emit log_named_uint("balance", creditToken.balanceOf(address(rsa)));

        // repay full  debt
        deal(address(creditToken), address(rsa), rsa.totalOwed());
        rsa.repay();
        assertEq(uint8(rsa.status()), uint8(FunFunding.STATUS.REPAID));

        deal(address(feeToken), address(rsa), 1000);
        uint256 preBalance2 = feeToken.balanceOf(address(rsa));

        vm.startPrank(borrower);
        // debt repaid so can sweep now
        rsa.sweep(address(feeToken), borrower);
        vm.stopPrank();

        uint256 postBalance2 = feeToken.balanceOf(address(rsa));
        assertEq(postBalance2, 0);
        assertEq(preBalance2 - postBalance2, 1000);
    }

    function test_sweep_mustFailIfDebt() public {
        deal(address(feeToken), address(rsa), 1000);
        uint256 preBalance = feeToken.balanceOf(address(rsa));

        vm.startPrank(borrower);
        // no depositor so no debt so can sweep
        rsa.sweep(address(feeToken), borrower);
        vm.stopPrank();

        uint256 postBalance = feeToken.balanceOf(address(rsa));
        assertEq(postBalance, 0);
        assertEq(preBalance - postBalance, 1000);

        // now borrower is in debt
        _depositRSA(depositor, rsa, 0.1 ether);
        
        vm.startPrank(borrower);
        // no debt officially until initTerm(). just pooled deposits
        assertEq(creditToken.balanceOf(borrower), 0);
        vm.expectRevert(ERC20.InsufficientBalance.selector);
        rsa.sweep(address(creditToken), borrower);
        assertEq(creditToken.balanceOf(address(rsa)), 0.1 ether);
        assertEq(creditToken.balanceOf(borrower), 0);
        vm.stopPrank();

        _initRSA(rsa);
        assertEq(creditToken.balanceOf(address(borrower)), 0.1 ether);

        deal(address(feeToken), address(rsa), 1000);
        uint256 preBalance2 = feeToken.balanceOf(address(rsa));

        vm.startPrank(borrower);
        vm.expectRevert(FunFunding.InvalidStatus.selector);
        rsa.sweep(address(feeToken), borrower);
        vm.stopPrank();

        // confirm failed and all tokens still there
        uint256 postBalance2 = feeToken.balanceOf(address(rsa));
        assertEq(postBalance2, 1000);
        assertEq(preBalance2, postBalance2);

        // repay loan and test sweep again
        uint256 total = rsa.totalOwed();
        _generateRevenue(creditToken, total);
        vm.startPrank(borrower);
        rsa.sweep(address(feeToken), borrower);
        assertEq(feeToken.balanceOf(address(rsa)), 0);
        assertEq(feeToken.balanceOf(address(borrower)), preBalance + preBalance2);

        rsa.sweep(address(creditToken), borrower);
        assertEq(creditToken.balanceOf(address(rsa)), total);
        assertEq(rsa.claimableAmount(), total);
        // only original money from loan in wallet, nothing swept
        assertEq(creditToken.balanceOf(address(borrower)), 0.1 ether);
        vm.stopPrank();
    }

    //     Testing Helpers & Automations
    //     **********************
    //     *********************/

    function _generateRevenue(IERC20x _token, uint256 _amount) internal {
        deal(address(_token), address(rsa), _amount);
        // TODO add rsa.repay() if tests failing
        rsa.repay();
    }

    /**
     * @dev Creates a new Revenue Share Agreement mints token to depositor and approves to RSA
     * @param _token address of token being lent
     * @param _apr total return rate for lifetime of RSA (time undetermined)
     */
    function _initRSA(address _token, uint16 _apr) internal returns (FunFunding newRSA) {
        address _newRSA = factory.deployFunFunding(borrower, _token, _apr, "RSA Revenue Stream Token", "rsaCLAIM");
        return FunFunding(_newRSA);
    }

    function _initRSA(FunFunding _rsa) internal {
        vm.prank(_rsa.owner());
        _rsa.initiateTerm();
    }

    function _depositRSA(address _depositor, FunFunding _rsa, uint256 amount) internal returns (uint256 shares) {
        // uint256 amount = _rsa.totalOwed(); no longer set on initialize()
        deal(address(creditToken), _depositor, amount);
        vm.startPrank(_depositor);
        creditToken.approve(address(_rsa), type(uint256).max);
        shares = _rsa.deposit(amount, _depositor);
        vm.stopPrank();
    }

    /**
     * @dev sends tokens through spigot and makes claimable for owner and operator
     */
    function _tradeRevenue(address _feeToken, uint256 _minRevenueSold, uint256 _minCreditsBought)
        internal
        returns (uint256 tokensBought)
    {
        // dont actually need to initiate trade since we can update EVM state manually
        // keep to document flow and hopefully check bugs related to process
        hoax(depositor);
        rsa.initiateOrder(
            address(_feeToken), _minRevenueSold, _minCreditsBought, uint32(block.timestamp + MAX_TRADE_DEADLINE)
        );

        // simulate trade by moving want tokens into rsa, and transferring sold tokens out
        deal(address(creditToken), address(rsa), _minCreditsBought);
        vm.prank(address(rsa));
        IERC20x(_feeToken).transfer(address(0), _minRevenueSold);

        return _minCreditsBought;
    }
}
