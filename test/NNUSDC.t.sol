// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {IERC20x} from "../src/Interfaces.sol";
import {NNETHCore} from "./NNETHCore.t.sol";
import {NNETHBaseTest} from "./NNETHBaseTest.t.sol";
import {NNETHAaveIntegration} from "./NNETHAave.integration.t.sol";

contract NNUSDCAaveIntegration is NNETHAaveIntegration {
    // GHO fails on decimals() call in initialize()
    // IERC20x public GHO = IERC20x(0x6Bb7a212910682DCFdbd5BCBb3e28FB4E8da10Ee);
    // IERC20x public debtGHO = IERC20x(0x38e59ADE183BbEb94583d44213c8f3297e9933e9);
    IERC20x public BTC = IERC20x(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 );
    IERC20x public debtBTC = IERC20x(0x59dca05b6c26dbd64b5381374aAaC5CD05644C28);

    function setUp() override(NNETHAaveIntegration) public {
        reserveToken = USDC;
        debtToken = debtBTC;
        borrowToken = address(BTC);
        super.setUp();
    }
}

contract NNUSDCCore is NNETHCore {
    // GHO fails on decimals() call in initialize()
    // IERC20x public GHO = IERC20x(0x6Bb7a212910682DCFdbd5BCBb3e28FB4E8da10Ee);
    // IERC20x public debtGHO = IERC20x(0x38e59ADE183BbEb94583d44213c8f3297e9933e9);
    
    // TBH ETH might be better bc we just pay ourselves yield vs BTC which we dont have atm
    IERC20x public BTC = IERC20x(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    IERC20x public debtBTC = IERC20x(0x59dca05b6c26dbd64b5381374aAaC5CD05644C28);

    function setUp() override(NNETHBaseTest) public {
        reserveToken = USDC;
        debtToken = debtBTC;
        borrowToken = address(BTC);
        super.setUp();
    }
}

