pragma solidity ^0.8.26;

import {ZuETH} from "../src/ZuETH.sol";
import {IERC20, IAaveMarket, IZuETH} from "../src/Interfaces.sol";

import {ZuEthBaseTest} from "./ZuEthBaseTest.t.sol";
import {Handler} from "./ZuEthPlaybook.sol";

contract ZuEthBasic is ZuEthBaseTest {
    function test_deposit_aaveIntegration(uint256 amount) public {
        
    }
    function assertAccountBalanceLteTotalSupply(address account) external {
        assertLe(zuETH.balanceOf(account), zuETH.totalSupply());
    }

}