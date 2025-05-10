// SPDX-License-Identifier: UNLICENSED
// https://github.com/horsefacts/FunETH-invariant-testing/blob/main/test/WETH9.symbolic.t.sol

pragma solidity ^0.8.26;

import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import {Test} from "forge-std/Test.sol";

import {FunETH} from "../../src/FunETH.sol";
import {IERC20} from "../../src/Interfaces.sol";
import {FunETHBaseTest} from "./FunETHBaseTest.t.sol";

contract WETHSymTest is SymTest, FunETHBaseTest {
    function test_globalInvariants(bytes4 selector, address caller, uint256 val) public {
        // Execute an arbitrary tx
        vm.prank(caller);
        bytes memory call = gen_calldata(selector, val);
        // if a valid selector, then call with data
        emit log_bytes(call);
        if (call.length != 0) {
            (bool success,) = address(funETH).call(call);
            vm.assume(success); // ignore reverting cases
        }

        // Record post-state
        assert(funETH.totalSupply() <= funETH.underlying());
    }

    // @dev deposit() increases the caller's balance by exactly msg.value;
    function test_deposit_depositorBalanceUpdate(address guy, uint256 wad) public assumeValidAddress(guy) {
        uint256 balanceBefore = funETH.balanceOf(guy);

        wad = _depositnnEth(guy, wad, true);

        uint256 balanceAfter = funETH.balanceOf(guy);

        assert(balanceAfter == balanceBefore + wad);
    }

    // @dev deposit() does not change the balance of any address besides the caller.
    function test_deposit_balancePreservation(address guy, address gal, uint256 wad) public assumeValidAddress(guy) {
        vm.assume(guy != gal);
        uint256 balanceBefore = funETH.balanceOf(gal);

        wad = _depositnnEth(guy, wad, true);

        uint256 balanceAfter = funETH.balanceOf(gal);

        assert(balanceAfter == balanceBefore);
    }

    // @dev withdraw() decreases the caller's balance by exactly msg.value;
    function test_withdraw_withdrawerBalanceUpdate(address guy, uint256 wad) public assumeValidAddress(guy) {
        vm.assume(guy != address(debtToken));
        vm.assume(guy != address(funETH.aToken()));

        wad = _depositnnEth(guy, wad, true);

        uint256 balanceBefore = funETH.balanceOf(guy);

        _withdrawnnEth(guy, wad);

        uint256 balanceAfter = funETH.balanceOf(guy);

        assert(balanceAfter == balanceBefore - wad);
    }

    // @dev withdraw() does not change the balance of any address besides the caller.
    function test_withdraw_balancePreservation(address guy, address gal, uint256 wad) public assumeValidAddress(guy) {
        vm.assume(guy != gal);
        vm.assume(guy != address(debtToken));
        vm.assume(guy != address(funETH.aToken()));

        wad = _depositnnEth(guy, wad, true);

        uint256 balanceBefore = funETH.balanceOf(gal);

        _withdrawnnEth(guy, wad);

        uint256 balanceAfter = funETH.balanceOf(gal);

        assert(balanceAfter == balanceBefore);
    }

    // @dev approve(dst, wad) sets dst allowance to wad.
    function test_approve_allowanceUpdate(address guy, address dst, uint256 wad) public assumeValidAddress(guy) {
        wad = bound(wad, funETH.MIN_DEPOSIT(), MAX_AAVE_DEPOSIT);
        vm.prank(guy);
        funETH.approve(dst, wad);

        uint256 allowanceAfter = funETH.allowance(guy, dst);

        assert(allowanceAfter == wad);
    }

    // @dev approve(dst, wad) does not change the allowance of any other address/spender.
    function test_approve_allowancePreservation(address guy, address dst1, uint256 wad, address gal, address dst2)
        public
        assumeValidAddress(guy)
    {
        vm.assume(guy != gal);

        wad = bound(wad, funETH.MIN_DEPOSIT(), MAX_AAVE_DEPOSIT);

        uint256 allowanceBefore = funETH.allowance(gal, dst2);

        vm.prank(guy);
        funETH.approve(dst1, wad);

        assert(funETH.allowance(gal, dst2) == allowanceBefore); // original unnaffected by other user/dst

        vm.prank(guy);
        funETH.approve(dst2, wad); // to same dst unaffected too
        assert(funETH.allowance(gal, dst2) == allowanceBefore);
    }

    // @dev transfer(dst, wad):
    //      - decreases guy's balance by exactly wad.
    //      - increases dst's balance by exactly wad.
    function test_transfer_balanceUpdate(address guy, address dst, uint256 wad) public assumeValidAddress(guy) {
        vm.assume(guy != dst);

        // vm.deal(guy, wad);
        wad = _depositnnEth(guy, wad, true);

        uint256 guyBalanceBefore = funETH.balanceOf(guy);
        uint256 dstBalanceBefore = funETH.balanceOf(dst);

        vm.prank(guy);
        funETH.transfer(dst, wad);

        uint256 guyBalanceAfter = funETH.balanceOf(guy);
        uint256 dstBalanceAfter = funETH.balanceOf(dst);

        assert(guyBalanceAfter == guyBalanceBefore - wad);
        assert(dstBalanceAfter == dstBalanceBefore + wad);
    }

    // @dev transfer(dst, wad):
    //      - does not change balance of any other address
    function test_transfer_balancePreservation(address guy, address dst, uint256 wad, address gal)
        public
        assumeValidAddress(guy)
    {
        vm.assume(guy != dst);
        vm.assume(guy != gal);
        vm.assume(dst != gal);

        // vm.deal(guy, wad);
        wad = _depositnnEth(guy, wad, true);

        uint256 galBalanceBefore = funETH.balanceOf(gal);

        vm.prank(guy);
        funETH.transfer(dst, wad);

        uint256 galBalanceAfter = funETH.balanceOf(gal);

        assert(galBalanceAfter == galBalanceBefore);
    }

    // @dev transferFrom(src, dst, wad):
    //      - decreases src's balance by exactly wad.
    //      - increases dst's balance by exactly wad.
    function test_transferFrom_balanceUpdate(address guy, address src, address dst, uint256 wad, uint256 approval)
        public
        assumeValidAddress(guy)
        assumeValidAddress(src)
        assumeValidAddress(dst)
    {
        vm.assume(src != dst);

        wad = _depositnnEth(src, wad, true);
        // vm.deal(src, wad);
        vm.assume(approval > wad);
        deal(address(funETH), src, wad);

        vm.prank(src);
        funETH.approve(guy, approval);

        uint256 srcBalanceBefore = funETH.balanceOf(src);
        uint256 dstBalanceBefore = funETH.balanceOf(dst);

        vm.prank(guy);
        funETH.transferFrom(src, dst, wad);

        uint256 srcBalanceAfter = funETH.balanceOf(src);
        uint256 dstBalanceAfter = funETH.balanceOf(dst);

        assert(srcBalanceAfter == srcBalanceBefore - wad);
        assert(dstBalanceAfter == dstBalanceBefore + wad);
    }

    // @dev transfer(dst, wad):
    //      - does not change balance of any other address
    function test_transferFrom_balancePreservation(
        address guy,
        address src,
        address dst,
        uint256 wad,
        uint256 approval,
        address gal
    ) public assumeValidAddress(guy) assumeValidAddress(src) assumeValidAddress(dst) {
        vm.assume(guy != dst);
        vm.assume(guy != gal);
        vm.assume(dst != gal);
        vm.assume(src != gal);

        wad = _depositnnEth(src, wad, true);
        vm.assume(approval > wad);

        vm.prank(src);
        funETH.approve(guy, approval);

        uint256 srcBalanceBefore = funETH.balanceOf(src);
        uint256 galBalanceBefore = funETH.balanceOf(gal);

        vm.prank(guy);
        funETH.transferFrom(src, dst, wad);

        assert(funETH.balanceOf(gal) == galBalanceBefore);
        assert(funETH.balanceOf(src) == srcBalanceBefore - wad);
    }

    // @dev transferFrom(src, dst, wad):
    //      - decreases msg.sender's allowance by exactly wad.
    function test_transferFrom_allowanceUpdate(address guy, address src, address dst, uint256 wad, uint256 approval)
        public
        assumeValidAddress(guy)
        assumeValidAddress(src)
        assumeValidAddress(dst)
    {
        vm.assume(guy != src);
        vm.assume(src != dst);
        vm.assume(approval != type(uint256).max);
        wad = _depositnnEth(src, wad, true);
        vm.assume(approval > wad);

        vm.prank(src);
        funETH.approve(guy, approval);

        uint256 guyAllowanceBefore = funETH.allowance(src, guy);
        emit log_named_uint("init apporval", approval);
        emit log_named_uint("guy apporval", guyAllowanceBefore);

        emit log_named_uint("amnt", wad);
        vm.prank(guy);
        funETH.transferFrom(src, dst, wad);

        uint256 guyAllowanceAfter = funETH.allowance(src, guy);

        assert(guyAllowanceAfter == guyAllowanceBefore - wad);
    }

    // @dev transferFrom(src, dst, wad):
    //      - does not change allowance if caller is src.
    function test_transferFrom_allowanceUpdate_callerIsSrc(
        address guy,
        address src,
        address dst,
        uint256 wad,
        uint256 approval
    ) public assumeValidAddress(guy) assumeValidAddress(src) assumeValidAddress(dst) {
        vm.assume(guy != src);
        vm.assume(src != dst);

        wad = _depositnnEth(src, wad, true);
        vm.assume(approval > wad);

        vm.prank(src);
        funETH.approve(guy, approval);

        uint256 guyAllowanceBefore = funETH.allowance(guy, guy);
        vm.assume(guyAllowanceBefore != type(uint256).max);

        vm.prank(guy);
        funETH.transferFrom(src, dst, wad);

        uint256 guyAllowanceAfter = funETH.allowance(guy, guy);

        assert(guyAllowanceAfter == guyAllowanceBefore);
    }

    // @dev transferFrom(src, dst, wad):
    //      - does not change msg.sender's allowance if set to type(uint256).max
    function test_transferFrom_allowanceUpdate_maxAllowance(address guy, address src, address dst, uint256 wad)
        public
        assumeValidAddress(guy)
        assumeValidAddress(src)
        assumeValidAddress(dst)
    {
        wad = _depositnnEth(src, wad, true);

        vm.assume(src != dst);

        vm.startPrank(src);
        funETH.approve(guy, type(uint256).max);
        vm.stopPrank();

        uint256 guyAllowanceBefore = funETH.allowance(src, guy);

        vm.prank(guy);
        funETH.transferFrom(src, dst, wad);

        uint256 guyAllowanceAfter = funETH.allowance(src, guy);

        assert(guyAllowanceAfter == guyAllowanceBefore);
        assert(guyAllowanceAfter == type(uint256).max);
    }

    function gen_calldata(bytes4 selector, uint256 wad) internal returns (bytes memory) {
        // Ignore view functions
        // Skip for now

        // Create symbolic values to be included in calldata
        address guy = makeAddr("guy");
        address src = makeAddr("src");
        address dst = makeAddr("dst");
        // uint256 wad = uint256(vm.random());

        // Generate calldata based on the function selector
        // wad = bound(wad, funETH.MIN_DEPOSIT(), MAX_AAVE_DEPOSIT);
        bytes memory args;
        if (selector == FunETH.withdraw.selector) {
            args = abi.encode(wad);
        } else if (selector == IERC20.approve.selector) {
            args = abi.encode(guy, wad);
        } else if (selector == IERC20.transfer.selector) {
            args = abi.encode(dst, wad);
        } else if (selector == IERC20.transferFrom.selector) {
            args = abi.encode(src, dst, wad);
        } else {
            // For functions where all parameters are static (not dynamic arrays or bytes),
            // a raw byte array is sufficient instead of explicitly specifying each argument.
            // args = svm.createBytes(1024, "data"); // choose a size that is large enough to cover all parameters
            return bytes("");
        }
        return abi.encodePacked(selector, args);
    }
}
