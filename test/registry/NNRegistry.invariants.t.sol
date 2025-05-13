pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {Handler} from "./NNRegistryPlaybook.t.sol";
import {NNRegistryCoreTest} from "./NNRegistryCore.t.sol";

contract NNRegistryInvariants is NNRegistryCoreTest {
    Handler public handler;

    function setUp() public virtual override {
        super.setUp();
        handler = new Handler(registry);

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = Handler.stake.selector;
        selectors[3] = Handler.increaseStake.selector;
        selectors[4] = Handler.depositUSDCAndStake.selector;
        selectors[4] = Handler.depositETHAndStake.selector;
        selectors[1] = Handler.unstake.selector;
        selectors[1] = Handler.approve.selector;
        selectors[1] = Handler.transferFrom.selector;

        selectors[2] = Handler.listProperty.selector;
        selectors[2] = Handler.delistProperty.selector;
        selectors[2] = Handler.approveBuyer.selector;
        // selectors[5] = Handler.sendFallback.selector;
        // selectors[6] = Handler.forcePush.selector;

        // basically do a bunch of random shit before we test invariants
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));

        targetContract(address(handler));
    }

    // all stakeIDs in existance match funETH deposits + funUSDC deposits

    // all stakes + unstakes = all funETH/funUSDC deposits - funETH/funUSDC withdrawals

    //
    function invariant_callSummary() public view {
        handler.callSummary();
    }
}
