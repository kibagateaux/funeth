pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {ZuETH} from "../src/ZuETH.sol";
import {IERC20, IAaveMarket, IZuETH} from "../src/Interfaces.sol";

contract ZuEthBaseTest is Test {
    ZuETH public zuETH;
    IERC20 reserveToken;
    IERC20 public debtUSDC = IERC20(0x59dca05b6c26dbd64b5381374aAaC5CD05644C28);
    IERC20 public WETH = IERC20(0x4200000000000000000000000000000000000006);
    IAaveMarket public aave = IAaveMarket(0xA238Dd80C259a72e81d7e4664a9801593F98d1c5);

    // string private BASE_RPC_URL = vm.envString("BASE_RPC_URL");
    uint256 private baseFork;

    function setUp() virtual public {
        baseFork = vm.createSelectFork(vm.rpcUrl('base'), 23_471_564);
        reserveToken = WETH;
        zuETH = new ZuETH();
        // vm.makePersistent(address(zuETH));
        zuETH.initialize(address(WETH), address(aave), address(debtUSDC), "ZuCity Ethereum", "zuETH");
    }

    function _wethZuethDeposit(address user, uint256 amount) internal {
        deal(user, amount);
        WETH.deposit{value: amount};
        zuETH.deposit(amount);
    }


}