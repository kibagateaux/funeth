pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {NNETH} from "../src/NNETH.sol";
import {IERC20x, IAaveMarket, INNETH} from "../src/Interfaces.sol";

contract NNETHBaseTest is Test {
    NNETH public nnETH;

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

    uint256 private baseFork;

    function setUp() virtual public {
        baseFork = vm.createSelectFork(vm.rpcUrl('base'), 23_502_225);

        nnETH = new NNETH();

        (,bytes memory data) = address(reserveToken).call(abi.encodeWithSignature("symbol()"));
        emit log_named_string("reserve asset symbol", abi.decode(data, (string)));
        (,bytes memory data2) = address(borrowToken).call(abi.encodeWithSignature("symbol()"));
        emit log_named_string  ("debt asset symbol", abi.decode(data2, (string)));

        nnETH.initialize(address(reserveToken), address(aave), address(debtToken), "nnCity Ethereum", "nnETH");
    }

    function _assumeValidAddress(address target) internal {
        //  addresses that will throw errors or miscalculations during testing
        vm.assume(address(0) != target);
        vm.assume(target != nnETH.ZU_CITY_TREASURY()); // maybe dont want this here
        vm.assume(target != address(aave));
        vm.assume(address(nnETH.aToken()) != target);
        vm.assume(address(WETH) != target);
        vm.assume(address(debtWETH) != target);
        vm.assume(address(USDC) != target);
        vm.assume(address(debtUSDC) != target);
        vm.assume(address(0x3ABd6f64A422225E61E435baE41db12096106df7) != target); // proxy admin. throws if USDC called by them.
        vm.assume(address(BTC) != target);
        vm.assume(address(debtBTC) != target);
    }

    function _boundDepositAmount(uint256 initial, bool borrowable) internal returns (uint256) {
        uint256 min;
        // give enough deposit that collateral value lets us borrow at least 1 unit of debt token
        if(borrowable) min = reserveToken.decimals() == 18 ? 10 ether : 100_000_000;
        else min = nnETH.MIN_DEPOSIT();
        uint256 max = reserveToken.decimals() == 18 ? MAX_AAVE_DEPOSIT : MAX_AAVE_DEPOSIT_USDC;
        return bound(
            initial,
            min,// prevent decimal rounding errors on aave protocol
            max // prevent max supply reverts on Aave
        ); 
    }

    function _depositnnEth(address user, uint256 amount) internal returns (uint256 deposited) {
        deposited = _boundDepositAmount(amount, false);

        vm.startPrank(user);
        nnETH.reserveToken().approve(address(nnETH), deposited);
        nnETH.deposit(deposited);
        vm.stopPrank();
    }

    /// @notice ensure enough collateral so we have credit > 0 so borrow() calls dont fail on 0.
    function _depositForBorrowing(address user, uint256 amount) internal returns (uint256 deposited) {
        vm.assume(user != address(0));
        deposited = _boundDepositAmount(amount, true);

        deal(address(nnETH.reserveToken()), user, deposited);

        vm.startPrank(user);
        nnETH.reserveToken().approve(address(nnETH), deposited);
        nnETH.deposit(deposited);
        vm.stopPrank();
    }

    function _depositnnEth(address user, uint256 amount, bool mint) internal returns (uint256 deposited) {
        vm.assume(user != address(0));
        deposited = _boundDepositAmount(amount, false);
        if(mint) deal(address(nnETH.reserveToken()), user, deposited);
        return _depositnnEth(user, deposited);
    }

    function _lend(address city, uint256 amount) internal {
        vm.assume(city != address(0)); // prevent aave error sending to 0x0

        // when we deposit -> withdraw immediately we have 1 wei less balance than we deposit
        // probs attack prevention method on aave protocol so move 1 block ahead to increase balance from interest
        vm.warp(block.timestamp + 1 weeks);

        vm.prank(nnETH.ZU_CITY_TREASURY());
        nnETH.lend(city, amount);
    }

    function _withdrawnnEth(address user, uint256 amount) internal {
        // when we deposit -> withdraw immediately we have 1 wei less balance than we deposit
        // probs attack prevention method on aave protocol so move 1 block ahead to increase balance from interest
        
        vm.warp(block.timestamp + 1 days);
        vm.prank(user);
        nnETH.withdraw(amount);
    }

    /**
    * @dev denominated in Aave protocol base asset decimals (8 decimals from Chainlink feed)
        NOT debtToken decimals so must convert for calculations on lend/borrow
    */
    function _borrowable(uint256 nnethSupply) internal returns (uint256 aaveTotalCredit, uint256 nnEthCreditLimit){
        (,,,, uint256 ltvConfig,) = aave.getUserAccountData(address(nnETH));

        // Normal market doesnt return as it should so use AddressProvider to fetch oracle.
        (, bytes memory data) = IAaveMarket(0xe20fCBdBfFC4Dd138cE8b2E6FBb6CB49777ad64D).getPriceOracle().call(abi.encodeWithSignature("getAssetPrice(address)", reserveToken));

        uint256 price;
        assembly {
            price := mload(add(data, 32))
        }
        
        emit log_named_uint("reserveToken price (8 dec)", price);

        aaveTotalCredit = (nnethSupply * ltvConfig * price)
            / 1e4 // ltv bps offset
            / 1e8;  // price decimals

        // 8 = some aave internal decimal thing since we already offset price decimals
        aaveTotalCredit = nnETH.decimals() > 10 ?
            aaveTotalCredit / (10**(nnETH.decimals() - 8)) :
            aaveTotalCredit * (10**(8-nnETH.decimals()));

        nnEthCreditLimit = ((aaveTotalCredit / nnETH.MIN_RESERVE_FACTOR()) - 1) / 1e2; // just under limit. account for aave vs debtToken decimals

        // 41_666_667 min ETH deposited to borrow 1 USDC of credit
        // 100 = nnETHCreditLimit in Aave 8 decimals = 1 USDC in 6 decimals
        // (100 * 1e22) / ltvConfig * price * nnETH.MIN_RESERVE_FACTOR() = (nnethSupply) ;
    }
}