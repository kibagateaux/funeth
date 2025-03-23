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
    
    IAaveMarket public aaveBase = IAaveMarket(0xA238Dd80C259a72e81d7e4664a9801593F98d1c5);
    uint256 public MAX_AAVE_DEPOSIT = 1000 ether; // TODO get supply cap for Aave on network
    uint8 aaveEMode = 0;
    
    // chain agnostic test variables
    IERC20x public reserveToken = WETH;
    IERC20x public debtToken = debtUSDC;
    address public borrowToken = address(USDC);
    // IERC20x public debtToken = debtGHO;
    // address public borrowToken = address(GHO);
    IAaveMarket public aave = aaveBase;

    uint256 private baseFork;

    function setUp() virtual public {
        baseFork = vm.createSelectFork(vm.rpcUrl('base'), 23_502_225);
        nnETH = new NNETH();

        // 1 = ETHLIKE. Aave on Base does not have stablecoin eMode, only ETH.
        nnETH.initialize(address(reserveToken), address(aave), address(debtToken), aaveEMode, "nnCity Ethereum", "nnETH");
    }

    function _depositnnEth(address user, uint256 amount) internal returns (uint256 deposited) {
        deposited = bound(
            amount,
            nnETH.MIN_DEPOSIT(),// prevent decimal rounding errors on aave protocol
            // prevent max supply reverts on Aave
            reserveToken.decimals() == 18 ? MAX_AAVE_DEPOSIT : 1000 gwei
        ); 

        vm.startPrank(user);
        nnETH.reserveToken().approve(address(nnETH), deposited);
        nnETH.deposit(deposited);
        vm.stopPrank();
    }

    /// @notice ensure enough collateral so we have credit > 0 so borrow() calls dont fail on 0.
    function _depositForBorrowing(address user, uint256 amount) internal returns (uint256 deposited) {
        deposited = bound(
            amount,
            // prevent decimal rounding errors btw price feed + tokens during testing
            reserveToken.decimals() == 18 ? 10 ether : 100_000_000,
            // prevent max supply reverts on Aave
            reserveToken.decimals() == 18 ? MAX_AAVE_DEPOSIT : 1000 gwei
        ); 

        deal(address(nnETH.reserveToken()), user, deposited);

        vm.startPrank(user);
        nnETH.reserveToken().approve(address(nnETH), deposited);
        nnETH.deposit(deposited);
        vm.stopPrank();
    }

    function _depositnnEth(address user, uint256 amount, bool mint) internal returns (uint256 deposited) {
        deposited = bound(amount, nnETH.MIN_DEPOSIT(), MAX_AAVE_DEPOSIT); // prevent min/max supply reverts on Aave

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
        vm.assume(user != address(debtToken));
        vm.assume(user != address(nnETH.aToken()));
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
        uint256 ltvConfig = 8000; // TODO pull from Aave.reserveConfig or userAcccountData
        
        //mainnet oracle. Base doesnt work
        (, bytes memory data) = IAaveMarket(0xe20fCBdBfFC4Dd138cE8b2E6FBb6CB49777ad64D).getPriceOracle().call(abi.encodeWithSignature("getAssetPrice(address)", reserveToken));
        // (, bytes memory data) = aaveBase.getPriceOracle().call(abi.encodeWithSignature("getAssetPrice(address)", reserveToken));
        uint256 price;
        assembly {
            price := mload(add(data, 32))
        }

        aaveTotalCredit = (nnethSupply * ltvConfig * price) / 1e22; // total credit / token18 vs aave8 decimal diff (10) / price decimals (8) / bps decimals (4)
        nnEthCreditLimit = ((aaveTotalCredit / nnETH.MIN_RESERVE_FACTOR()) - 1) / 1e2; // just under limit. account for aave vs debtToken decimals

        emit log_named_uint("ETH collateralized (18 dec)", nnethSupply);
        emit log_named_uint("ETH price (8 dec)", price);
        emit log_named_uint("collateral val (18 dec)", (nnethSupply * price) / 1e8);
        emit log_named_uint("max credit usd (0 dec)", aaveTotalCredit);

        // 41_666_667 min ETH deposited to borrow 1 USDC of credit
        // 100 = nnETHCreditLimit in Aave 8 decimals = 1 USDC in 6 decimals
        // (100 * 1e22) / ltvConfig * price * nnETH.MIN_RESERVE_FACTOR() = (nnethSupply) ;
    }
}