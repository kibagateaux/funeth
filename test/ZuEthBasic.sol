pragma solidity ^0.8.26;

import {ZuEthBaseTest} from "./ZuEthBaseTest.t.sol";
import {IERC20, IAaveMarket, IZuETH} from "../src/Interfaces.sol";
import {ZuETH} from "../src/ZuETH.sol";

contract ZuEthBasic is ZuEthBaseTest {
    function test_initialize_cantReinitialize() public {
        vm.expectRevert(ZuETH.AlreadyInitialized.selector);
        zuETH.initialize(address(WETH), address(aave), address(debtUSDC), "ZuCity Ethereum", "zuETH");
    }

    function test_initialize_setsProperDepositToken() public {
        emit log_address(address(zuETH));
        assert(zuETH.aToken() == IERC20(0xD4a0e0b9149BCee3C920d2E00b5dE09138fd8bb7));
    }
}