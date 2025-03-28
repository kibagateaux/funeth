pragma solidity ^0.8.26;

import {ERC721} from "solady/tokens/ERC721.sol";
import {EnumerableSetLib} from "solady/utils/EnumerableSetLib.sol";
import {GPv2Helper} from "./lib/GPV2.sol";

// extr legl 
// staking to a property nor the initation of the sales process guarantees eventual ownership of the property
// possession of the NFT does not entitle you to any rights or ownership of the associate property.
// Only the entity that purchased the property and is listed on the deed has ownership and rights
// Individual Property owners may encode rights into the owning/operating entity of the property that gives NFT holders rights and/or ownership
// Only Niggano Land Management, subsidiary, or affiliate must have exclusive property managment entity for all properties listed in the registry after purchase
// Define "The City" is one of the many entities that is responsible for the property and all associated costs and liabilities.
// The City is a legal entity registered in the appropriate jurisdiction with a the ability to do business, hold assetes, and enter into contracts.

contract NNCityLandRegistry is ERC721, GPv2Helper {

    uint64 nextLotID; // max 18,446,744,073,709,551,615 lots
    address public nnETH;
    address public nnUSDC;
    
    enum PropertyStatus { Delisted, Listed, Purchasing, Bought }
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


    constructor() ERC721() {}

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
    event BuyerApproved(uint64 lotID, address buyer);

    // TODO NFT functions.
    // function uri
    // function _transfer. if(stakes[stakeID]) revert. else if(properties[lotID].buyer) all gucci
    // function ownerOf() if(properties[lotID].buyer) address(uint160(properties[lotID].buyer)) else if(stakes[stakeID]) address(uint160(stakes[stakeID])) else revert
    
    function stake(uint64 lotID, address nnToken, uint128 stakeAmount) public returns(uint256) {
        assert(stakeAmount > 0);
        assert(nnToken == nnETH || nnToken == nnUSDC);
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
        stakes[stakeID].nnToken.transfer(msg.sender, stakes[stakeID].stakeAmount);
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
    function listProperty(uint64 lotID, ListingDetails memory property) public {
        assert(cityConfig[msg.sender] != 0);
        // no checks on price/deposit e.g. deposit > price
        // and properties go for $0 in Japan

        properties[lotID] = Property({
            status: PropertyStatus.Listed,
            city: msg.sender,
            price: property.price,
            deposit: property.deposit,
            uri: property.uri
        });

        emit PropertyListed(lotID);
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
        emit BuyerApproved(lotID, buyer);
    }
    
    function revokeProperty(uint64 lotID) internal {
        if(properties[lotID].buyer != address(0)) {
            _burn(lotID, properties[lotID].buyer);
            properties[lotID].buyer = address(0);
        }
    }
    

    /**
     * @notice Initiates purchase process for the lot. Only city owner can approve buyer
     *         Only city owner can approve buyer.
     * @ legal  Unsecured 0% interest loan to the management company to complete your property purchase.
     *         Staker/buyer is granted perpetual usage rights to the property  by holding the NNLandRegistry NFT associated with the lotID until the property is sold.
     *         Usage is the right to live in or occupy the property at their discretion,  modify the interior for personal use, provided changes do not reduce the property’s core value or require structural approval from the developer.
     *         The NFT holder is responsible for routine maintenance and utility cost and any violations of the property’s deed restrictions, with The City covering major repairs (e.g., roof replacement).
     *         The city is responsible for any property taxes.
     *         The city is responsible for any property insurance.
     * @param lotID property to purchase
     * @param buyer owner of approved property stake
     */
    function approveBuyer(uint64 lotID, address buyer) public {
        _assertCity(lotID);
        uint256 stakeID = _constructStakeID(lotID, buyer);
        assert(properties[lotID].stakes.contains(stakeID));
        Stake memory stake = stakes[stakeID];
        _assertStakeValuation(lotID, stake.nnToken, stake.stakeAmount);

        _assignProperty(lotID, buyer);
        properties[lotID].status = PropertyStatus.Purchasing;
        // TODO nnToken.withdraw (stakeAmount) and trade stakeAmount to USDC in city address
        // assignProperty in trade callback

        emit BuyerApproved(lotID, buyer);
    }


    function confirmNNSwap() public {
        // cowswap callback function

        // override isTradeSignatureValid. 
        // super() + check chainlink ETH/USD price (only one way ETH->USD)

        // update owningStakeID to use nnUSDC and USDC amount received for refunding not ETH
        // decode order and ensure receiver is right city
        // 
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