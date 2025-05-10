// SPDX-License-Identifier: GPL-3.0-or-later
// https://github.com/horsefacts/FunETH-invariant-testing/blob/main/test/funETH.invariants.t.sol

pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {Handler, ETH_SUPPLY} from "./FunEthPlaybook.t.sol";
import {FunETHBaseTest} from "./FunETHBaseTest.t.sol";

contract nnEthInvariants is FunETHBaseTest {
    Handler public handler;

    function setUp() public virtual override {
        super.setUp();
        handler = new Handler(funETH, address(reserveToken));

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = Handler.deposit.selector;
        selectors[1] = Handler.withdraw.selector;
        selectors[2] = Handler.approve.selector;
        selectors[3] = Handler.transfer.selector;
        selectors[4] = Handler.transferFrom.selector;
        // selectors[5] = Handler.sendFallback.selector;
        // selectors[6] = Handler.forcePush.selector;

        // basically do a bunch of random shit before we test invariants
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));

        targetContract(address(handler));
    }

    // ETH can only be wrapped into WETH, WETH can only
    // be unwrapped back into ETH. The sum of the Handler's
    // ETH balance plus the WETH totalSupply() should always
    // equal the total ETH_SUPPLY.
    function invariant_conservationOfETH() public view {
        assertEq(ETH_SUPPLY, reserveToken.balanceOf(address(handler)) + funETH.totalSupply());
    }

    function invariant_noETHUnfarmed() public view {
        assertEq(0, address(funETH).balance);
        assertGe(funETH.underlying(), 0);
    }

    // The WETH contract's Ether balance should always be
    // at least as much as the sum of individual deposits
    function invariant_solvencyDeposits() public view {
        assertEq(
            funETH.underlying(), handler.ghost_depositSum() + handler.ghost_forcePushSum() - handler.ghost_withdrawSum()
        );
    }

    // The WETH contract's Ether balance should always be
    // at least as much as the sum of individual balances
    function invariant_solvencyBalances() public {
        uint256 sumOfBalances = handler.reduceActors(0, this.accumulateBalance);
        assertEq(funETH.underlying() - handler.ghost_forcePushSum(), sumOfBalances);
    }

    function accumulateBalance(uint256 balance, address caller) external view returns (uint256) {
        return balance + funETH.balanceOf(caller);
    }

    // No individual account balance can exceed the
    // WETH totalSupply().
    function invariant_depositorBalances() public {
        handler.forEachActor(this.assertAccountBalanceLteTotalSupply);
    }

    function assertAccountBalanceLteTotalSupply(address account) external view {
        assertLe(funETH.balanceOf(account), funETH.totalSupply());
    }

    function invariant_callSummary() public view {
        handler.callSummary();
    }
}
