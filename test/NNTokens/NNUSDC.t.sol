// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {IERC20x} from "../../src/Interfaces.sol";
import {NNETHCore} from "./NNETHCore.t.sol";
import {NNETHBaseTest} from "./NNETHBaseTest.t.sol";
import {NNETHAaveIntegration} from "./NNETHAave.integration.t.sol";
import {nnEthInvariants} from "./WETH.invariant.t.sol";
import {WETHSymTest} from "./WETH.symbolic.t.sol";

contract NNUSDCAaveIntegration is NNETHAaveIntegration {
    function setUp() override(NNETHAaveIntegration) virtual public {
        reserveToken = USDC;
        debtToken = debtWETH;
        borrowToken = address(WETH);
        super.setUp();
    }

    function test_initialize_configSetup() virtual public {
        assertEq(address(reserveToken), address(USDC));
        assertEq(address(debtToken), address(debtWETH));
        assertEq(address(borrowToken), address(WETH));
    }
}

contract NNUSDCCore is NNETHCore {
    function setUp() override(NNETHBaseTest) virtual public {
        reserveToken = USDC;
        debtToken = debtWETH;
        borrowToken = address(WETH);
        super.setUp();
    }

    function test_initialize_configSetup() override virtual public {
        assertEq(address(reserveToken), address(USDC));
        assertEq(address(debtToken), address(debtWETH));
        assertEq(address(borrowToken), address(WETH));
    }
}


contract NNUSDCInvariants is nnEthInvariants {
    function setUp() override(nnEthInvariants) virtual public {
        reserveToken = USDC;
        debtToken = debtWETH;
        borrowToken = address(WETH);
        super.setUp();
    }

    function test_initialize_configSetup() virtual public {
        assertEq(address(reserveToken), address(USDC));
        assertEq(address(debtToken), address(debtWETH));
        assertEq(address(borrowToken), address(WETH));
    }
}


contract NNUSDCSymTest is WETHSymTest {
    function setUp() override(NNETHBaseTest) virtual public {
        reserveToken = USDC;
        debtToken = debtWETH;
        borrowToken = address(WETH);
        super.setUp();
    }

    function test_initialize_configSetup() virtual public {
        assertEq(address(reserveToken), address(USDC));
        assertEq(address(debtToken), address(debtWETH));
        assertEq(address(borrowToken), address(WETH));
    }
}

