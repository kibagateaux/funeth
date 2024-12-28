pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {ZuETH} from "../src/ZuETH.sol";
import {IERC20x, IAaveMarket, IZuETH} from "../src/Interfaces.sol";

contract ZuEthBaseTest is Test {
    ZuETH public zuETH;

    // Base asset/protocol addresses
    IERC20x public debtUSDC = IERC20x(0x59dca05b6c26dbd64b5381374aAaC5CD05644C28);
    IERC20x public debtWETH = IERC20x(0x24e6e0795b3c7c71D965fCc4f371803d1c1DcA1E);
    IERC20x public WETH = IERC20x(0x4200000000000000000000000000000000000006);
    IERC20x public USDC = IERC20x(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    IAaveMarket public aaveBase = IAaveMarket(0xA238Dd80C259a72e81d7e4664a9801593F98d1c5);
    uint256 public MAX_AAVE_DEPOSIT = 100 ether; // TODO get supply cap for Aave on network
    
    // chain agnostic test variables
    IERC20x reserveToken = WETH;
    IERC20x public debtToken = debtUSDC;
    IAaveMarket public aave = aaveBase;

    uint256 private baseFork;

    function setUp() virtual public {
        baseFork = vm.createSelectFork(vm.rpcUrl('base'), 23_502_225);
        zuETH = new ZuETH();

        // 1 = ETHLIKE. Aave on Base does not have stablecoin eMode, only ETH.
        uint256 eMode = 0;
        zuETH.initialize(address(WETH), address(aave), address(debtToken), 0, "ZuCity Ethereum", "zuETH");
    }

    function _depositZuEth(address user, uint256 amount) internal returns (uint256 deposited) {
        deposited = bound(amount, zuETH.MIN_DEPOSIT(), MAX_AAVE_DEPOSIT); // prevent min/max supply reverts on Aave

        vm.startPrank(user);
        zuETH.reserveToken().approve(address(zuETH), deposited);
        zuETH.deposit(deposited);
        vm.stopPrank();
    }

    function _depositZuEth(address user, uint256 amount, bool mint) internal returns (uint256 deposited) {
        deposited = bound(amount, zuETH.MIN_DEPOSIT(), MAX_AAVE_DEPOSIT); // prevent min/max supply reverts on Aave

        if(mint) deal(address(zuETH.reserveToken()), user, deposited);
        return _depositZuEth(user, deposited);
    }

    function _withdrawZuEth(address user, uint256 amount) internal {
        vm.assume(user != address(debtToken));
        vm.assume(user != address(zuETH.aToken()));
        // when we deposit -> withdraw immediately we have 1 wei less balance than we deposit
        // probs attack prevention method on aave protocol so move 1 block ahead to increase balance from interest
        
        vm.warp(block.timestamp + 1 days);
        vm.prank(user);
        zuETH.withdraw(amount);
    }

    
    function _borrowable(uint256 zuethSupply) internal returns (uint256 aaveTotalCredit, uint256 zuEthCreditLimit){
        uint256 ltvConfig = 80; // TODO pull from Aave.reserveConfig or userAcccountData
        
        (, bytes memory data) = IAaveMarket(0xe20fCBdBfFC4Dd138cE8b2E6FBb6CB49777ad64D).getPriceOracle().call(abi.encodeWithSignature("getAssetPrice(address)", reserveToken));
        uint256 price;
        assembly {
            price := mload(add(data, 32))
        }
        // TODO add ETH price
        aaveTotalCredit = (zuethSupply * ltvConfig * price) / 1e20; // total credit / token decimal diff (10) / price decimals (10)
        // aaveTotalCredit = (zuethSupply * ltvConfig) / 1e10; // total credit / token decimal diff (10) / price decimals (10)
        zuEthCreditLimit = (aaveTotalCredit / zuETH.MIN_HEALTH_FACTOR());
        // borrowable = delegated / zuETH.MIN_HEALTH_FACTOR();
    }


}