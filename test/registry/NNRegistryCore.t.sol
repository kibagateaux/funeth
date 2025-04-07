

import { NNETH } from "../../src/NNETH.sol";
import {GPv2Order} from "../../src/lib/GPV2.sol";
import {IERC20x, IAaveMarket, INNETH, IGPSettlement} from "../../src/Interfaces.sol";
import { NNETHBaseTest } from "../NNTokens/NNETHBaseTest.t.sol";
import {EnumerableSetLib} from "solady/utils/EnumerableSetLib.sol";
import { NNCityLandRegistry } from "../../src/NNCityLandRegistry.sol";

contract NNRegistryCoreTest is NNETHBaseTest {
    using EnumerableSetLib for EnumerableSetLib.Uint256Set;

    INNETH public nnUSDC;
    NNCityLandRegistry public registry;

    uint64 lotID;
    address curator = address(0x123);
    address city = address(0x456);

    function setUp() virtual override public {
        super.setUp();
        nnUSDC = new NNETH();
        nnUSDC.initialize(address(USDC), address(aave), address(debtWETH), "nnUSDC", "nnUSDC");
        registry = new NNCityLandRegistry(address(nnETH), address(nnUSDC), curator);
        lotID = registry.nextLotID();
        vm.prank(curator);
        registry.addCity(city, 1);    
    }

    function test_constructor_revertsOnInvalidNNTokens() public {
        // reset for init test
        vm.expectRevert(); // silent revert on to address with no reserveToken()
        new NNCityLandRegistry(address(0), address(nnUSDC), curator);
        vm.expectRevert(); // silent revert on to address with no reserveToken()
        new NNCityLandRegistry(address(nnETH), address(0), curator);
    }

    function test_constructor_setsNNValuesProperly() public {
        assertEq(address(registry.nnETH()), address(nnETH));
        assertEq(address(registry.nnUSDC()), address(nnUSDC));
    }

    function test_constructor_setsUnderlyingReserveTokensProperly() public {
        assertEq(address(registry.USDC()), address(USDC));
        assertEq(address(registry.WETH()), address(WETH));
    }

    function test_stake_revertsOnInvalidLotStatus() public {
        // reverts if lot is DELISTED
        assertEq(uint8(registry.getPropertyStatus(lotID)), uint8(NNCityLandRegistry.PropertyStatus.Delisted));
        vm.expectRevert(NNCityLandRegistry.PropertyNotForSale.selector);
        registry.stake(lotID, address(vm.addr(123)), address(nnETH), 100 ether);
        
        // reverts if lot is PURCHASING
        // list property and accept a staker
        uint64 newLotID = _listProperty();
        uint256 buyerStake = _stakeProperty(address(vm.addr(3939)), newLotID, 100 ether);
        vm.prank(city);
        registry.approveBuyer(newLotID, buyerStake);

        assertEq(uint8(registry.getPropertyStatus(newLotID)), uint8(NNCityLandRegistry.PropertyStatus.Approved));
        vm.expectRevert(NNCityLandRegistry.PropertyNotForSale.selector);
        vm.prank(vm.addr(999)); // new addr so new stake id on lot
        registry.stake(newLotID, address(vm.addr(123)), address(nnETH), 100 ether);
        
        // reverts if lot is BOUGHT
        // stub cowswap to show order settlement
        bytes[] memory prices = new bytes[](1);
        prices[0] = abi.encode(100 ether);
        bytes memory uid = abi.encodePacked(bytes32(0), address(registry), block.timestamp);
        vm.mockCalls(
            address(GPv2Order.COWSWAP_SETTLEMENT_ADDRESS), 
            abi.encodeWithSelector(IGPSettlement.filledAmount.selector, uid),
            prices
        );
        registry.confirmSettlement(uid);
        
        assertEq(uint8(registry.getPropertyStatus(newLotID)), uint8(NNCityLandRegistry.PropertyStatus.Purchasing));
        vm.expectRevert(NNCityLandRegistry.PropertyNotForSale.selector);
        registry.stake(newLotID, address(vm.addr(123)), address(nnETH), 100 ether);
    }
    
    function test_stake_revertsOnZeroStakeAmount() public {
        vm.expectRevert(NNCityLandRegistry.InvalidStakeAmount.selector);
        registry.stake(lotID, address(vm.addr(123)), address(nnUSDC), 0);
        vm.expectRevert(NNCityLandRegistry.InvalidStakeAmount.selector);
        registry.stake(lotID, address(vm.addr(123)), address(nnETH), 0);
    }   

    function test_stake_revertsOnInvalidNNToken() public {
        // reverts if nnToken is not nnETH or nnUSDC
        vm.expectRevert(NNCityLandRegistry.InvalidNNToken.selector);
        registry.stake(lotID, address(vm.addr(123)), address(this), 100 ether);
        vm.expectRevert(NNCityLandRegistry.InvalidNNToken.selector);
        registry.stake(lotID, address(vm.addr(123)), address(USDC), 100 ether);
    }   

    function test_stake_mintsStakeNFT() public {
        _listProperty();
        uint256 stakeID = _stakeProperty(address(vm.addr(3939)), lotID, 1 ether);
        assertEq(registry.ownerOf(stakeID), address(vm.addr(3939)));
        assertNotEq(registry.tokenURI(stakeID), "");
    }

    function test_stake_savesStakeData() public {
        _listProperty();
        uint256 stakeID = _stakeProperty(address(vm.addr(3939)), lotID, 1 ether);
        (address nnToken, uint128 stakeAmount) = registry.stakes(stakeID);
        assertEq(nnToken, address(nnETH));
        assertEq(stakeAmount, 1 ether);
    }

    function test_stake_emitsStakeEvent() public {
        _listProperty();
        _depositnnEth(address(vm.addr(3939)), 1 ether, true);
        vm.prank(address(vm.addr(3939)));
        nnETH.approve(address(registry), 1 ether);
        
        vm.expectEmit(true, true, true, true);
        emit NNCityLandRegistry.StakeLot(lotID, address(vm.addr(3939)), address(nnETH), 1 ether);
        vm.prank(address(vm.addr(3939)));
        registry.stake(lotID, address(vm.addr(3939)), address(nnETH), 1 ether);
    }

    function test_stake_addsStakeToLotList() public {
        _listProperty();
        assertEq(registry.stakeCount(lotID), 0);
        
        uint256 stakeID = _stakeProperty(address(vm.addr(3939)), lotID, 1 ether);
        assertEq(registry.stakeCount(lotID), 1);
        assertEq(registry.includesStake(lotID, stakeID), true);
    }

    function test_stake_revertsIfAmountUnderDeposit() public {
        _listProperty();
        vm.expectRevert(NNCityLandRegistry.InvalidStakeAmount.selector);
        _stakeProperty(address(vm.addr(3939)), address(nnETH), lotID, 1_001 gwei);
    }

    /// @notice incase smart contract mediates deposits on behalf of users
    function test_stake_userCanStakeMultipleTimesToSameProperty() public {
        _listProperty();
        uint256 stakeID = _stakeProperty(address(vm.addr(3939)), address(nnUSDC), lotID, 1_001 gwei);

        assertEq(registry.stakeCount(lotID), 1);
        assertEq(registry.includesStake(lotID, stakeID), true);

        uint256 newStakeID = _stakeProperty(address(vm.addr(3939)), address(nnUSDC), lotID, 1_001 gwei);

        assertEq(registry.stakeCount(lotID), 2);
        assertEq(registry.includesStake(lotID, stakeID), true); // still has first
        assertEq(registry.includesStake(lotID, newStakeID), true);

        assertEq(registry.ownerOf(stakeID), address(vm.addr(3939)));
        assertEq(registry.ownerOf(newStakeID), address(vm.addr(3939)));
    }

    function test_stake_userCanStakeMultipleTimesToDifferentProperty() public {
        _listProperty();
        uint256 stakeID = _stakeProperty(address(vm.addr(3939)), address(nnUSDC), lotID, 1_001 gwei);
        uint64 lot2 = _listProperty();
        uint256 newStakeID = _stakeProperty(address(vm.addr(3939)), address(nnUSDC), lot2, 1_001 gwei);

        (, uint128 stakeAmount1) = registry.stakes(stakeID);
        (, uint128 stakeAmount2) = registry.stakes(newStakeID);

        assertEq(stakeAmount1, 1_001 gwei);
        assertEq(stakeAmount2, 1_001 gwei);
        assertNotEq(stakeID, newStakeID);
        assertEq(registry.ownerOf(stakeID), address(vm.addr(3939)));
        assertEq(registry.ownerOf(newStakeID), address(vm.addr(3939))); 

        assertEq(registry.stakeCount(lotID), 1);
        assertEq(registry.includesStake(lotID, stakeID), true);
        assertEq(registry.includesStake(lotID, newStakeID), false);

        assertEq(registry.stakeCount(lot2), 1);
        assertEq(registry.includesStake(lot2, newStakeID), true);
        assertEq(registry.includesStake(lot2, stakeID), false);

    }

    function test_stake_transfersStakeAmountFromUserToRegistry() public {
        _listProperty();
        uint256 stakeID = _stakeProperty(address(vm.addr(3939)), address(nnETH), lotID, 1 ether);
        assertEq(nnETH.balanceOf(address(registry)), 1 ether);
        assertEq(nnETH.balanceOf(address(vm.addr(3939))), 0);
    }

        function test_increaseStake_revertsIfStakeDoesNotExist() public {
        vm.expectRevert(NNCityLandRegistry.StakeDoesNotExist.selector);
        registry.increaseStake(1, 1 ether);
    }

    function test_increaseStake_increasesAmountIfAlreadyExists() public {
        _listProperty();
        uint256 stakeID = _stakeProperty(address(vm.addr(3939)), address(nnETH), lotID, 1 ether);

        assertEq(registry.stakeCount(lotID), 1);

        _increaseStake(stakeID, 1 ether);
        (, uint128 stakeAmount) = registry.stakes(stakeID);
        assertEq(stakeAmount, 2 ether);
        assertEq(registry.ownerOf(stakeID), address(vm.addr(3939)));
        assertEq(registry.stakeCount(lotID), 1);
        assertEq(registry.includesStake(lotID, stakeID), true);
    }

    // unstake
    // computes the right stakeID
    // reverts if lot is in LISTED
    // succeeds if lot is DELISTED, PURCHASING, BOUGHT
    // reverts if msg.sender != lot.buyer
    // stakeAmount is transferred to msg.sender
    // stake object is deleted
    // stake is removed from lot list
    // NFT owner is address 0
    // unstake event is emitted
    // reverts if stakeID == lot buyer


    // depositAndStakeUSDC
    // reduces USDC balance of depositor
    // increases nnUSDC supply
    // increases nnUSDC balance of registry
    // stake event with correct params with city + registry as referrer
    // stake object with proper stats

    // depositAndStakeETH
    // reduces ETH balance of depositor
    // increases nnETH supply
    // increases nnETH balance of registry
    // stake event with correct params with city + registry as referrer
    // stake event object with proper stats


    /** city ops */

    // listProperty
    // properties[nextLotID] is always empty
    // reverts if deposit is 0
    // reverts if price less than deposit
    // reverts if msg.sender is not a registered city
    // inits property storage with proper valuies
    // incs nextLotID
    // emits event

    // upodateListing
    // reverts if status != Li sted
    // reverts if not listing city
    // updates properties in storage properly
    // emits event

    // delist property
    // reverts if status != LISTED
    // reverts if not listing city
    // updates properties in storage properly
    // emits event

    // approveBuyer
    // reverts if lot is in LISTED
    // 

    // cancelPurchase

    function _listProperty() internal returns (uint64) {
        vm.prank(city);
        return registry.listProperty(NNCityLandRegistry.ListingDetails({
            price: uint64(100 gwei),
            deposit: uint64(100 gwei),
            uri: bytes32(0)
        }));    
    }

    function _stakeProperty(address user, uint64 lot, uint128 amount) internal returns (uint256)  {
        return _stakeProperty(user, address(nnETH), lot, amount);
    }

    function _increaseStake(uint256 stakeID, uint128 amount) internal {
        (address nnToken, ) = registry.stakes(stakeID);
        nnETH = NNETH(nnToken);
        _depositnnEth(address(vm.addr(666)), amount, true);
        vm.prank(address(vm.addr(666)));
        nnETH.approve(address(registry), amount);
        vm.prank(address(vm.addr(666)));
        return registry.increaseStake(stakeID, amount);
    }

    function _stakeProperty(address user, address nnToken, uint64 lot, uint128 amount) internal returns (uint256)  {
        nnETH = NNETH(nnToken);
        _depositnnEth(user, amount, true);
        vm.prank(user);
        IERC20x(nnToken).approve(address(registry), amount);
        vm.prank(user);
        return registry.stake(lot, user, nnToken, amount);
    }
}