pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {FunETH} from "../../src/FunETH.sol";
import {IERC20x, IAaveMarket, IFunETH} from "../../src/Interfaces.sol";
import {FunFactory} from "../../src/utils/FunFactory.sol";

contract FunETHBaseTest is Test {
    FunETH public funETH;

    // Base asset/protocol addresses
    IERC20x public WETH = IERC20x(0x4200000000000000000000000000000000000006);
    IERC20x public debtWETH = IERC20x(0x24e6e0795b3c7c71D965fCc4f371803d1c1DcA1E);
    IERC20x public USDC = IERC20x(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    IERC20x public debtUSDC = IERC20x(0x59dca05b6c26dbd64b5381374aAaC5CD05644C28);
    // GHO fails on decimals() call in initialize()
    // IERC20x public GHO = IERC20x(0x6Bb7a212910682DCFdbd5BCBb3e28FB4E8da10Ee);
    // IERC20x public debtGHO = IERC20x(0x38e59ADE183BbEb94583d44213c8f3297e9933e9);
    // BTC doesnt get set properly in testing .initialize() for some reason
    IERC20x public BTC = IERC20x(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    IERC20x public debtBTC = IERC20x(0x59dca05b6c26dbd64b5381374aAaC5CD05644C28);

    IAaveMarket public aaveBase = IAaveMarket(0xA238Dd80C259a72e81d7e4664a9801593F98d1c5);
    uint256 public MAX_AAVE_DEPOSIT = 1000 ether; // TODO get supply cap for Aave on network
    uint256 public MAX_AAVE_DEPOSIT_USDC = 2000 gwei; // TODO get supply cap for Aave on network

    // chain agnostic test variables
    IERC20x public reserveToken = WETH;
    IERC20x public debtToken = debtUSDC;
    address public borrowToken = address(USDC);
    IAaveMarket public aave = aaveBase;
    FunFactory public factory; // for deploying RSA in integration tests or basic lend() tests

    uint256 private baseFork;

    function setUp() public virtual {
        baseFork = vm.createSelectFork(vm.rpcUrl("base"), 23_502_225);

        factory = new FunFactory(address(aave), address(WETH));
        funETH = new FunETH();

        (, bytes memory data) = address(reserveToken).call(abi.encodeWithSignature("symbol()"));
        emit log_named_string("reserve asset symbol", abi.decode(data, (string)));
        (, bytes memory data2) = address(borrowToken).call(abi.encodeWithSignature("symbol()"));
        emit log_named_string("debt asset symbol", abi.decode(data2, (string)));

        funETH.initialize(address(reserveToken), address(aave), address(debtToken), "funCity Ethereum", "funETH");
    }

    modifier assumeValidAddress(address target) {
        //  addresses that will throw errors or miscalculations during testing
        vm.assume(address(0) != target);
        // vm.assume(target != funETH.owner()); // maybe dont want this here
        // vm.assume(address(WETH) != target);
        vm.assume(address(USDC) != target);
        // vm.assume(address(BTC) != target);
        // aave protocol throws on transferring to their addresses
        vm.assume(target != address(aave));
        vm.assume(address(funETH.aToken()) != target);
        vm.assume(address(debtWETH) != target);
        vm.assume(address(debtUSDC) != target);
        // aave proxy admin throws when calling contractas admin
        // USDC proxy admin throws when calling contractas admin
        vm.assume(address(0x4fc7850364958d97B4d3f5A08f79db2493f8cA44) != target);
        vm.assume(address(0x3ABd6f64A422225E61E435baE41db12096106df7) != target);

        // Permit2 contract throws on ERC20.approve() from solady
        vm.assume(address(0x000000000022D473030F116dDEE9F6B43aC78BA3) != target);
        _;
    }

    function _boundDepositAmount(uint256 initial, bool borrowable) internal view returns (uint256) {
        uint256 min;
        // give enough deposit that collateral value lets us borrow at least 1 unit of debt token
        if (borrowable) min = reserveToken.decimals() == 18 ? 10 ether : 100_000_000;
        else min = funETH.MIN_DEPOSIT();
        uint256 max = reserveToken.decimals() == 18 ? MAX_AAVE_DEPOSIT : MAX_AAVE_DEPOSIT_USDC;
        return bound(
            initial,
            min, // prevent decimal rounding errors on aave protocol
            max // prevent max supply reverts on Aave
        );
    }

    function _depositnnEth(address user, uint256 amount) internal returns (uint256 deposited) {
        deposited = _boundDepositAmount(amount, false);

        vm.startPrank(user);
        funETH.reserveToken().approve(address(funETH), deposited);
        funETH.deposit(deposited);
        vm.stopPrank();
    }

    /// @notice ensure enough collateral so we have credit > 0 so borrow() calls dont fail on 0.
    function _depositForBorrowing(address user, uint256 amount) internal returns (uint256 deposited) {
        vm.assume(user != address(0));
        deposited = _boundDepositAmount(amount, true);

        deal(address(funETH.reserveToken()), user, deposited);

        vm.startPrank(user);
        funETH.reserveToken().approve(address(funETH), deposited);
        funETH.deposit(deposited);
        vm.stopPrank();
    }

    function _depositnnEth(address user, uint256 amount, bool mint) internal returns (uint256 deposited) {
        vm.assume(user != address(0));
        deposited = _boundDepositAmount(amount, false);
        if (mint) deal(address(funETH.reserveToken()), user, deposited);
        return _depositnnEth(user, deposited);
    }

    function _lend(address city, uint256 amount) internal {
        vm.assume(city != address(0)); // prevent aave error sending to 0x0

        // when we deposit -> withdraw immediately we have 1 wei less balance than we deposit
        // probs attack prevention method on aave protocol so move 1 block ahead to increase balance from interest
        vm.warp(block.timestamp + 1 weeks);

        address rsa = factory.deployFunFunding(city, funETH.debtAsset(), 100, "test", "test");
        vm.prank(funETH.owner());
        funETH.lend(city, rsa, amount);
    }

    function _withdrawnnEth(address user, uint256 amount) internal {
        // when we deposit -> withdraw immediately we have 1 wei less balance than we deposit
        // probs attack prevention method on aave protocol so move 1 block ahead to increase balance from interest

        vm.warp(block.timestamp + 1 days);
        vm.prank(user);
        funETH.withdraw(amount);
    }

    /**
     * @dev denominated in Aave protocol base asset decimals (8 decimals from Chainlink feed)
     *     NOT debtToken decimals so must convert for calculations on lend/borrow
     */
    function _borrowable(uint256 nnethSupply) internal returns (uint256 aaveTotalCredit, uint256 nnEthCreditLimit) {
        (,,,, uint256 ltvConfig,) = aave.getUserAccountData(address(funETH));

        // Normal market doesnt return as it should so use AddressProvider to fetch oracle.
        // (, bytes memory data) = IAaveMarket(0xe20fCBdBfFC4Dd138cE8b2E6FBb6CB49777ad64D).getPriceOracle().call(abi.encodeWithSignature("getAssetPrice(address)", reserveToken));
        // uint256 price;
        // assembly {
        //     price := mload(add(data, 32))
        // }
        uint256 reservePrice =
            IAaveMarket(aave.ADDRESSES_PROVIDER()).getPriceOracle().getAssetPrice(address(reserveToken));
        uint256 debtPrice =
            IAaveMarket(aave.ADDRESSES_PROVIDER()).getPriceOracle().getAssetPrice(debtToken.UNDERLYING_ASSET_ADDRESS());

        emit log_named_uint("reserveToken reservePrice (8 dec)", reservePrice);
        emit log_named_uint("debtToken reservePrice (8 dec)", debtPrice);

        // aaveTotalCredit = (nnethSupply * ltvConfig * reservePrice)
        //     / 1e4 // ltv bps offset
        //     / 1e8; // reservePrice decimals

        // 8 = some aave internal decimal thing since we already offset price decimals
        // total credit in usd 8 decimals
        // aaveTotalCredit = funETH.decimals() > 8 ?
        // //     // offset nnethSupply decimals to normalize to 8 dec usd price
        //     aaveTotalCredit / (10**(funETH.decimals() - 8)) :
        //     aaveTotalCredit * (10**(8-funETH.decimals()));

        // 1e4  ltv bps offset + 1e8 reservePrice decimals
        aaveTotalCredit =
            funETH.convertToDecimal(nnethSupply * ltvConfig * reservePrice, reserveToken.decimals() + 12, 8);

        emit log_named_uint("total cred init (8 dec)", aaveTotalCredit);
        // emit log_named_uint("total cred new (8 dec)", aaveTotalCredit2);

        // total credit in usd -> debt token
        // need to account for token price
        //  nnEthCreditLimit = ((aaveTotalCredit / funETH.MIN_RESERVE_FACTOR()) - 1) / 1e2; // just under limit. account for aave vs debtToken decimals
        // nnEthCreditLimit = funETH.convertToDecimal(
        //     (aaveTotalCredit / funETH.MIN_RESERVE_FACTOR()) - 1,
        //      8,
        //      debtToken.decimals()
        // );

        nnEthCreditLimit = (
            funETH.convertToDecimal(
                aaveTotalCredit,
                0, // upscale from final decimal amount (8 dec prices cancel out) to get more precise answer
                debtToken.decimals()
            ) / debtPrice / funETH.MIN_RESERVE_FACTOR()
        ) - 1;

        emit log_named_uint("total cred init (token dec)", nnEthCreditLimit);
        // emit log_named_uint("total cred new (8 dec)", nnEthCreditLimit2);
        // emit log_named_uint("total cred new2 (8 dec)", nnEthCreditLimit3);

        // 41_666_667 min ETH deposited to borrow 1 USDC of credit
        // 100 = funETHCreditLimit in Aave 8 decimals = 1 USDC in 6 decimals
        // (100 * 1e22) / ltvConfig * price * funETH.MIN_RESERVE_FACTOR() = (nnethSupply) ;
    }
}
