// pragma solidity ^0.8.26;


// import "forge-std/Test.sol";
// import {FeeClaimer} from "../../src/utils/FeeClaimer.sol";
// import {MockToken} from "../helpers/MockToken.sol";
// import {MockFeeGenerator} from "../helpers/MockFeeGenerator.sol";
// import {Ownable} from "solady/auth/Ownable.sol";
// import {IFeeClaimer} from "../../src/Interfaces.sol";

// contract FeeClaimerTest is Test, IFeeClaimer {
//     address ETH = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

   
//     // claimer contracts/configurations to test against
//     MockToken private token;
//     address private feeContract;
//     FeeClaimer private claimer;
//     FeeClaimer.ClaimContract private settings;

//     // Named vars for common inputs
//     uint256 constant MAX_REVENUE = type(uint256).max / 100;
//     // function signatures for mock revenue contract to pass as params to claimer
//     bytes4 constant opsFunc =
//         MockFeeGenerator.doAnOperationsThing.selector;
//     bytes4 constant transferOwnerFunc =
//         MockFeeGenerator.transferOwnership.selector;
//     bytes4 constant claimPullPaymentFunc =
//         MockFeeGenerator.claimPullPayment.selector;
//     bytes4 constant claimPushPaymentFunc = bytes4(0);

//     // create dynamic arrays for function args
//     // Mostly unused in tests so convenience for empty array
//     bytes4[] private whitelist;
//     address[] private c;
//     FeeClaimer.ClaimContract[] private s;

//     // FeeClaimer Controller access control vars
//     address public owner;
//     address public operator;
  

//     function setUp() public {
//         owner = address(this);
//         operator = address(10);
        
//         token = new MockToken();

//         _initFeeClaimer(
//             address(token),
//             claimPushPaymentFunc,
//             transferOwnerFunc
//         );
//     }

//     /**
//      * @dev Helper function to initialize new FeeContracts with different params to test functionality
//      */
//     function _initFeeClaimer(
//         address _token,
//         bytes4 _claimFunc,
//         bytes4 _newOwnerFunc
//     ) internal {
//         claimer = new FeeClaimer(); 
//         claimer.initialize(owner, operator, 66);

//         // deploy new revenue contract with settings
//         feeContract = address(new MockFeeGenerator(owner, _token));

//         _addFeeContract(claimer, feeContract, _claimFunc, _newOwnerFunc);
//     }


//     /**
//      * @dev Helper function to initialize new FeeContracts with different params to test functionality
//      */
//     function _addFeeContract(
//         FeeClaimer _spigot,
//         address _feeContract,
//         bytes4 _claimFunc,
//         bytes4 _newOwnerFunc
//     ) internal {
//         // deploy new revenue contract with settings

//         settings = FeeClaimer.ClaimContract(_claimFunc, _newOwnerFunc);

//         // add claimer for revenue contract
//         require(
//             _spigot.addFeeContract(feeContract, settings),
//             "Failed to add claimer"
//         );

//         // give claimer ownership to claim revenue
//         _feeContract.call(
//             abi.encodeWithSelector(_newOwnerFunc, address(claimer))
//         );
//     }

//         /**
//      * @dev sends tokens through claimer and makes claimable for owner and operator
//      */
//     function _generateFees(
//         address _feeContract,
//         MockToken _token,
//         uint256 _amount
//     ) internal returns(uint256 ownerTokens, uint256 operatorTokens) {

//         (uint8 split, bytes4 claimFunc, ) = claimer.getSetting(_feeContract);
//         deal(address(token), address(claimer), _amount);
//         /// @dev assumes claim func is push payment bc thats easiest to test
//         /// need to pass in claim data as param to support claim payments
//         bytes memory claimData = abi.encodeWithSelector(claimFunc);
//         claimer.claimFees(_feeContract, address(_token), claimData);
        
//         return assertFeeContractSplits(address(_token), _amount);
//     }

//     // FeeClaimer Initialization 

//     function test_initialize_cantInitTwice() public {
//         FeeClaimer spiggy = new FeeClaimer(); 
        
//         assertEq(spiggy.owner(), address(0));

//         spiggy.initialize(owner, operator, 70);
//         assertNotEq(spiggy.owner(), address(0));

//         vm.expectRevert(Ownable.AlreadyInitialized.selector);
//         spiggy.initialize(owner, operator, 70);
        
//         hoax(owner);
//         vm.expectRevert(Ownable.AlreadyInitialized.selector);
//         spiggy.initialize(owner, operator, 70);
        
//         hoax(operator);
//         vm.expectRevert(Ownable.AlreadyInitialized.selector);
//         spiggy.initialize(owner, operator, 70);

//         assertNotEq(spiggy.owner(), address(0));
//     }

//     function test_initialize_setsStakeholderValues() public {
//         FeeClaimer spiggy = new FeeClaimer(); 
//         assertEq(spiggy.owner(), address(0));
//         assertEq(spiggy.operator(), address(0));
    
//         spiggy.initialize(owner, operator, 37);
//         assertEq(spiggy.owner(), owner);
//         assertEq(spiggy.operator(), operator);
//     }

//     function test_initialize_anyoneCanInitialize() public {
//         hoax(vm.addr(42)); // deply as random address
//         FeeClaimer spiggy = new FeeClaimer(); 
        
//         assertEq(spiggy.owner(), address(0));

//         hoax(vm.addr(69)); // init as a different random address
//         spiggy.initialize(owner, operator, 37);
//         assertNotEq(spiggy.owner(), address(0));
//     }

//     function test_initialize_nullStakeholderAddresses() public {
//         FeeClaimer spiggy = new FeeClaimer(); 
//         assertEq(spiggy.owner(), address(0));
        
//         vm.expectRevert();
//         spiggy.initialize(address(0), operator, 37);
//         assertEq(spiggy.owner(), address(0));
        
//         vm.expectRevert();
//         spiggy.initialize(owner, address(0), 37);
//         assertEq(spiggy.owner(), address(0));
//     }

//     function test_initialize_cantUseFeeContractUntilInitialized() public {
//         FeeClaimer spiggy = new FeeClaimer(); 
//         assertEq(spiggy.owner(), address(0));

        
//         // If we cant add revenue contracts, we cant claim revenue
//         // so no potential loss of funds by sending them to address(0)
//         vm.expectRevert(FeeClaimer.CallerAccessDenied.selector);
//         spiggy.addFeeContract(feeContract, settings);
        
//         // cant get back door access to stakeholder roles
//         vm.expectRevert(FeeClaimer.CallerAccessDenied.selector);
//         spiggy.updateOwner(vm.addr(42));
//         vm.expectRevert(FeeClaimer.CallerAccessDenied.selector);
//         spiggy.updateOperator(vm.addr(42));
//     }


//     /*
//     * @notice tests same thing as `test_claimFees_updatesTokenReservesOnMultipleClaims`
//     * but wanted a diff test where we clear storage periodically instead of trying to test the max
//     * @dev invariant (started working on it below) 
//     */
//     function test_ownerAndOperatorTokens(uint64 _revenue, uint8 _months) public  {
//         vm.assume(_months > 12);
//         uint256 expectedOwnerTokens;
//         uint256 expectedOperatorTokens;
//         uint256 totalFees;
        
//         uint256 fees = bound(_revenue, 15_000 * 10**18, MAX_REVENUE * 2);
//         uint256 ownerAmount = fees * claimer.ownerSplit() / 100;
//         uint256 operatorAmount = fees - ownerAmount;

//         for(uint8 i; i < _months; i++) {
//             deal(address(token), address(claimer), fees);
//             claimer.claimFees(feeContract, address(token), abi.encodeWithSelector(claimPushPaymentFunc)); 
//             expectedOwnerTokens += ownerAmount;
//             expectedOperatorTokens += operatorAmount;
//             totalFees += fees;
//             uint256 actualOwnerTokens = claimer.getOwnerTokens(address(token));
//             uint256 actualOperatorTokens = claimer.getOperatorTokens(address(token));

//             assertEq(expectedOwnerTokens, claimer.getOwnerTokens(address(token)), "invalid owner tokens");
//             assertEq(expectedOperatorTokens, claimer.getOperatorTokens(address(token)));
//             assertEq(expectedOwnerTokens + expectedOperatorTokens, totalFees);

//             // randomly reset storage amounts to make sure our math is right
//             if(i % 9 == 0) {
//                 hoax(owner);
//                 uint256 claimed = claimer.claimOwnerTokens(address(token));
//                 expectedOwnerTokens -= claimed;
//                 totalFees -= claimed;
//             }

//             if(i % 4 == 0) {
//                 hoax(operator);
//                 uint256 claimed = claimer.claimOperatorTokens(address(token));
//                 expectedOperatorTokens -= claimed;
//                 totalFees -= claimed;
//             }
//         }
//     }

//     // function invariant_ownerAndOperatorTokens() public  {
//     //     MockToken _token = new MockToken();
//     //     uint256 months = 24;
//     //     uint256 revenue = 1500 * 10**18;
//     //     uint256 ownerTokens;
//     //     uint256 operatorTokens;
        
//     //     uint256 ownerAmount = revenue * claimer.ownerSplit() / 100;
//     //     uint256 operatorAmount = revenue - ownerAmount;

//     //     for(uint8 i; i < months; i++) {
//     //         _deal(address(token), address(claimer), revenue);
//     //         claimer.claimFees(feeContract, address(_token), abi.encodeWithSelector(claimPushPaymentFunc)); 
//     //         ownerTokens += ownerAmount;
//     //         operatorTokens += operatorAmount;
//     //         uint256 actualOwnerTokens = claimer.getOwnerTokens(address(_token));
//     //         uint256 actualOperatorTokens = claimer.getOperatorTokens(address(_token));
            
//     //         emit log_named_uint("expected ownerTokens", ownerTokens);
//     //         emit log_named_uint("actual ownerTokens", actualOwnerTokens);
//     //         emit log_named_uint("expected operatorTokens", operatorTokens);
//     //         emit log_named_uint("actual operatorTokens", actualOperatorTokens);

//     //         assertEq(ownerTokens, claimer.getOwnerTokens(address(_token)), "invalid owner tokens");
//     //         assertEq(operatorTokens, claimer.getOperatorTokens(address(_token)));
//     //         assertEq(ownerTokens + operatorTokens, revenue * i);
//     //     }
//     // }

//     // Claiming functions

//     function test_claimFees_PullPaymentNoTokenFees() public {
//         _initFeeClaimer(
//             address(token),
//             claimPullPaymentFunc,
//             transferOwnerFunc
//         );

//         bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
//         vm.expectRevert(FeeClaimer.NoFees.selector);
//         claimer.claimFees(feeContract, address(token), claimData);
//     }

//     function test_claimFees_PushPaymentNoTokenFees() public {
//         _initFeeClaimer(
//             address(token),
//             claimPushPaymentFunc,
//             transferOwnerFunc
//         );

//         bytes memory claimData;
//         vm.expectRevert(FeeClaimer.NoFees.selector);
//         claimer.claimFees(feeContract, address(token), claimData);
//     }

//     function test_claimFees_PushPaymentNoETHFees() public {
//         _initFeeClaimer(
//             ETH,
//             claimPushPaymentFunc,
//             transferOwnerFunc
//         );

//         bytes memory claimData;
//         vm.expectRevert(FeeClaimer.NoFees.selector);
//         claimer.claimFees(feeContract, address(token), claimData);
//     }

//     function test_claimFees_PullPaymentNoETHFees() public {
//         _initFeeClaimer(
//             ETH,
//             claimPullPaymentFunc,
//             transferOwnerFunc
//         );

//         bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
//         vm.expectRevert(FeeClaimer.NoFees.selector);
//         claimer.claimFees(feeContract, address(token), claimData);
//     }

//     /**
//         @dev only need to test claim function on pull payments because push doesnt call revenue contract
//      */
//     function test_claimFees_NonExistantClaimFunction() public {
//         _initFeeClaimer(
//             address(token),
//             claimPullPaymentFunc,
//             transferOwnerFunc
//         );

//         bytes memory claimData = abi.encodeWithSelector(bytes4(0xdebfda05));
//         vm.expectRevert(FeeClaimer.BadFunction.selector);
//         claimer.claimFees(feeContract, address(token), claimData);
//     }

//     function test_claimFees_MaliciousClaimFunction() public {
//         _initFeeClaimer(
//             address(token),
//             claimPullPaymentFunc,
//             transferOwnerFunc
//         );

//         bytes memory claimData = abi.encodeWithSelector(transferOwnerFunc);
//         vm.expectRevert(FeeClaimer.BadFunction.selector);
//         claimer.claimFees(feeContract, address(token), claimData);
//     }

//     // Claim Fees - payment split and escrow accounting

//     /**
//      * @dev helper func to get max revenue payment claimable in FeeClaimer.
//      *      Prevents uint overflow on owner split calculations
//     */
//     function getMaxFees(uint256 totalFees) internal pure returns(uint256, uint256) {
//         if(totalFees > MAX_REVENUE) return(MAX_REVENUE, totalFees - MAX_REVENUE);
//         return (totalFees, 0);
//     }

//     /**
//      * @dev helper func to check revenue payment streams to `ownerTokens` and `operatorTokens` happened and FeeClaimer is accounting properly.
//     */
//     function assertFeeContractSplits(address _token, uint256 totalFees) internal
//         returns(uint256 ownerTokens, uint256 operatorTokens)
//     {
//         (uint256 maxFees, uint256 overflow) = getMaxFees(totalFees);
//         ownerTokens = maxFees * claimer.ownerSplit() / 100;
//         operatorTokens = maxFees - ownerTokens;
//         uint256 spigotBalance = _token == ETH ?
//             address(claimer).balance :
//             MockToken(_token).balanceOf(address(claimer));

//         uint256 roundingFix = spigotBalance - (ownerTokens + operatorTokens + overflow);
//         if(overflow > 0) {
//             assertLe(roundingFix, 1, "FeeClaimer rounding error too large");
//         }

//         assertEq(
//             claimer.getOwnerTokens(_token),
//             ownerTokens,
//             'Invalid Owner amount for claimer revenue'
//         );

//         assertEq(
//             claimer.getOperatorTokens(_token),
//             maxFees - ownerTokens,
//             'Invalid Operator amount for claimer revenue'
//         );

//         assertEq(
//             spigotBalance,
//             ownerTokens + operatorTokens + overflow + roundingFix, // revenue over max stays in contract unnaccounted
//             'FeeClaimer balance vs Owner + Operator + overflow mismatch'
//         );
//     }

//     function test_claimFees_pushPaymentToken(uint256 totalFees) public {
//         if (totalFees == 0 || totalFees > MAX_REVENUE) return;

//         // send revenue token directly to claimer (push)
//         deal(address(token), address(claimer), totalFees);
//         assertEq(token.balanceOf(address(claimer)), totalFees);

//         bytes memory claimData;
//         claimer.claimFees(feeContract, address(token), claimData);

//         assertFeeContractSplits(address(token), totalFees);
//     }

//     function test_claimFees_failsOnNonInitializedFeeContract(uint256 totalFees) public {
//         if (totalFees == 0 || totalFees > MAX_REVENUE) return;

//         // send revenue token directly to claimer (push)
//         deal(address(token), address(claimer), totalFees);
//         assertEq(token.balanceOf(address(claimer)), totalFees);

//         bytes memory claimData;
//         vm.expectRevert(FeeClaimer.InvalidFeeContract.selector);
//         claimer.claimFees(address(0), address(token), claimData);

//         vm.expectRevert(FeeClaimer.InvalidFeeContract.selector);
//         claimer.claimFees(makeAddr("villain"), address(token), claimData);
//     }

//     function test_claimFees_pullPaymentToken(uint256 totalFees) public {
//         if (totalFees == 0 || totalFees > MAX_REVENUE) return;
//         _initFeeClaimer(
//             address(token),
//             claimPullPaymentFunc,
//             transferOwnerFunc
//         );

//         deal(address(token), feeContract, totalFees); // send revenue
//         bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
//         claimer.claimFees(feeContract, address(token), claimData);

//         assertFeeContractSplits(address(token), totalFees);
//         assertEq(
//             token.balanceOf(feeContract),
//             0,
//             "All revenue not siphoned into FeeClaimer"
//         );
//     }

//     /**
//      * @dev
//      @param totalFees - uint96 because that is max ETH in this testing address when dapptools initializes
//      */
//     function test_claimFees_pushPaymentETH(uint96 totalFees) public {
//         if (totalFees == 0 || totalFees > MAX_REVENUE) return;
//         _initFeeClaimer(
//             ETH,
//             claimPushPaymentFunc,
//             transferOwnerFunc
//         );

//         vm.deal((address(claimer)), totalFees);
//         assertEq(totalFees, address(claimer).balance); // ensure claimer received revenue

//         bytes memory claimData;
//         uint256 revenueClaimed = claimer.claimFees(
//             feeContract,
//             ETH,
//             claimData
//         );
//         assertEq(
//             totalFees,
//             revenueClaimed,
//             "Improper revenue amount claimed"
//         );

//         assertFeeContractSplits(ETH, totalFees);
//     }

//     function test_claimFees_pullPaymentETH(uint96 totalFees) public {
//         if (totalFees == 0 || totalFees > MAX_REVENUE) return;
//         _initFeeClaimer(
//             ETH,
//             claimPullPaymentFunc,
//             transferOwnerFunc
//         );

//         vm.deal(feeContract, totalFees);

//         bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
//         assertEq(
//             totalFees,
//             claimer.claimFees(feeContract, ETH, claimData),
//             "invalid revenue amount claimed"
//         );

//         assertFeeContractSplits(ETH, totalFees);
//     }

//     function test_claimFees_pushPaymentMultipleTokensPerContract(
//         uint96 tokenFees,
//         uint96 ethFees
//     ) public {
//         if (tokenFees == 0 || tokenFees > MAX_REVENUE) return;
//         if (ethFees == 0 || ethFees > MAX_REVENUE) return;

//         _initFeeClaimer(
//             ETH,
//             claimPushPaymentFunc,
//             transferOwnerFunc
//         );

//         deal(address(claimer), ethFees);
//         deal(address(token), address(claimer), tokenFees);

//         bytes memory claimData = abi.encodeWithSelector(claimPushPaymentFunc);
//         assertEq(
//             ethFees,
//             claimer.claimFees(feeContract, ETH, claimData),
//             "invalid revenue amount claimed"
//         );
//         assertEq(
//             tokenFees,
//             claimer.claimFees(feeContract, address(token), claimData),
//             "invalid revenue amount claimed"
//         );

//         assertFeeContractSplits(ETH, ethFees);
//         assertFeeContractSplits(address(token), tokenFees);
//     }

//     function test_claimFees_pullPaymentMultipleTokensPerContract(uint96 tokenFees, uint96 ethFees) public {
//         if(tokenFees == 0 || tokenFees > MAX_REVENUE) return;
//         if(ethFees == 0 || ethFees > MAX_REVENUE) return;

//         _initFeeClaimer(ETH, MockFeeGenerator.claimPullPayment.selector, transferOwnerFunc);

//         deal(feeContract, ethFees);
//         deal(address(token), feeContract, tokenFees);

//         bytes memory ethClaimData = abi.encodeWithSelector(MockFeeGenerator.claimPullPayment.selector,  ETH);
//         assertEq(ethFees, claimer.claimFees(feeContract, ETH, ethClaimData), 'invalid revenue amount claimed');
//         bytes memory tokenClaimData = abi.encodeWithSelector(MockFeeGenerator.claimPullPayment.selector,  token);
//         assertEq(tokenFees, claimer.claimFees(feeContract, address(token), tokenClaimData), 'invalid revenue amount claimed');

//         assertFeeContractSplits(ETH, ethFees);
//         assertFeeContractSplits(address(token), tokenFees);
//     }


//     function test_claimFees_updatesTokenReservesOnMultipleClaims(uint256 _revenue) public {
//         uint256 totalFees;
//         uint256 ownerTokens;
//         uint256 operatorTokens;
//         uint8 revenueSplit = 70;
//         _initFeeClaimer(ETH, claimPushPaymentFunc, transferOwnerFunc);

//         uint256 maxPerRoundFees = MAX_REVENUE * 2;
//         while(totalFees < type(uint256).max - maxPerRoundFees) {
//             uint256 revenue = bound(_revenue, MAX_REVENUE / 20, maxPerRoundFees);
//             emit log_named_uint(' -- New Fees -- ', revenue);
//             deal(address(token), address(claimer), revenue);
            
//             bytes memory claimData = abi.encodeWithSelector(claimPushPaymentFunc,  token);
//             uint256 claimed = claimer.claimFees(feeContract, address(token), claimData);
            
//             uint256 spigotBalance = token.balanceOf(address(claimer));
            
//             (uint256 maxFees, uint256 overflow) = getMaxFees(revenue);
//             uint256 expectedOwnerTokens = maxFees * revenueSplit / 100;
//             uint256 expectedOperatorTokens = maxFees - expectedOwnerTokens;

//             assertEq(token.balanceOf(address(claimer)), totalFees + revenue);

//             assertEq(
//                 claimer.getOwnerTokens(address(token)),
//                 ownerTokens + expectedOwnerTokens,
//                 'Invalid Owner amount for claimer revenue'
//             );
//             assertEq(
//                 claimer.getOperatorTokens(address(token)),
//                 operatorTokens + expectedOperatorTokens,
//                 'Invalid Operator amount for claimer revenue'
//             );

//             assertEq(
//                 spigotBalance,
//                 totalFees + revenue, // revenue over max stays in contract unnaccounted
//                 'FeeClaimer balance vs Owner + Operator + overflow mismatch'
//             );

//             assertEq(
//                 revenue,
//                 claimed + overflow, // revenue over max stays in contract unnaccounted
//                 'total revenue vs overflow + claimed mismatch'
//             );

//             // update teeting vars with totals
//             ownerTokens += expectedOwnerTokens;
//             operatorTokens += expectedOperatorTokens;
//             totalFees += claimed + overflow;

//             emit log_named_uint(' -- Total Fees -- ', totalFees);
//         }
//     }


//     function test_claimFees_emitsClaimFeesEvent(uint256 _revenue) public {
//         uint256 revenue = bound(_revenue, 1_500 * 10**18, MAX_REVENUE);
//         _initFeeClaimer(ETH, MockFeeGenerator.claimPullPayment.selector, transferOwnerFunc);

//         deal(feeContract, revenue);
//         deal(address(token), feeContract, revenue);

//         uint256 tokenFeesForOwner = (revenue * claimer.ownerSplit()) / 100;
//         vm.expectEmit(true, false, false, true, address(claimer));
//         emit FeeClaimer.ClaimFees(feeContract, address(token), revenue, tokenFeesForOwner);
//         bytes memory tokenClaimData = abi.encodeWithSelector(MockFeeGenerator.claimPullPayment.selector, token);
//         assertEq(revenue, claimer.claimFees(feeContract, address(token), tokenClaimData), 'invalid token revenue amount claimed');
        
//         uint256 ethFeesForOwner = (revenue * claimer.ownerSplit()) / 100;
//         vm.expectEmit(true, false, false, true, address(claimer));
//         emit FeeClaimer.ClaimFees(feeContract, ETH, revenue, ethFeesForOwner);
//         bytes memory ethClaimData = abi.encodeWithSelector(MockFeeGenerator.claimPullPayment.selector, ETH);
//         assertEq(revenue, claimer.claimFees(feeContract, ETH, ethClaimData), 'invalid ETH revenue amount claimed');

//         assertFeeContractSplits(ETH, revenue);
//         assertFeeContractSplits(address(token), revenue);
//     }

//     // Claim escrow

//     function test_claimOwnerTokens_AsOwner(uint256 _revenue) public {
//         uint256 revenue = bound(_revenue, 1_500 * 10**18, MAX_REVENUE);
//         // send revenue and claim it
//         deal(address(token), address(claimer), revenue);
//         bytes memory claimData;
//         claimer.claimFees(feeContract, address(token), claimData);
//         assertFeeContractSplits(address(token), revenue);

//         uint256 claimed = claimer.claimOwnerTokens(address(token));
//         (uint256 maxFees,) = getMaxFees(revenue);

//         assertEq(
//             (maxFees * claimer.ownerSplit()) / 100,
//             claimed,
//             "Invalid escrow claimed"
//         );
//         assertEq(
//             token.balanceOf(owner),
//             claimed,
//             "Claimed escrow not sent to owner"
//         );
//     }

//     function test_claimOwnerTokens_AsNonOwner() public {
//         // send revenue and claim it
//         deal(address(token), address(claimer), 10**10);
//         bytes memory claimData;
//         claimer.claimFees(feeContract, address(token), claimData);

//         hoax(address(0xdebf));
//         vm.expectRevert(FeeClaimer.CallerAccessDenied.selector);

//         // claim fails
//         claimer.claimOwnerTokens(address(token));
//     }

//     function test_claimOperatorTokens_AsOperator(uint256 totalFees, uint8 _split) public {
//         if(totalFees <= 50|| totalFees > MAX_REVENUE) return;
//         if (_split > 99 || _split < 0) return;
        
//         uint256 ownerTokens = totalFees * claimer.ownerSplit() / 100;
  

        

//         _initFeeClaimer(address(token), claimPushPaymentFunc, transferOwnerFunc);

//         // console.log(claimer.ownerSplit());
//         // console.log(totalFees);
        
        
//         // send revenue and claim it
//         deal(address(token), address(claimer), totalFees);
//         bytes memory claimData;
//         claimer.claimFees(feeContract, address(token), claimData);

//         uint256 operatorTokens = claimer.getOperatorTokens(address(token));
        
        
        
//         assertFeeContractSplits(address(token), totalFees);
        

//         vm.prank(operator);
//         uint256 claimed = claimer.claimOperatorTokens(address(token));
//         (uint256 maxFees,) = getMaxFees(totalFees);




//        // assertEq(roundingFix > 1, false, "rounding fix is greater than 1");
//         assertEq(operatorTokens  , claimed, "Invalid escrow claimed");
//         assertEq(token.balanceOf(operator), claimed, "Claimed escrow not sent to owner");
//     }

//     function test_claimOperatorTokens_AsNonOperator() public {
//         // send revenue and claim it
//         deal(address(token), address(claimer), 10**10);
//         bytes memory claimData;
//         claimer.claimFees(feeContract, address(token), claimData);

//         hoax(address(0xdebf));
//         vm.expectRevert(FeeClaimer.CallerAccessDenied.selector);

//         // claim fails
//         claimer.claimOperatorTokens(address(token));
//     }

//     // Unclaimed Fees no longer affectbs FeeClaimer behaviour. Keep for docs
//     function test_claimEscrow_UnclaimedFees() public {
//         // send revenue and claim it
//         // deal(address(token), address(claimer), MAX_REVENUE + 1);
//         // bytes memory claimData;
//         // claimer.claimFees(feeContract, address(token), claimData);
//         // vm.expectRevert(FeeClaimer.UnclaimedFees.selector);
//         // claimer.claimEscrow(address(token));       // reverts because excess tokens
//     }

//     function test_claimOwnerTokens_AllFeesClaimed() public {
//         // send revenue and claim it
//         deal(address(token), address(claimer), MAX_REVENUE + 1);
//         bytes memory claimData;
//         claimer.claimFees(feeContract, address(token), claimData); // collect majority of revenue
//         claimer.claimFees(feeContract, address(token), claimData); // collect remained

//         claimer.claimOwnerTokens(address(token));       // should pass bc no unlciamed revenue
//     }

//     function test_claimEscrow_UnregisteredToken() public {
//         // create new token and send push payment
//         MockToken fakeToken = new MockToken();
//         fakeToken.mint(address(claimer), 10**10);

//         bytes memory claimData;
//         vm.expectRevert(FeeClaimer.NoFees.selector);
//         claimer.claimFees(feeContract, address(token), claimData);

//         // will always return 0 if you can't claim revenue for token
//         // claimer.claimEscrow(address(fakeToken));
//     }

//     // FeeClaimer initialization

//     function test_addFeeContract_ProperSettings() public {
//         _initFeeClaimer(
//             address(token),
//             claimPullPaymentFunc,
//             transferOwnerFunc
//         );
//         (uint8 _split, bytes4 _claim, bytes4 _transfer) = claimer.getSetting(
//             feeContract
//         );

//         // assertEq(settings.token, _token);
//         assertEq(claimer.ownerSplit(), _split);
//         assertEq(settings.claimFunction, _claim);
//         assertEq(settings.transferOwnerFunction, _transfer);
//     }

//     function test_addFeeContract_OwnerSplit0To100(uint8 split) public {
//         // Split can only be 0-100 for numerator in percent calculation
//         if (split > 100 || split == 0) return;
//         _initFeeClaimer(
//             address(token),
//             claimPullPaymentFunc,
//             transferOwnerFunc
//         );
//         // assertEq(claimer.getSetting(feeContract).ownerSplit, split);
//     }

//     function test_addFeeContract_NoOwnerSplitOver100(uint8 split) public {
//         // Split can only be 0-100 for numerator in percent calculation
//         if (split <= 100) return;

//         feeContract = address(
//             new MockFeeGenerator(address(this), address(token))
//         );

//         settings = FeeClaimer.ClaimContract(
//             claimPushPaymentFunc,
//             transferOwnerFunc
//         );

//         vm.expectRevert(FeeClaimer.BadSetting.selector);

//         claimer.addFeeContract(address(feeContract), settings);
//     }

//     function test_addFeeContract_NoTransferFunc() public {
//         feeContract = address(
//             new MockFeeGenerator(address(this), address(token))
//         );

//         settings = FeeClaimer.ClaimContract(claimPullPaymentFunc, bytes4(0));

//         vm.expectRevert(FeeClaimer.BadSetting.selector);

//         claimer.addFeeContract(address(feeContract), settings);
//     }

//     function test_addFeeContract_TransferFuncParam(bytes4 func) public {
//         if (func == claimPushPaymentFunc) return;
//         _initFeeClaimer(address(token), claimPushPaymentFunc, func);

//         (, , bytes4 _transfer) = claimer.getSetting(address(feeContract));
//         assertEq(_transfer, func);
//     }

//     function test_addFeeContract_AsNonOwner() public {
//         hoax(address(0xdebf));
//         vm.expectRevert(FeeClaimer.CallerAccessDenied.selector);
//         claimer.addFeeContract(address(0xdebf), settings);
//     }

//     function test_addFeeContract_ExistingFeeContract() public {
//         vm.expectRevert(FeeClaimer.FeeContractSettingsExist.selector);
//         claimer.addFeeContract(feeContract, settings);
//     }

//     function test_addFeeContract_FeeContractAsFeeContract() public {
//         vm.expectRevert(FeeClaimer.InvalidFeeContract.selector);
//         claimer.addFeeContract(address(claimer), settings);
//     }

//     //  Updating
//     function test_updateOwnerSplit_AsOwner() public {
//         claimer.updateOwnerSplit(feeContract, 0);
//     }

//     function test_updateOwnerSplit_0To100(uint8 split) public {
//         if (split > 100) return;
//         assertTrue(claimer.updateOwnerSplit(feeContract, split));
//         (uint8 split_, , ) = claimer.getSetting(feeContract);
//         assertEq(split, split_);
//     }

//     function test_updateOwnerSplit_AsNonOwner() public {
//         vm.expectRevert(FeeClaimer.CallerAccessDenied.selector);
//         hoax(address(40));
//         claimer.updateOwnerSplit(feeContract, 0);
//     }

//     function test_updateOwnerSplit_Over100(uint8 split) public {
//         if (split <= 100) return;
//         vm.expectRevert(FeeClaimer.BadSetting.selector);
//         claimer.updateOwnerSplit(feeContract, split);
//     }

//     // Unclaimed Fees no longer affectbs FeeClaimer behaviour. Keep for docs
//     function test_updateOwnerSplit_UnclaimedFees() public {
//         // send revenue and dont claim
//         // deal(address(token), address(claimer), type(uint).max);
//         // // vm.expectRevert(FeeClaimer.UnclaimedFees.selector);
//         // claimer.updateOwnerSplit(feeContract, 0);     // reverts because excess tokens
//     }

//     // Operate()

//     function test_operate_NonWhitelistedFunction() public {
//         vm.prank(owner);
//         assertTrue(claimer.updateWhitelistedFunction(opsFunc, false));

//         vm.expectRevert(FeeClaimer.OperatorFnNotWhitelisted.selector);
//         vm.prank(operator);
//         claimer.operate(feeContract, abi.encodeWithSelector(opsFunc));
//     }

//     function test_operate_OperatorCanOperate() public {
//         vm.prank(owner);
//         assertTrue(claimer.updateWhitelistedFunction(opsFunc, true));
//         vm.prank(operator);
//         assertTrue(
//             claimer.operate(feeContract, abi.encodeWithSelector(opsFunc))
//         );
//     }

//     // should fail because the fn has not been whitelisted
//     function test_operate_ClaimFeesBadFunction() public {
//         _initFeeClaimer(
//             address(token),
//             claimPullPaymentFunc,
//             transferOwnerFunc
//         );

//         // we need to whitelist the transfer function in order to test the
//         // correct error condition
//         claimer.updateWhitelistedFunction(claimPullPaymentFunc, true);

//         bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
//         // vm.expectRevert(FeeClaimer.OperatorFnNotWhitelisted.selector);
//         vm.expectRevert(FeeClaimer.OperatorFnNotValid.selector);
//         vm.prank(operator);
//         claimer.operate(feeContract, claimData);
//     }

//     // should test trying to call operate on an existing transfer owner function
//     function test_operate_TransferOwnerBadFunction() public {
//         _initFeeClaimer(
//             address(token),
//             claimPullPaymentFunc,
//             transferOwnerFunc
//         );

//         // we need to whitelist the transfer function in order to test the
//         // correct error condition
//         claimer.updateWhitelistedFunction(transferOwnerFunc, true);

//         bytes memory transferData = abi.encodeWithSelector(
//             transferOwnerFunc,
//             address(operator)
//         );
//         vm.expectRevert(FeeClaimer.OperatorFnNotValid.selector);
//         vm.prank(operator);
//         claimer.operate(feeContract, transferData);
//     }

//     function test_operate_callFails() public {
//         _initFeeClaimer(
//             address(token),
//             claimPullPaymentFunc,
//             transferOwnerFunc
//         );

//         claimer.updateWhitelistedFunction(
//             MockFeeGenerator.doAnOperationsThingWithArgs.selector,
//             true
//         );

//         bytes memory operationsThingData = abi.encodeWithSelector(
//             MockFeeGenerator.doAnOperationsThingWithArgs.selector,
//             5
//         );

//         vm.expectRevert(FeeClaimer.OperatorFnCallFailed.selector);
//         vm.prank(operator);
//         claimer.operate(feeContract, operationsThingData);
//     }

//     function test_operate_AsNonOperator() public {
//         hoax(address(0xdebf));
//         bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
//         vm.expectRevert(FeeClaimer.CallerAccessDenied.selector);
//         claimer.operate(feeContract, claimData);
//     }

//     function test_operate_NonWhitelistFunc() public {
//         vm.expectRevert(FeeClaimer.OperatorFnNotWhitelisted.selector);
//         vm.prank(operator);
//         claimer.operate(feeContract, abi.encodeWithSelector(opsFunc));
//     }

//     function test_updateWhitelistedFunction_ToTrue() public {
//         assertTrue(claimer.updateWhitelistedFunction(opsFunc, true));
//         assertTrue(claimer.isWhitelisted(opsFunc));
//     }

//     function test_updateWhitelistedFunction_ToFalse() public {
//         assertTrue(claimer.updateWhitelistedFunction(opsFunc, false));
//         assertFalse(claimer.isWhitelisted(opsFunc));
//     }

//     // Release

//     function test_removeFeeContract() public {
//         (, , bytes4 transferOwnerFunc_) = claimer.getSetting(feeContract);
//         assertEq(bytes4(transferOwnerFunc), transferOwnerFunc_);

//         claimer.removeFeeContract(feeContract);

//         (, , bytes4 transferOwnerFunc__) = claimer.getSetting(feeContract);
//         assertEq(bytes4(0), transferOwnerFunc__);
//     }

//     function test_removeFeeContract_AsOperator() public {
//         claimer.updateOwner(address(0xdebf)); // random owner

//         assertEq(claimer.owner(), address(0xdebf));
//         assertEq(claimer.operator(), operator);

//         vm.expectRevert(FeeClaimer.CallerAccessDenied.selector);
//         claimer.removeFeeContract(feeContract);
//     }

//     function test_removeFeeContract_AsNonOwner() public {
//         hoax(address(0xdebf));
//         vm.expectRevert(FeeClaimer.CallerAccessDenied.selector);
//         claimer.removeFeeContract(feeContract);
//     }

//     // Unclaimed Fees no longer affectbs FeeClaimer behaviour. Keep for docs
//     function test_removeFeeContract_UnclaimedFees() public {
//         // // send revenue and dont claim
//         // deal(address(token), address(claimer), type(uint).max);
//         // vm.expectRevert(FeeClaimer.UnclaimedFees.selector);
//         // claimer.claimEscrow(address(token));       // reverts because excess tokens
//     }

//     // Access Control Changes
//     function test_updateOwner_AsOwner() public {
//         claimer.updateOwner(address(0xdebf));
//         assertEq(claimer.owner(), address(0xdebf));
//     }

//     function test_updateOperator_AsOperator() public {
//         vm.prank(operator);
//         claimer.updateOperator(address(0xdebf));
//         assertEq(claimer.operator(), address(0xdebf));
//     }

//     function test_updateOperator_AsOwner() public {
//         vm.prank(owner);
//         claimer.updateOperator(address(20));
//     }
    
//     function test_updateOwner_AsNonOwner() public {
//         hoax(address(0xdebf));
//         vm.expectRevert(FeeClaimer.CallerAccessDenied.selector);
//         claimer.updateOwner(owner);
//     }

//     function test_updateOwner_AsOperator() public {
//         hoax(operator);
//         vm.expectRevert(FeeClaimer.CallerAccessDenied.selector);
//         claimer.updateOwner(owner);
//     }

//     function test_updateOwner_NullAddress() public {
//         vm.expectRevert();
//         claimer.updateOwner(address(0));
//     }

//     function test_updateOperator_AsNonOperator() public {
//         hoax(address(0xdebf));
//         vm.expectRevert(FeeClaimer.CallerAccessDenied.selector);
//         claimer.updateOperator(operator);
//     }

//     function test_addFeeContract_feeClaimerIsInvalidFeeContract() public {
//         feeContract = address(new MockFeeGenerator(owner, address(new MockToken())));

//         settings = FeeClaimer.ClaimContract(bytes4(""), bytes4("1234"));

//         claimer = new FeeClaimer(); 
//         claimer.initialize(owner, operator);

//         vm.expectRevert(FeeClaimer.InvalidFeeContract.selector);
//         claimer.addFeeContract(address(claimer), settings);
//     }

//     function test_addFeeContract_revertsOnDuplicateFeeContract() public {
//         feeContract = address(new MockFeeGenerator(owner, address(new MockToken())));

//         settings = FeeClaimer.ClaimContract(bytes4(""), bytes4("1234"));

//         claimer = new FeeClaimer(); 
//         claimer.initialize(owner, operator);

//         claimer.addFeeContract(address(feeContract), settings);

//         FeeClaimer.ClaimContract memory altSettings = FeeClaimer.ClaimContract(bytes4(""), bytes4("1234"));
        
//         vm.expectRevert(FeeClaimer.FeeContractSettingsExist.selector);
//          claimer.addFeeContract(address(feeContract), altSettings);
//     }



//     // dummy functions to get interfaces for RSA and SPpigot

//     function claimFees(
//         address feeContract,
//         address token,
//         bytes calldata data
//     ) external returns (uint256 claimed) { return 0; }

//     function operate(address feeContract, bytes calldata data) external returns (bool) {
//         return  true;
//     }

//     // owner funcs

//     function claimOwnerTokens(address token) external returns (uint256 claimed) {
//         return 0;
//     }

//     function claimOperatorTokens(address token) external returns (uint256 claimed) {
//         return 0;
//     }

//     function addFeeContract(address feeContract, FeeClaimer.ClaimContract memory setting) external returns (bool) {
//         return  true;
//     }

//     function removeFeeContract(address feeContract) external returns (bool) {
//         return  true;
//     }

//     // stakeholder funcs

//     function updateOwnerSplit(address feeContract, uint8 ownerSplit) external returns (bool) {
//         return  true;
//     }

//     function updateOwner(address newOwner) external returns (bool) {
//         return  true;
//     }

//     function updateOperator(address newOperator) external returns (bool) {
//         return  true;
//     }

//     function updateWhitelistedFunction(bytes4 func, bool allowed) external returns (bool) {
//         return  true;
//     }

//     // Getters
//     // function owner() external view returns (address) {
//     //     return address(0);
//     // }

//     // function operator() external view returns (address) {
//     //     return address(0);
//     // }

//     function isWhitelisted(bytes4 func) external view returns (bool) {
//         return  true;
//     }

//     function getOwnerTokens(address token) external view returns (uint256) {
//         return 0;
//     }

//     function getOperatorTokens(address token) external view returns (uint256) {
//         return 0;
//     }

//     function getSetting(
//         address feeContract
//     ) external view returns (uint8 split, bytes4 claimFunc, bytes4 transferFunc) {
//         return (0, bytes4(0), bytes4(0));
//     }
// }

