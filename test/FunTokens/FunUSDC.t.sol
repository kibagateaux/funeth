// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {IERC20x} from "../../src/Interfaces.sol";
import {FunETHCore} from "./FunETHCore.t.sol";
import {FunETHBaseTest} from "./FunETHBaseTest.t.sol";
import {FunETHAaveIntegration} from "./FunETHAave.integration.t.sol";
import {nnEthInvariants} from "./WETH.invariant.t.sol";
import {WETHSymTest} from "./WETH.symbolic.t.sol";

contract NNUSDCAaveIntegration is FunETHAaveIntegration {
    function setUp() public virtual override(FunETHAaveIntegration) {
        reserveToken = USDC;
        debtToken = debtWETH;
        borrowToken = address(WETH);
        super.setUp();
    }

    function test_initialize_configSetup() public virtual {
        assertEq(address(reserveToken), address(USDC));
        assertEq(address(debtToken), address(debtWETH));
        assertEq(address(borrowToken), address(WETH));
    }
}

contract NNUSDCCore is FunETHCore {
    function setUp() public virtual override(FunETHBaseTest) {
        reserveToken = USDC;
        debtToken = debtWETH;
        borrowToken = address(WETH);
        super.setUp();
    }

    function test_initialize_configSetup() public virtual override {
        assertEq(address(reserveToken), address(USDC));
        assertEq(address(debtToken), address(debtWETH));
        assertEq(address(borrowToken), address(WETH));
    }
}

contract NNUSDCInvariants is nnEthInvariants {
    function setUp() public virtual override(nnEthInvariants) {
        reserveToken = USDC;
        debtToken = debtWETH;
        borrowToken = address(WETH);
        super.setUp();
    }

    function test_initialize_configSetup() public virtual {
        assertEq(address(reserveToken), address(USDC));
        assertEq(address(debtToken), address(debtWETH));
        assertEq(address(borrowToken), address(WETH));
    }
}

contract NNUSDCSymTest is WETHSymTest {
    function setUp() public virtual override(FunETHBaseTest) {
        reserveToken = USDC;
        debtToken = debtWETH;
        borrowToken = address(WETH);
        super.setUp();
    }

    function test_initialize_configSetup() public virtual {
        assertEq(address(reserveToken), address(USDC));
        assertEq(address(debtToken), address(debtWETH));
        assertEq(address(borrowToken), address(WETH));
    }
}
