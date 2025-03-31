pragma solidity ^0.8.26;

import {ERC721} from "solady/tokens/ERC721.sol";
import {EnumerableSetLib} from "solady/utils/EnumerableSetLib.sol";
import {GPv2Helper, GPv2Order} from "./lib/GPV2.sol";
import {IERC20x} from "./Interfaces.sol";

// extr legl 
// staking to a property nor the initation of the sales process guarantees eventual ownership of the property
// possession of the NFT does not entitle you to any rights or ownership of the associate property.
// Only the entity that purchased the property and is listed on the deed has ownership and rights
// Individual Property owners may encode rights into the owning/operating entity of the property that gives NFT holders rights and/or ownership
// Only Niggano Land Management, subsidiary, or affiliate must have exclusive property managment entity for all properties listed in the registry after purchase
// Define "The City" is one of the many entities that is responsible for the property and all associated costs and liabilities.
// The City is a legal entity registered in the appropriate jurisdiction with a the ability to do business, hold assetes, and enter into contracts.
// the debt can only be repaid via Payment in Kind when a perpetual usage right contract is signed between the lender and the city

contract NNCityLandRegistry is ERC721, GPv2Helper {
    uint64 nextLotID; // max 18,446,744,073,709,551,615 lots
    IERC20x immutable public nnETH;
    IERC20x immutable public nnUSDC;
    IERC20x immutable public USDC;
    
    enum PropertyStatus { Delisted, Listed, Approved, Purchasing, Bought }
    struct Property {
        PropertyStatus status; // delisted, listed, purchasing, bought
        address city; // property manager for lot
        uint64 price; // Full price of property. max 184.5B USD w/ 8 decimals
        uint64 deposit; // Min stake to being purchase process
        uint256 owningStakeID; // approved buyer
        bytes32 uri; // ipfs hash of property details. nn token gated.
        uint256[] stakes; // Stake ids of all interest in this property
        // EnumerableSetLib.Uint256Set[] stakes; // Stake ids of all interest in this property

    }

    // using EnumerableSetLib for Uint8Set;
    // using EnumerableSetLib for EnumerableSetLib.Uint256Set;

    // function params for listing/updating a property
    struct ListingDetails {
        uint64 price; // Full price of property. max 184.5B USD w/ 8 decimals
        uint64 deposit; // Min stake to being purchase process
        bytes32 uri; // ipfs hash of property details. nn token gated.
    }



    struct Stake {
        // todo add owner id to make transferrable
        address nnToken;
        uint128 stakeAmount;
    }

    mapping(uint256 => Property) public properties;
    mapping(uint256 => Stake) public stakes;
    mapping(address => uint256) public cityConfig; // uint encode something e.g. preferred nnToken + fee?


    constructor(address _nnETH, address _nnUSDC, address _USDC) ERC721() {
        nnETH = IERC20x(_nnETH);
        nnUSDC = IERC20x(_nnUSDC);
        USDC = IERC20x(_USDC);
    }

    function name() public view virtual override returns (string memory) {
        return  "NN Cities Land Registry";
    }

    function symbol() public view virtual override  returns (string memory) {
        return  "NNCLR";
    }

    function tokenURI(uint256 id) public view virtual override returns (string memory) {
        // if property different format than stake?
        // 
        return "";
    }

    event StakeLot(uint64 lotID, address staker, address nnToken, uint128 stakeAmount);
    event UnstakeLot(uint256 stakeID);
    event PropertyListed(uint64 lotID);
    event PurchaseCancelled(uint64 lotID);
    event PropertyDelisted(uint64 lotID);
    event PropertyPaymentProcessed(uint64 lotID);
    event BuyerApproved(uint64 lotID, address buyer);

    error InvalidCity();

    // TODO NFT functions.
    // function uri
    // function _transfer. if(stakes[stakeID]) revert. else if(properties[lotID].buyer) all gucci
    // function ownerOf() if(properties[lotID].buyer) address(uint160(properties[lotID].buyer)) else if(stakes[stakeID]) address(uint160(stakes[stakeID])) else revert
    
    function stake(uint64 lotID, address nnToken, uint128 stakeAmount) public returns(uint256) {
        assert(stakeAmount > 0);
        assert(nnToken == address(nnETH) || nnToken == address(nnUSDC));
        uint256 stakeID = _constructStakeID(lotID, msg.sender);

        if(stakes[stakeID].nnToken == address(0)) {
            _assertStakeValuation(lotID, nnToken, stakeAmount);
            stakes[stakeID] = Stake({ nnToken: nnToken, stakeAmount: stakeAmount });
            properties[lotID].stakes.add(stakeID);
        } else {
            // already staked, increasing bid
            stakes[stakeID].stakeAmount += stakeAmount;
        }

        // TODO technically could _mint NFT for ur stake too since can never clash with property NFT
        // have to think of usecase for it. would have to think thru use cases and logic flows for it
        // not much financialization uses since short term deposit until approved. 
        // makes it appear in wallet tho.

        emit StakeLot(lotID, msg.sender, nnToken, stakeAmount);
        return stakeID;
    }

    function unstake(uint64 lotID) public {
        // stake locked until buyer selected or city delists
        assert(properties[lotID].status != PropertyStatus.Listed);
        assert(msg.sender != address(properties[lotID].buyer));

        uint256 stakeID = _constructStakeID(lotID, msg.sender);
        IERC20x(stakes[stakeID].nnToken).transfer(msg.sender, stakes[stakeID].stakeAmount);
        delete stakes[stakeID];
        properties[lotID].stakes.remove(stakeID);
        // TODO _burn stake NFT

        emit UnstakeLot(stakeID);
    }

    function depositUSDCAndStake(uint64 lotID, uint128 stakeAmount) public {
        nnUSDC.reserveToken().approve(address(nnUSDC), stakeAmount);
        nnUSDC.depositWithPreference(stakeAmount, properties[lotID].city, address(this));
        return stake(lotID, nnUSDC, stakeAmount);
    }

    // function depositETHAndStake(uint64 lotID) payable public {
    // TODO NNLib.WETH
    //     WETH.deposit{value: msg.value}();
    //     nnETH.reserveToken().approve(nnETH, msg.value);
    //     nnETH.depositWithPreference(msg.value, properties[lotID].city, address(this));
    //     return stake(lotID, nnETH, msg.value);
    // }


    /* property manager admin funcs */
    function listProperty(ListingDetails memory property) public {
        assert(cityConfig[msg.sender] != 0);
        // at least 100 USD to prevent replay attacks on cowswap order
        // even property is worth $0 in Japan
        assert(property.price > 1e10);

        properties[nextLotID] = Property({
            status: PropertyStatus.Listed,
            city: msg.sender,
            price: property.price,
            deposit: property.deposit,
            uri: property.uri
        });

        emit PropertyListed(nextLotID);

        ++nextLotID;
    }

    function updateListing(uint64 lotID, ListingDetails memory property) public {
        assert(properties[lotID].city == msg.sender);
        properties[lotID] = property; // TODO test this doesnt overwrite everything just new fields
        emit PropertyListed(lotID);
    }

    function cancelPurchase(uint64 lotID) public {
        _assertCity(lotID);
        assert(properties[lotID].status = PropertyStatus.Purchasing);
        _burn(lotID, properties[lotID].buyer);

        properties[lotID].buyer = address(0);
        properties[lotID].status = PropertyStatus.Listed;
        emit PurchaseCancelled(lotID);
    }

    function delistProperty(uint64 lotID) public {
        _assertCity(lotID);
        assert(properties[lotID].status = PropertyStatus.Listed);
        // todo can it be delisted if purchasing? 
        // revokeProperty(lotID);
        properties[lotID].status = PropertyStatus.Delisted;
        emit PropertyDelisted(lotID);
    }

    function _assignProperty(uint64 lotID, address buyer) internal {
        properties[lotID].buyer = buyer;
        _mint(lotID, buyer);
    }
    
    function revokeProperty(uint64 lotID) internal {
        if(properties[lotID].buyer != address(0)) {
            _burn(lotID, properties[lotID].buyer);
            properties[lotID].buyer = address(0);
            // TODO transfer stake back to them? shouldn't be codified bc maybe they violate terms
            // maybe allow callback contract call by city?
            // _onRevokeProperty(address termsContract); termsContract.onRevokeProperty(lotID);
        }
    }
    

    /**
     * @notice Initiates purchase process for the lot. Only city owner can approve buyer
     *         Only city owner can approve buyer.
     * @ legal  Unsecured 0% interest loan to the management company to complete your property purchase.
     *         Staker/buyer is granted perpetual usage rights to the property  by holding the NNLandRegistry NFT associated with the lotID until the property is sold.
     *         Usage is the right to live in or occupy the property at their discretion,  modify the interior for personal use, provided changes do not reduce the property’s core value or require structural approval from the developer.
     TODO revise, city owns property
     *         The NFT holder is responsible for routine maintenance and utility cost and any violations of the property’s deed restrictions, with The City covering major repairs (e.g., roof replacement).
     *         The city is responsible for any property taxes and insurance.
     * @param lotID property to purchase
     * @param buyer owner of approved property stake
     */
    function approveBuyer(uint64 lotID, address buyer) public {
        _assertCity(lotID);
        uint256 stakeID = _constructStakeID(lotID, buyer);
        assert(properties[lotID].stakes.contains(stakeID));
        Stake memory stake = stakes[stakeID];

        // if staking in volatile asset then convert to stables before issuing loan
        // assume stable asset doesnt need valuation check
        if(stake.nnToken == nnETH) {
            _assertStakeValuation(lotID, nnETH, stake.stakeAmount); // check received amount is sufficient for purchase to buy property
            initiateOrder(lotID, stake);
        }

        properties[lotID].status = PropertyStatus.Approved;
        properties[lotID].buyer = buyer;

        emit BuyerApproved(lotID, buyer);
    }

    function isValidSignature(bytes32 _tradeHash, bytes calldata _encodedOrder) external virtual override view returns (bytes4) {
        GPv2Order.Data memory _order = abi.decode(_encodedOrder, (GPv2Order.Data));
        
        // validate order params match order hash
        if(_order.hash(GPv2Order.DOMAIN_SEPARATOR) != _tradeHash) {
            revert GPv2Order.InvalidTradeOrder();
        }

        // only approve orders created with initiateTrade()
        Order memory orderParam = orderParams[_tradeHash];

        if(properties[orderParam.lotID].status != PropertyStatus.Approved) {
            // prevent replays on orderes that have already been executed
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
        if(properties[orderParam.lotID].city != GPv2Order.actualReceiver(_order, address(this))) {
            revert GPv2Order.InvalidTradeReceiver();
        }

        // TODO deposit vs price
        if(_order.buyAmount < nnUSDC.convertToDecimal(orderParam.price, 8, nnUSDC.decimals())) {
            revert GPv2Order.InvalidTradePrice();
        }

        if(_order.feeAmount != 0) {
            // i think we need to allow fees but idk how much
            // pretty sure we need to incorporate app fee + solver fee 
            revert GPv2Order.InvalidTradeFee();
        }

        return GPv2Order.ERC_1271_MAGIC_VALUE;
    }


    // https://docs.cow.fi/cow-protocol/reference/contracts/core/settlement#orderuid
    function confirmSettlement(bytes calldata uid) public virtual override {
        // GPv2 docs say this may be deleted after order expiry. 
        // so we set a long deadline and validate price against time trade is initiated in isValidSignature

        (bytes32 tradeHash, ,) = abi.decode(uid, (bytes32, address, uint32));
        if(orderParams[tradeHash].deadline == 0) {
            revert GPv2Order.InvalidTradeOrder();
        }

        uint32 lotID = orderParams[tradeHash].lotID;
        if(properties[lotID].status != PropertyStatus.Approved) {
            revert GPv2Order.InvalidTradeOrder();
        }

        // We set `partiallyFillable` to false so if price check in isValidSignature was accurate we have the full amount desired
        uint256 usdcBought = GPv2Order.settledAmount(uid);
        if(usdcBought == 0) {
            revert GPv2Order.InvalidTradeSettled();
        }

        // TODO deposit vs price
        if(nnUSDC.convertToDecimal(usdcBought, nnUSDC.decimals(), 8) < properties[lotID].price) {
            revert GPv2Order.InvalidTradeSettled();
        }
        
        // TODO what if usdcBought > 0 but < price? update stake but do not assign property? need to set lot.status == LISTED and delete buyer?
        address buyer = properties[lotID].buyer;
        _assignProperty(lotID, buyer);
        properties[lotID].status = PropertyStatus.Purchasing;
        stakes[properties[lotID].buyer] = Stake({
            nnToken: nnUSDC,
            stakeAmount: usdcBought
        });
        
        // TODO deploy RSA w/ 0 interest. deposit w/ shares to buyer?
        // lower annual taxes to amoritize as usage rights for 90d/yr for 100 yrs
        // basically better to not encode in smart contract and let city handle it offchain

        emit PropertyPaymentProcessed(lotID);
    }


    function initiateOrder(
        Stake memory stake,
        uint32 lotID
    )
        public virtual view
        returns(GPv2Order.Data memory) 
    {
        if(msg.sender != properties[lotID].city) {
            revert InvalidCity();
        }

        // not sure if we need to check balance, order would just fail.
        // might be an issue with approving an invalid order that could be exploited later
        // require(_sellAmount >= ERC20(_revenueToken).balanceOf(address(this)), "No tokens to trade");

        // call max so multiple orders dont override each other
        // we always specify a specific amount of nnTokens tokens to sell but WETH doesnt support increaseAllowance
        nnETH.approve(GPv2Order.COWSWAP_SETTLEMENT_ADDRESS, type(uint256).max);

        uint32 deadline = uint32(block.timestamp + GPv2Order.MAX_TRADE_DEADLINE);

        //bytes32 tradeHash = generateOrder(
        //     lot.city,
        //     address(nnUSDC),
        //     address(nnETH),
        //     stake.nnToken,
        //     stake.stakeAmount,
        //     lot.price, // TODO price vs deposit
        //     deadline
        // ).hash(GPv2Order.COWSWAP_DOMAIN_SEPARATOR);
        bytes32 tradeHash = GPv2Order.Data({
            kind: GPv2Order.KIND_BUY,   // BUY lets us check `filledAmount` for actual received amount and we care more about received amount than tokens sold
            receiver: address(0),         // send tokens directly to city
            sellToken: address(nnETH),  // only sell volatile assets aka nnETH
            // TODO would be nice to do nnUSDC but then resolveres need to support it which is extra overhead
            buyToken: address(nnUSDC),    // only buy stables aka raw USDC
            sellAmount: stake.stakeAmount, // sell full stake amount
            // TODO deposit vs price
            buyAmount: properties[lotID].price, // must buy at least property price
            feeAmount: 0, // TODO figure out fees owed
            validTo: deadline,
            appData: 0,                 // no custom data for isValidsignature
            partiallyFillable: false,  // only execute trade if we get full property amount
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });

        orderParams[tradeHash] = Order({
            ownerID: lotID,
            deadline: uint32(block.timestamp + GPv2Order.MAX_TRADE_DEADLINE),
            price: uint128(nnETH.getReservePrice())
        });

        // emit OrderInitiated(asset, _revenueToken, tradeHash, _sellAmount, _minBuyAmount, _deadline);
    }

    function _constructStakeID(uint64 lotID, address staker) internal pure returns (uint256) {
        // extra 4 bytes for some kind of data?
        return uint256(uint160(staker)) << 64; // pull tests from b code
    }

    function _assertCity(uint64 lotID) internal view {
        assert(msg.sender == properties[lotID].city);
    }

    function _assertStakeValuation(uint64 lotID, address nnToken, uint128 stakeAmount) internal view {
        assert(properties[lotID].status == PropertyStatus.Listed);
        try nnToken.reserveAssetPrice() returns (uint256 reservePrice) {
                // ensure stake at least matches listing price
                // TODO check vs deposit not full price
                assert(nnToken.convertToDecimal(stakeAmount * reservePrice, nnToken.decimals() + 8, 8) >= properties[lotID].price);
            } catch {
                revert("Invalid nnToken price feed");
            }
    }

}