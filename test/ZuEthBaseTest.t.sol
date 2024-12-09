pragma solidity ^0.8.19;

import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import {Test} from "forge-std/Test.sol";

import {ZuETH} from "../src/ZuETH.sol";
import { IERC20, IAaveMarket } from "../src/Interfaces.sol";

contract ZuETHBaseTest is SymTest, Test {
    ZuETH zueth;
    IERC20 debtUSDC = IERC20(0x59dca05b6c26dbd64b5381374aAaC5CD05644C28);
    IERC20 WETH = IERC20(0x4200000000000000000000000000000000000006);
    IAaveMarket aave = IAaveMarket(0xA238Dd80C259a72e81d7e4664a9801593F98d1c5);

    string BASE_RPC_URL = vm.envString("BASE_RPC_URL");


    function setUp() public {
        // fork base mainnet
        vm.createSelectFork(BASE_RPC_URL, 23_471_564);
        
        zueth = new ZuETH(address(WETH), address(aave), address(debtUSDC), "ZuCity Ethereum", "zuETH");
    }

    function test_initialize_setsProperDepositToken() public {
        assert(zueth.aToken() == address(0xD4a0e0b9149BCee3C920d2E00b5dE09138fd8bb7));
    }


}