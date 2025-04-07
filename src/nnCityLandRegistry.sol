pragma solidity ^0.8.26;

import {ERC721} from "solady/tokens/ERC721.sol";
import {EnumerableSetLib} from "solady/utils/EnumerableSetLib.sol";
import {GPv2Helper, GPv2Order} from "./lib/GPV2.sol";
import {IERC20x, INNETH} from "./Interfaces.sol";

// extr legl 
// staking to a property nor the initation of the sales process guarantees eventual ownership of the property
// possession of the NFT does not entitle you to any rights or ownership of the associate property.
// Only the entity that purchased the property and is listed on the deed has ownership and rights
// Individual Property owners may encode rights into the owning/operating entity of the property that gives NFT holders rights and/or ownership
// Only Niggano Land Management, subsidiary, or affiliate must have exclusive property managment entity for all _properties listed in the registry after purchase
// Define "The City" is one of the many entities that is responsible for the property and all associated costs and liabilities.
// The City is a legal entity registered in the appropriate jurisdiction with a the ability to do business, hold assetes, and enter into contracts.
// the debt can only be repaid via Payment in Kind when a perpetual usage right contract is signed between the lender and the city

contract NNCityLandRegistry is ERC721, GPv2Helper {
    using EnumerableSetLib for EnumerableSetLib.Uint256Set;
    using GPv2Order for GPv2Order.Data;

    uint64 public nextLotID; // max 18,446,744,073,709,551,615 lots
    INNETH immutable public nnETH;
    INNETH immutable public nnUSDC;
    IERC20x immutable public USDC;
    IERC20x immutable public WETH;
    address public curator;
    
    enum PropertyStatus { Delisted, Listed, Approved, Purchasing, Paying, Bought }
    struct Property {
        PropertyStatus status; // delisted, listed, purchasing, bought
        address city; // property manager for lot
        uint64 price; // Full price of property. max 184.5B USD w/ 8 decimals
        uint64 deposit; // Min stake to being purchase process
        uint256 buyer; // approved buyer
        bytes32 uri; // ipfs hash of property details. nn token gated.
        EnumerableSetLib.Uint256Set stakes; // Stake ids of all interest in this property
    }


    // function params for listing/updating a property
    struct ListingDetails {
        uint64 price; // Full price of property. max 184.5B USD w/ 8 decimals
        uint64 deposit; // Min stake to being purchase process
        bytes32 uri; // ipfs hash of property details. nn token gated.
    }

    struct Stake {
        address nnToken;
        uint128 stakeAmount;
    }

    mapping(uint256 => Property) internal _properties;
    mapping(uint256 => Stake) public stakes;
    mapping(address => uint256) public cityConfigs;

    event StakeLot(uint64 lotID, address staker, address nnToken, uint128 stakeAmount);
    event StakeIncreased(uint256 stakeID, uint128 stakeAmount);
    event UnstakeLot(uint256 stakeID);
    event ListProperty(uint64 lotID);
    event CancelPurchase(uint64 lotID);
    event PropertyDelisted(uint64 lotID);
    event ProcessPropertyPayment(uint64 lotID);
    event ApproveBuyer(uint64 lotID, uint256 stakeID);

    error InvalidCity();
    error InvalidStakeAmount();
    error InvalidNNToken();
    error AlreadyInitialized();
    error InactiveProperty();
    error OwnershipNotFinalized();
    error NotCurator();
    error PropertyNotForSale();
    error StakeDoesNotExist();


    constructor(address _nnETH, address _nnUSDC, address _curator) ERC721() {
        nnETH = INNETH(_nnETH);
        nnUSDC = INNETH(_nnUSDC);
        USDC = nnUSDC.reserveToken();
        WETH = nnETH.reserveToken();
        curator = _curator;
    }

    // TODO attack vectors to test. 
    // 1. buyer stake approved then transfers stake token
    // 3. stake NFT transferred during purchasing process (not our problem, we've already transferred the cash out cant withdraw)
    
    // TODO invariants
    // pre initiateOrder
    // nnETH balance == all staked amounts
    // nnUSDC balance == all staked amounts
    // post confirmSettlement
    // nnETH balance == all staked amounts - buyer stake amount
    // nnUSDC balance == all staked amounts - buyer stake amount
    //

    function initialize(address _nnETH, address _nnUSDC) public {
        if(address(nnETH) != address(0)) revert AlreadyInitialized();

    }

    function name() public view virtual override returns (string memory) {
        return  "Network Nations Land Registry";
    }

    function symbol() public view virtual override  returns (string memory) {
        return  "NNLR";
    }

    function tokenURI(uint256 id) public view virtual override returns (string memory) {
        // is property different format than stake?
        return "_TODO_";
    }


    function addCity(address city, uint256 config) public {
        if(msg.sender != curator) {
            revert NotCurator();
        }
        cityConfigs[city] = config;
    }

    function _beforeTokenTransfer(address from, address to, uint256 id) internal virtual override {

        // TODO need to think thru property + stake transfer combos
        // if property transferred, then owner stake transferred too?
        // if owner stake transferred, then property transferred too?

        if(stakes[id].nnToken != address(0)) {
            // is stake NFT
        //     revert StakesNonTransferrable();
        // ?? if stakes transferrable then if lending to a stake lender (contract) needs to be able to handle receiving the property NFT if stake is accepted
        } else {
            // is property NFT
            if(_properties[id].status == PropertyStatus.Delisted) {
                revert InactiveProperty();
            }

            if(_properties[id].status == PropertyStatus.Purchasing) {
                revert OwnershipNotFinalized();
            }
        }
    }

    function stake(uint64 lotID, address owner, address nnToken, uint128 stakeAmount) public returns(uint256) {
        if(stakeAmount == 0) {
            revert InvalidStakeAmount();
        }
        if(nnToken != address(nnETH) && nnToken != address(nnUSDC)) {
            revert InvalidNNToken();
        }
        if(_properties[lotID].status != PropertyStatus.Listed) {
            revert PropertyNotForSale();
        }
        uint256 stakeID = _constructStakeID(lotID, owner);

        if(stakes[stakeID].nnToken == address(0)) {
            _assertStakeValuation(lotID, address(nnToken), stakeAmount);
            IERC20x(nnToken).transferFrom(msg.sender, address(this), stakeAmount);

            stakes[stakeID] = Stake({ nnToken: address(nnToken), stakeAmount: stakeAmount });
            _mint(owner, stakeID);
            _properties[lotID].stakes.add(stakeID);
        }

        emit StakeLot(lotID, owner, address(nnToken), stakeAmount);
        return stakeID;
    }

    function increaseStake(uint256 stakeID, uint128 stakeAmount) public {
        if(_exists(stakeID)) {
            IERC20x(stakes[stakeID].nnToken).transferFrom(msg.sender, address(this), stakeAmount);
            // already staked, increasing bid
            stakes[stakeID].stakeAmount += stakeAmount;
            emit StakeIncreased(stakeID, stakeAmount);
        } else {
            revert StakeDoesNotExist();
        }
    }

    function unstake(uint64 lotID, uint256 stakeID, address to) public {
        // stake locked until buyer selected or city delists
        // TODO dont think we want this
        assert(_properties[lotID].status != PropertyStatus.Listed);
        // ensure stake matches correct lot
        assert(uint64(stakeID >> 64) == lotID);
         // cant unstake if you are purchasing the lot
        assert(_properties[lotID].buyer != stakeID);
        // allow anyone with NFT approval to unstake for delegated control
        assert(_isApprovedOrOwner(msg.sender, stakeID));

        // if stake actually existed then burn NFT and delete all data
        if(_properties[lotID].stakes.remove(stakeID)) {
            IERC20x(stakes[stakeID].nnToken).transfer(to, stakes[stakeID].stakeAmount);
            delete stakes[stakeID];
            _burn(stakeID);
            emit UnstakeLot(stakeID);
        }
    }

    function depositUSDCAndStake(uint64 lotID, address owner, uint128 stakeAmount) public returns(uint256) {
        USDC.approve(address(nnUSDC), stakeAmount);
        nnUSDC.depositWithPreference(stakeAmount, _properties[lotID].city, address(this));
        return stake(lotID, owner, address(nnUSDC), stakeAmount);
    }

    function depositETHAndStake(uint64 lotID, address owner) payable public returns(uint256) {
        if(msg.value > type(uint128).max) {
            revert InvalidStakeAmount();
        }
        WETH.deposit{value: uint128(msg.value)}();
        WETH.approve(address(nnETH), uint128(msg.value));
        nnETH.depositWithPreference(uint128(msg.value), _properties[lotID].city, address(this));
        return stake(lotID, owner, address(nnETH), uint128(msg.value));
    }

    /* property manager admin funcs */
    function listProperty(ListingDetails memory property) public returns (uint64) {
        _assertIsCity();
        // at least 100 USD to prevent replay attacks on cowswap order
        // even property is worth $0 in Japan
        // assert(property.deposit > 1e10);
        assert(property.price >= property.deposit);

        _properties[nextLotID] = Property({
            status: PropertyStatus.Listed,
            city: msg.sender,
            price: property.price,
            deposit: property.deposit,
            uri: property.uri,
            buyer: 0,
            stakes: EnumerableSetLib.Uint256Set(0)
        });

        // TODO mint NFT to city here? and _transfer in assignProperty?
        // lets city do more financialization while waiting for a buyer if they already own the property not sourcing capital

        emit ListProperty(nextLotID);
        uint64 lotID = nextLotID;
        nextLotID++;
        return lotID;
    }

    function updateListing(uint64 lotID, ListingDetails memory property) public {
        _assertCityJurisdiction(lotID);
        assert(_properties[lotID].status == PropertyStatus.Listed);
        _properties[lotID].price = property.price; // TODO test this doesnt overwrite everything just new fields
        _properties[lotID].deposit = property.deposit; // TODO test this doesnt overwrite everything just new fields
        _properties[lotID].uri = property.uri; // TODO test this doesnt overwrite everything just new fields
        emit ListProperty(lotID);
    }

    function delistProperty(uint64 lotID) public {
        _assertCityJurisdiction(lotID);
        assert(_properties[lotID].status == PropertyStatus.Listed);
        // TODO can it be delisted if purchasing? 
        // revokeProperty(lotID);
        _properties[lotID].status = PropertyStatus.Delisted;
        emit PropertyDelisted(lotID);
    }

    function cancelPurchase(uint64 lotID) public {
        _assertCityJurisdiction(lotID);
        assert(_properties[lotID].status == PropertyStatus.Purchasing);
        
        _revokeProperty(lotID);
        _properties[lotID].status = PropertyStatus.Listed;

        emit CancelPurchase(lotID);
    }


    function _assignProperty(uint64 lotID, uint256 stakeID) internal {
        _properties[lotID].buyer = stakeID;
        _mint(_ownerOf(stakeID), uint256(lotID));
    }
    
    function _revokeProperty(uint64 lotID) internal {
        _burn(uint256(lotID));
        _burn(_properties[lotID].buyer);
        _properties[lotID].buyer = 0;
        _properties[lotID].status = PropertyStatus.Listed;
        // TODO transfer stake back to them? shouldn't be codified bc maybe they violate terms
        // or only made deposit not full purchase
        // maybe allow callback contract call by city?
        // _onRevokeProperty(address termsContract); termsContract.onRevokeProperty(lotID);
    }
    

    /**
     * @notice Initiates purchase process for the lot. Only city owner can approve buyer
     *         Only city owner can approve buyer.
     * @ legal Unsecured 0% interest loan to the management company to complete your property purchase.
     *         Staker/buyer debt is repaid via a long-term usage rights to the property by holding the NNLandRegistry NFT associated with the lotID until the property is sold.
     *         Usage is the right to live in or occupy the property at their discretion,  modify the interior for personal use, provided changes do not reduce the property’s core value or require structural approval from the developer.
     *         The city is responsible for paying any property taxes, insurance, maintenance, utilities, and major repairs.
     * @param lotID property to purchase
     * @param stakeID owner of approved property stake
     */
    function approveBuyer(uint64 lotID, uint256 stakeID) public {
        _assertCityJurisdiction(lotID);
        assert(_properties[lotID].stakes.contains(stakeID));
        Stake memory patron = stakes[stakeID];

        // if staking in volatile asset then convert to stables before issuing loan
        // assume stable asset doesnt need valuation check
        if(patron.nnToken == address(nnETH)) {
            _assertStakeValuation(lotID, address(nnETH), patron.stakeAmount); // check received amount is sufficient for purchase to buy property
            initiateOrder(patron, lotID);
        }

        _properties[lotID].status = PropertyStatus.Approved;
        _properties[lotID].buyer = stakeID;
        // TODO burn stake ID? can now represent by lot NFT for future interactions. Cant be unstaked anyway since we've sold/transferred out assets
        // maybe make it non-transferable so a redemption/refund contract can still get delegated powers to burn it once refund issued?is         emit ApproveBuyer(lotID, stakeID);
    }

    function isValidSignature(bytes32 _tradeHash, bytes calldata _encodedOrder) external virtual override view returns (bytes4) {
        GPv2Order.Data memory _order = abi.decode(_encodedOrder, (GPv2Order.Data));
        
        // validate order params match order hash
        if(_order.hash(GPv2Order.COWSWAP_DOMAIN_SEPARATOR) != _tradeHash) {
            revert GPv2Order.InvalidTradeOrder();
        }

        // only approve orders created with initiateTrade()
        OrderMetadata memory orderParam = orderParams[_tradeHash];

        if(_properties[orderParam.ownerID].status != PropertyStatus.Approved) {
            // prevent replays on orders that have already been executed
            // assumes we call 
            revert GPv2Order.InvalidTradeOrder();
        }

        if(orderParam.deadline > block.timestamp || _order.validTo != orderParam.deadline) {
            revert GPv2Order.InvalidTradeDeadline();
        }
        if(orderParam.deadline > block.timestamp || _order.validTo != orderParam.deadline) {
            revert GPv2Order.InvalidTradeDeadline();
        }

        if(_order.appData != 0) {
            // ensure no malicious extra data e.g. sending excess surplus to another address
            revert GPv2Order.InvalidTradeAppData();
        }

        // TODO subsequent checks should be redundant if checking order hash already

        // tokens sent directly to city for loan
        if(_properties[orderParam.ownerID].city != GPv2Order.actualReceiver(_order, address(this))) {
            revert GPv2Order.InvalidTradeReceiver();
        }

        // confirm we are getting the amount of USDC we expect from the order when initiated
        // TODO deposit vs price ? 
        if(_order.buyAmount < nnUSDC.convertToDecimal(orderParam.minPrice, 8, nnUSDC.decimals())) {
            revert GPv2Order.InvalidTradePrice();
        }

        if(_order.feeAmount != 0) {
            // i think we need to allow fees but idk how much
            // pretty sure we need to incorporate app fee + solver fee 
            revert GPv2Order.InvalidTradeFee();
        }

        return GPv2Order.ERC_1271_MAGIC_VALUE;
    }

    // TODO just redploy milkman on base w/ chainlink its much simpler and more functionality + already audited and in prod
    // https://github.com/cowdao-grants/milkman/blob/main/DEPLOYMENTS.md
    // https://docs.cow.fi/cow-protocol/reference/contracts/core/settlement#orderuid
    function confirmSettlement(bytes calldata uid) public virtual override {
        // GPv2 docs say this may be deleted after order expiry. 
        // so we set a long deadline and validate price against time trade is initiated in initiateOrder

        (bytes32 tradeHash, ,) = abi.decode(uid, (bytes32, address, uint32));
        if(orderParams[tradeHash].deadline == 0) {
            revert GPv2Order.InvalidTradeOrder();
        }

        // TODO stakeID and decompose lotID
        uint256 stakeID = orderParams[tradeHash].ownerID;
        uint64 lotID = _getLotForStake(stakeID);
        if(_properties[lotID].status != PropertyStatus.Approved) {
            revert GPv2Order.InvalidTradeOrder();
        }

        // We set `partiallyFillable` to false so if price check in isValidSignature was accurate we have the full amount desired
        uint256 usdcBought = GPv2Order.settledAmount(uid, orderParams[tradeHash].deadline);
        if(usdcBought == 0) {
            revert GPv2Order.InvalidTradeOrder();
        }

        // TODO deposit vs price
        if(nnUSDC.convertToDecimal(usdcBought, nnUSDC.decimals(), 8) < _properties[lotID].price) {
            revert GPv2Order.InvalidTradeOrder();
        }
        
        // TODO what if usdcBought > 0 but < price? update stake but do not assign property? need to set lot.status == LISTED and delete buyer?
        uint256 buyer = _properties[lotID].buyer;
        _assignProperty(lotID, buyer);
        _properties[lotID].status = PropertyStatus.Purchasing;
        // update stake to reflect new token + balance
        stakes[_properties[lotID].buyer] = Stake({
            nnToken: address(nnUSDC),
            stakeAmount: uint128(usdcBought) // TODO send excess back to buyer?
        });

        orderParams[tradeHash].deadline = 0; // prevent replay if original owner transfers property NFT
        
        // TODO deploy RSA w/ 0 interest. deposit w/ shares to buyer?
        // lower annual taxes to amoritize as usage rights for 90d/yr for 100 yrs
        // basically better to not encode in smart contract and let city handle it offchain

        emit ProcessPropertyPayment(lotID);
    }

    function initiateOrder(
        Stake memory partron,
        uint64 lotID
    )
        public virtual
        returns(GPv2Order.Data memory) 
    {
        if(msg.sender != _properties[lotID].city) {
            revert InvalidCity();
        }
        // TODO just raw weth/usdc here? actually increases complexity bc have to track all 4 token balanecs instead of main 2. 
        // also harder to recover assets if a trade fails bc need to have separate logic path for finding failed trade and redepositing specific amount instead of having nnBalance already there.

        // not sure if we need to check balance, order would just fail.
        // might be an issue with approving an invalid order that could be exploited later
        // require(_sellAmount >= ERC20(_revenueToken).balanceOf(address(this)), "No tokens to trade");

        // call max so multiple orders dont override each other
        // WETH doesnt support increaseAllowance
        IERC20x(address(nnETH)).approve(GPv2Order.COWSWAP_SETTLEMENT_ADDRESS, type(uint256).max);

        uint32 deadline = uint32(block.timestamp + GPv2Order.MAX_TRADE_DEADLINE);

        // emit OrderInitiated(asset, _revenueToken, tradeHash, _sellAmount, _minBuyAmount, _deadline);
        GPv2Order.Data memory order = GPv2Order.Data({
            kind: GPv2Order.KIND_BUY,   // BUY lets us check `filledAmount` for actual received amount and we care more about received amount than tokens sold
            receiver: address(0),         // send tokens directly to city
            // TODO nice to do nnETH but then resolvers need to support it
            sellToken: address(nnETH),  // only sell volatile assets aka nnETH
            // TODO nice to do nnUSDC but then resolvers need to support it which is extra overhead
            buyToken: address(nnUSDC),    // only buy stables aka raw USDC
            sellAmount: partron.stakeAmount, // sell full stake amount
            // TODO deposit vs price
            buyAmount: _properties[lotID].price, // must buy at least property price
            feeAmount: 0, // TODO figure out fees owed
            validTo: deadline,
            appData: 0,                 // no custom data for isValidsignature
            partiallyFillable: false,  // only execute trade if we get full property amount
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });

        orderParams[order.hash(GPv2Order.COWSWAP_DOMAIN_SEPARATOR)] = OrderMetadata({
            ownerID: lotID,
            deadline: deadline,
            minPrice: uint128(nnETH.reserveAssetPrice())
        });

        // TODO add uid to event. abi.encodePacked(order.hash, address(this),deadline);
        // emit OrderInitiated(address(nnETH), address(nnUSDC), order.hash(GPv2Order.COWSWAP_DOMAIN_SEPARATOR), partron.stakeAmount, _properties[lotID].price, deadline);


        return order;
    }


    function getPropertyStatus(uint64 lotID) public view returns (PropertyStatus) {
        return _properties[lotID].status;
    }

    function _constructStakeID(uint64 lotID, address staker) internal view returns (uint256) {
        // extra 4 bytes in the middle for some kind of data?
        return uint256(lotID) << 64 | _properties[lotID].stakes.length(); // pull tests from b code
    }

    function _getLotForStake(uint256 stakeID) internal pure returns (uint64) {
        return uint64(stakeID >> 64); // pull tests from b code
    }

    // TODO implement _encode/_decode stakeID
    /**
    * @notice uint encode stake IDs to include lotID and owner
     * |----------------------------------------------------------------|
     * |stakerAddr 20 bytes |    empty 4 bytes     |   lotID 8 bytes    |
     * |----------------------------------------------------------------|
     *
     */
    function _encodeStakeID(uint32 lotID, address staker) public pure returns (uint256  result) {
        
        // lotID as last 4 bytes (shift 160 bits from end)
        assembly {
            result := shl(160, staker)
            result := or(result, shl(0, lotID))
        }
    }

    function _decodeStakeID(uint256 stakeID) public pure returns (uint32 lotID, address staker) {
        // get last 
        lotID = uint32(stakeID >> 64);
        staker = address(uint160(stakeID));
    }

    function _assertCityJurisdiction(uint64 lotID) internal view {
        assert(msg.sender == _properties[lotID].city);
    }

    function _assertIsCity() internal view {
        assert(cityConfigs[msg.sender] != 0);
    }

    function _assertStakeValuation(uint64 lotID, address nnToken, uint128 stakeAmount) internal view {
        assert(_properties[lotID].status == PropertyStatus.Listed);
        try INNETH(nnToken).reserveAssetPrice() returns (uint256 reservePrice) {
                // ensure stake at least matches listing price
                // TODO check vs deposit not full price
                if(INNETH(nnToken).convertToDecimal(stakeAmount * reservePrice, IERC20x(nnToken).decimals() + 8, 8) < _properties[lotID].price) {
                    revert InvalidStakeAmount();
                }
            } catch {
                revert("Invalid nnToken price feed");
            }
    }


    function properties(uint64 lotID) external view returns (Property memory) {
        return _properties[lotID];
    }

    function stakeCount(uint64 lotID) external view returns (uint256) {
        return uint256(_properties[lotID].stakes.length());
    }

    function includesStake(uint64 lotID, uint256 stakeID) external view returns (bool) {
        return _properties[lotID].stakes.contains(stakeID);
    }

}