// pragma solidity ^0.8.26;

// import "forge-std/Test.sol";
// import {GPv2Order} from "../../src/lib/GPv2.sol";
// import {FunFunding} from "../../src/utils/FunFunding.sol";

// contract RSACowSwapIntegrationTest is Test {
//     using GPv2Order for GPv2Order.Data;

//     /*********************
//     **********************

//     CowSwap Market Order Creation

//     Integration Tests

//     **********************
//     *********************/

//     // TODO what happens if we iniitate multiple orders for the same token inbetween the first one being finalized?
//     // could happen with same tokens or new revenue tokens between trade inits

//     /// @dev invariant
//     function test_generateOrder_mustReturnCowswapOrderFormat() public {
//         // semantic wrapper
//         // we already manually import GPv2 library and check against generateOrder
//         test_generateOrder_mustUseHardcodedOrderParams();
//     }

//     /// @dev invariant
//     function test_generateOrder_mustUseHardcodedOrderParams() public {
//         _depositRSA(lender, rsa);

//         address sellToken = address(revenueToken);
//         address buyToken = address(creditToken);
//         uint32 deadline = uint32(block.timestamp + MAX_TRADE_DEADLINE);

//          GPv2Order.Data memory expectedOrder = GPv2Order.Data({
//             kind: GPv2Order.KIND_SELL,
//             receiver: address(rsa), // hardcode so trades are trustless
//             sellToken: sellToken,  // hardcode so trades are trustless
//             buyToken: buyToken,
//             sellAmount: 1,
//             buyAmount: 0,
//             feeAmount: 0,
//             validTo: deadline,
//             appData: 0,
//             partiallyFillable: false,
//             sellTokenBalance: GPv2Order.BALANCE_ERC20,
//             buyTokenBalance: GPv2Order.BALANCE_ERC20
//         });
//         bytes32 expectedHash = expectedOrder.hash(COWSWAP_DOMAIN_SEPARATOR);

//         GPv2Order.Data memory order = rsa.generateOrder(sellToken, 1, 0, deadline);
//         bytes32 orderHash = order.hash(COWSWAP_DOMAIN_SEPARATOR);

//         assertEq(expectedHash, orderHash);
//     }

//     function test_initiateOrder_returnsOrderHash() public {
//         _depositRSA(lender, rsa);
//         vm.startPrank(lender);
//         bytes32 orderHash = rsa.initiateOrder(address(revenueToken), 1, 0, uint32(block.timestamp + MAX_TRADE_DEADLINE));
//         assertTrue(orderHash != bytes32(0));
//         vm.stopPrank();
//     }

//     /// @dev invariant
//     function test_initiateOrder_mustUseHardcodedOrderParams() public {
//         _depositRSA(lender, rsa);

//         address sellToken = address(revenueToken);
//         uint32 deadline = uint32(block.timestamp + MAX_TRADE_DEADLINE);

//         GPv2Order.Data memory expectedOrder = rsa.generateOrder(sellToken, 1, 0, deadline);
//         bytes32 expectedHash = expectedOrder.hash(COWSWAP_DOMAIN_SEPARATOR);

//         vm.startPrank(lender);
//         bytes32 orderHash = rsa.initiateOrder(sellToken, 1, 0, deadline);
//         vm.stopPrank();

//         assertEq(orderHash, expectedHash);
//     }

//     function test_initiateOrder_mustOwnSellAmount() public {
//         _depositRSA(lender, rsa);
//         vm.startPrank(lender);
//         bytes32 orderHash = rsa.initiateOrder(address(revenueToken), 1, 0, uint32(block.timestamp + MAX_TRADE_DEADLINE));
//         assertTrue(orderHash != bytes32(0));
//         vm.stopPrank();
//     }

//     /// @dev invariant
//     function test_initiateOrder_mustSellOver1Token() public {
//         _depositRSA(lender, rsa);
//         vm.startPrank(lender);
//         vm.expectRevert("Invalid trade amount");
//         rsa.initiateOrder(address(revenueToken), 0, 0, uint32(block.timestamp + MAX_TRADE_DEADLINE));
//         vm.stopPrank();
//     }

//     /// @dev invariant
//     function invariant_initiateOrder_cantTradeIfNoDebt() public {
//         // havent deposited so no debt
//         vm.startPrank(borrower);
//         vm.expectRevert("agreement unitinitiated");
//         rsa.initiateOrder(address(revenueToken), 1, 0, uint32(block.timestamp + MAX_TRADE_DEADLINE));
//         vm.stopPrank();

//         vm.startPrank(lender);
//         vm.expectRevert("Trade not required");
//         rsa.initiateOrder(address(revenueToken), 1, 0, uint32(block.timestamp + MAX_TRADE_DEADLINE));
//         vm.stopPrank();

//         vm.startPrank(rando);
//         vm.expectRevert("Trade not required");
//         rsa.initiateOrder(address(revenueToken), 1, 0, uint32(block.timestamp + MAX_TRADE_DEADLINE));
//         vm.stopPrank();
//     }

//     /// @dev invariant
//     function test_initiateOrder_cantSellCreditToken() public {
//         _depositRSA(lender, rsa);
//         vm.startPrank(lender);
//         vm.expectRevert("Cant sell token being bought");
//         rsa.initiateOrder(address(creditToken), 1, 0, uint32(block.timestamp + MAX_TRADE_DEADLINE));
//         vm.stopPrank();
//     }

//     function test_initiateOrder_lenderOrBorrowerCanSubmit() public {
//         _depositRSA(lender, rsa);
//         uint32 deadline =  uint32(block.timestamp + MAX_TRADE_DEADLINE);
//         vm.startPrank(lender);
//         rsa.initiateOrder(address(revenueToken), 1, 0, deadline);
//         vm.stopPrank();
//         vm.startPrank(borrower);
//         rsa.initiateOrder(address(revenueToken), 1, 0, deadline);
//         vm.stopPrank();

//         vm.startPrank(rando);
//         vm.expectRevert("Caller must be stakeholder");
//         rsa.initiateOrder(address(revenueToken), 1, 0, deadline);
//         vm.stopPrank();
//     }

//     function test_initiateOrder_storesOrderData() public {
//         _depositRSA(lender, rsa);
//         uint32 deadline =  uint32(block.timestamp + MAX_TRADE_DEADLINE);
//         bytes32 orderId = rsa.generateOrder(address(revenueToken), 1, 0, deadline).hash(COWSWAP_DOMAIN_SEPARATOR);
//         assertEq(rsa.orders(orderId), 0);

//         vm.startPrank(lender);
//         rsa.initiateOrder(address(revenueToken), 1, 0, deadline);
//         assertEq(rsa.orders(orderId), deadline);
//         vm.stopPrank();
//     }

//     function _initOrder(address _sellToken, uint256 _sellAmount, uint32 _deadline) internal returns(bytes32) {
//         _depositRSA(lender, rsa);
//         vm.startPrank(lender);
//         return rsa.initiateOrder(address(_sellToken), _sellAmount, 0, _deadline);
//     }

//     /********************* EIP-2981 Order Verification *********************/

//     function test_verifySignature_mustInitiateOrderFirst() public {
//         uint32 deadline = uint32(block.timestamp + MAX_TRADE_DEADLINE);
//         GPv2Order.Data memory order = rsa.generateOrder(address(revenueToken), 1, 0, deadline);
//         bytes32 expectedOrderId = order.hash(COWSWAP_DOMAIN_SEPARATOR);
//         assertEq(rsa.orders(expectedOrderId), 0);

//         // vm.expectRevert(FunFunding.InvalidTradeId.selector);

//         // orderId is the signed orderdata
//         assertEq(rsa.isValidSignature(expectedOrderId, abi.encode(order)), ERC_1271_NON_MAGIC_VALUE);

//         bytes32 orderId = _initOrder(address(revenueToken), 1, deadline);
//         // signature should be valid now that we initiated order
//         bytes4 value = rsa.isValidSignature(expectedOrderId, abi.encode(order)); // orderId is the signed orderdata
//         // assert all state changes since isValidSignature might return NON_MAGIC_VALUE
//         assertEq(value, ERC_1271_MAGIC_VALUE);
//         assertEq(expectedOrderId, orderId);
//         assertEq(rsa.orders(expectedOrderId), deadline);
//     }

//     /// @dev invariant
//     function test_verifySignature_mustUseERC20Balance() public {
//         revert();
//     }

//     /// @dev invariant
//     function test_verifySignature_mustBuyCreditToken() public {
//         revert();
//     }

//     /// @dev invariant
//     function invariant_verifySignature_mustBeSellOrder() public {
//         // GPv2Order memory order = rsa.generateOrder(address(revenueToken), 1, 0, uint32(block.timestamp + MAX_TRADE_DEADLINE));
//         // rsa.orders[order.hash(COWSWAP_DOMAIN_SEPARATOR)] = 1;
//     }

//     /// @dev invariant
//     function test_verifySignature_mustSignOrderFromCowContract() public {
//         revert();
//     }

//     function test_verifySignature_returnsMagicValueForValidOrders() public {
//         GPv2Order.Data memory order = rsa.generateOrder(address(revenueToken), 1, 0, uint32(block.timestamp + MAX_TRADE_DEADLINE));
//         bytes32 orderId = _initOrder(address(revenueToken), 1, uint32(block.timestamp + MAX_TRADE_DEADLINE));
//         // signature should be valid now that we initiated order
//         bytes4 value = rsa.isValidSignature(orderId, abi.encode(order)); // orderId is the signed orderdata
//         assertEq(value, ERC_1271_MAGIC_VALUE);
//     }

//     function test_verifySignature_returnsNonMagicValueForInvalidOrders() public {
//         GPv2Order.Data memory order = rsa.generateOrder(address(revenueToken), 1, 0, uint32(block.timestamp + MAX_TRADE_DEADLINE));
//         bytes32 badOrderId = rsa.generateOrder(address(revenueToken), 1, 0, uint32(block.timestamp + MAX_TRADE_DEADLINE)).hash(COWSWAP_DOMAIN_SEPARATOR);
//         // signature should be valid now that we initiated order
//         bytes4 value = rsa.isValidSignature(badOrderId, abi.encode(order)); // orderId is the signed orderdata
//         assertEq(value, ERC_1271_NON_MAGIC_VALUE);
//     }

//     // TODO!!! need to test that the hardcoded order params that isValidSignature never passes if any of those conditions are met

//     /*********************
//     **********************

//     Event Emissions

//     Unit Tests

//     **********************
//     *********************/

//     function test_deposit_emitsDepositEvent() public {
//         vm.expectEmit(true, true, false, true, address(rsa));
//         emit FunFunding.Deposit(lender);
//         _depositRSA(lender, rsa);
//     }

//     function test_repay_emitsRepayEvent(uint256 _amount) public {
//         vm.assume(_amount > 100);
//         creditToken.mint(address(rsa), _amount);
//         vm.expectEmit(true, true, true, true, address(rsa));
//         uint256 claimble = _amount > totalOwed ? totalOwed : _amount;
//         emit FunFunding.Repay(claimble);
//         rsa.repay();
//     }

//     function test_claimRev_emitsRepayEvent(uint256 _amount) public {
//         uint256 revAmount = bound(_amount, 100, MAX_UINT - totalOwed); // prevent overflow in MockToken totalSupply
//         _depositRSA(lender, rsa);
//         (uint256 claimed, ) = _generateRevenue(creditToken, revAmount);
//         uint256 claimable = claimed > totalOwed ? totalOwed : claimed;
//         vm.expectEmit(true, true, false, false, address(rsa));
//         emit FunFunding.Repay(claimable);
//         rsa.claimRev(address(creditToken));
//     }

//     function test_redeem_emitsRedeemEvent() public {
//         _depositRSA(lender, rsa);

//         _generateRevenue(creditToken, MAX_REVENUE);
//         rsa.claimRev(address(creditToken));

//         vm.prank(lender);
//         vm.expectEmit(true, true, false, true, address(rsa));
//         emit FunFunding.Redeem(lender, lender, lender, 1);
//         rsa.redeem(lender, lender, 1);
//         vm.stopPrank();
//     }

//     function test_initiateOrder_emitsOrderInitiatedEvent() public {
//         _depositRSA(lender, rsa);
//         uint32 deadline = uint32(block.timestamp + MAX_TRADE_DEADLINE);
//         bytes32 orderId = rsa.generateOrder(address(revenueToken), 1, 0, deadline).hash(COWSWAP_DOMAIN_SEPARATOR);
//         assertEq(rsa.orders(orderId), 0);

//         vm.startPrank(lender);
//         vm.expectEmit(true, true, true, true, address(rsa));
//         emit FunFunding.OrderInitiated(address(creditToken), address(revenueToken), orderId, 1, 0, deadline);
//         rsa.initiateOrder(address(revenueToken), 1, 0, deadline);
//         assertEq(rsa.orders(orderId), deadline);
//         vm.stopPrank();
//     }
// }
