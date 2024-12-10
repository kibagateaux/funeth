// // SPDX-License-Identifier: GPL-3.0-or-later
// // https://github.com/horsefacts/zuETH-invariant-testing/blob/main/test/ZuETH.invariants.t.sol

// pragma solidity ^0.8.26;

// import {Test} from "forge-std/Test.sol";
// import {ZuETH} from "../src/ZuETH.sol";

// import {Handler, ETH_SUPPLY} from "./ZuEthPlaybook.sol";
// import {ZuEthBaseTest} from "./ZuEthBaseTest.t.sol";
// import {IERC20, IAaveMarket, IZuETH} from "../src/Interfaces.sol";


// contract ZuEthInvariants is Test {
//     Handler public handler;
//     ZuETH public zuETH;
//     IERC20 public debtUSDC = IERC20(0x59dca05b6c26dbd64b5381374aAaC5CD05644C28);
//     IERC20 public WETH = IERC20(0x4200000000000000000000000000000000000006);
//     IAaveMarket public aave = IAaveMarket(0xA238Dd80C259a72e81d7e4664a9801593F98d1c5);


//     function setUp() public {        

//         IERC20 public debtUSDC = IERC20(0x59dca05b6c26dbd64b5381374aAaC5CD05644C28);
//         IERC20 public WETH = IERC20(0x4200000000000000000000000000000000000006);
//         IAaveMarket public aave = IAaveMarket(0xA238Dd80C259a72e81d7e4664a9801593F98d1c5);

//         zuETH = new ZuETH();
//         zuETH.initialize(address(WETH), address(aave), address(debtUSDC), "ZuCity Ethereum", "zuETH");

//         handler = new Handler(zuETH);

//         // bytes4[] memory selectors = new bytes4[](4);
//         // selectors[0] = Handler.deposit.selector;
//         // selectors[1] = Handler.withdraw.selector;
//         // selectors[2] = Handler.transfer.selector;
//         // selectors[3] = Handler.transferFrom.selector;
//         // selectors[2] = Handler.approve.selector;
//         // selectors[5] = Handler.sendFallback.selector;
//         // selectors[6] = Handler.forcePush.selector;

//         // basically do a bunch of random shit before we test invariants
//         // targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));

//         // targetContract(address(handler));
//     }

//     // ETH can only be wrapped into WETH, WETH can only
//     // be unwrapped back into ETH. The sum of the Handler's
//     // ETH balance plus the WETH totalSupply() should always
//     // equal the total ETH_SUPPLY.
//     function invariant_conservationOfETH() public {
//         assertEq(ETH_SUPPLY, address(handler).balance + zuETH.totalSupply());
//     }

//     function invariant_noETHUnfarmed() public {
//         assertEq(0, address(zuETH).balance);
//         assertGe(0, zuETH.underlying());
//     }

//     // The WETH contract's Ether balance should always be
//     // at least as much as the sum of individual deposits
//     function invariant_solvencyDeposits() public {
//         assertEq(
//             zuETH.underlying(),
//             handler.ghost_depositSum() + handler.ghost_forcePushSum() - handler.ghost_withdrawSum()
//         );
//     }

//     // The WETH contract's Ether balance should always be
//     // at least as much as the sum of individual balances
//     function invariant_solvencyBalances() public {
//         uint256 sumOfBalances = handler.reduceActors(0, this.accumulateBalance);
//         assertEq(zuETH.underlying() - handler.ghost_forcePushSum(), sumOfBalances);
//     }

//     function accumulateBalance(uint256 balance, address caller) external view returns (uint256) {
//         return balance + zuETH.balanceOf(caller);
//     }

//     // No individual account balance can exceed the
//     // WETH totalSupply().
//     function invariant_depositorBalances() public {
//         handler.forEachActor(this.assertAccountBalanceLteTotalSupply);
//     }

//     function assertAccountBalanceLteTotalSupply(address account) external {
//         assertLe(zuETH.balanceOf(account), zuETH.totalSupply());
//     }

//     function invariant_callSummary() public view {
//         handler.callSummary();
//     }
// }