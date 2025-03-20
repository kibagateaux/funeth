pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {nnETH as NetworkNationETH} from "../src/nnETH.sol";
import {IERC20x, IAaveMarket, InnETH} from "../src/Interfaces.sol";

contract nnEthBaseTest is Test {
    NetworkNationETH public nnETH;

    // Base asset/protocol addresses
    IERC20x public WETH = IERC20x(0x4200000000000000000000000000000000000006);
    IERC20x public debtWETH = IERC20x(0x24e6e0795b3c7c71D965fCc4f371803d1c1DcA1E);
    IERC20x public USDC = IERC20x(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    IERC20x public debtUSDC = IERC20x(0x59dca05b6c26dbd64b5381374aAaC5CD05644C28);
    // GHO fails on decimals() call in initialize()
    // IERC20x public GHO = IERC20x(0x6Bb7a212910682DCFdbd5BCBb3e28FB4E8da10Ee); // GHO
    // IERC20x public debtGHO = IERC20x(0x38e59ADE183BbEb94583d44213c8f3297e9933e9); // GHO
    IAaveMarket public aaveBase = IAaveMarket(0xA238Dd80C259a72e81d7e4664a9801593F98d1c5);
    uint256 public MAX_AAVE_DEPOSIT = 1000 ether; // TODO get supply cap for Aave on network
    uint8 aaveEMode = 0;
    
    // chain agnostic test variables
    IERC20x reserveToken = WETH;
    IERC20x public debtToken = debtUSDC;
    IAaveMarket public aave = aaveBase;

    uint256 private baseFork;

    function setUp() virtual public {
        baseFork = vm.createSelectFork(vm.rpcUrl('base'), 23_502_225);
        nnETH = new NetworkNationETH();

        // 1 = ETHLIKE. Aave on Base does not have stablecoin eMode, only ETH.
        nnETH.initialize(address(WETH), address(aave), address(debtToken), aaveEMode, "nnCity Ethereum", "nnETH");
    }

    function _depositnnEth(address user, uint256 amount) internal returns (uint256 deposited) {
        deposited = bound(amount, nnETH.MIN_DEPOSIT(), MAX_AAVE_DEPOSIT); // prevent min/max supply reverts on Aave

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

    
    function _borrowable(uint256 nnethSupply) internal returns (uint256 aaveTotalCredit, uint256 nnEthCreditLimit){
        uint256 ltvConfig = 8000; // TODO pull from Aave.reserveConfig or userAcccountData
        
        //mainnet oracle. Base doesnt work
        (, bytes memory data) = IAaveMarket(0xe20fCBdBfFC4Dd138cE8b2E6FBb6CB49777ad64D).getPriceOracle().call(abi.encodeWithSignature("getAssetPrice(address)", reserveToken));
        // (, bytes memory data) = aaveBase.getPriceOracle().call(abi.encodeWithSignature("getAssetPrice(address)", reserveToken));
        uint256 price;
        assembly {
            price := mload(add(data, 32))
        }
        emit log_named_uint("ETH price", price);
        // TODO add ETH price
        aaveTotalCredit = (nnethSupply * ltvConfig * price) / 1e22; // total credit / token18 vs aave8 decimal diff (10) / price decimals (8) / bps decimals (4)
        // aaveTotalCredit = (nnethSupply * ltvConfig) / 1e10; // total credit / token decimal diff (10) / price decimals (10)
        nnEthCreditLimit = (aaveTotalCredit ) / nnETH.MIN_RESERVE_FACTOR() - 1; // just under limit
    }


}