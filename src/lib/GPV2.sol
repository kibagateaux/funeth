import {GPv2Order} from "../Interfaces.sol";

library GPv2Lib {
    // custom addifitions to lib from milkman contract
    bytes4 internal constant ERC_1271_MAGIC_VALUE =  0x1626ba7e;
    bytes4 internal constant ERC_1271_NON_MAGIC_VALUE = 0xffffffff;
    /// @notice The contract that settles all trades. Must approve sell tokens to this address.
    /// @dev Same address acorss all chains
    address internal constant COWSWAP_SETTLEMENT_ADDRESS = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    /* end slot 1 */
    /// @notice The settlement contract's EIP-712 domain separator. Milkman uses this to verify that a provided UID matches provided order parameters.
    /// @dev Same acorss all chains because settlement address is the same
    bytes32 internal constant COWSWAP_DOMAIN_SEPARATOR =
        0xc078f884a2676e1345748b1feace7b0abee5d00ecadb6e574dcdd109a63e8943;
    uint256 internal constant MAX_TRADE_DEADLINE = 1 days;


    error InvalidSpigotAddress();
    error InvalidBorrowerAddress();
    error InvalidTradeDomain();
    error InvalidTradeDeadline();
    error InvalidTradeTokens();
    error InvalidTradeBalanceDestination();
    error MustBeSellOrder();
}

abstract contract GPv2Helper {
    using GPv2Order for GPv2Order.Data;
    mapping(bytes32 => uint32) public orders; // deadline for order based on id

       
    function isValidSignature(bytes32 _tradeHash, bytes calldata _encodedOrder) external view returns (bytes4) {
        GPv2Order.Data memory _order = abi.decode(_encodedOrder, (GPv2Order.Data));

        // if order created by RSA with initiateTrade() then auto-approve.
        if(orders[_tradeHash] != 0) {
            if(_order.validTo <= block.timestamp) {
                revert GPv2Lib.InvalidTradeDeadline();
            }

            return GPv2Lib.ERC_1271_MAGIC_VALUE;
        }

        // if not manually initiated or invalid order then revert
        return GPv2Lib.ERC_1271_NON_MAGIC_VALUE;
    }


    function _assertOrderParams(
        address _sellToken,
        uint256 _sellAmount,
        uint256 _minBuyAmount,
        uint32 _deadline
    ) internal view {
        // require()s ordered by least gas intensive
        /// @dev https://docs.cow.fi/tutorials/how-to-submit-orders-via-the-api/4.-signing-the-order#security-notice
        require(_sellAmount != 0, "Invalid trade amount");
        if(
            _deadline < block.timestamp ||
            _deadline > block.timestamp + GPv2Lib.MAX_TRADE_DEADLINE
        ) { 
            revert GPv2Lib.InvalidTradeDeadline();
        }
    }   

    function generateOrder(
        address receiver, 
        address _buyToken, 
        address _sellToken, 
        uint256 _sellAmount, 
        uint256 _minBuyAmount, 
        uint32 _deadline
    )
        public view
        returns(GPv2Order.Data memory) 
    {
        return GPv2Order.Data({
            kind: GPv2Order.KIND_SELL,  // market sell specific amount of tokens, check amount bought if necessary.
            receiver: receiver,
            sellToken: _sellToken,
            buyToken: _buyToken,
            sellAmount: _sellAmount,
            buyAmount: _minBuyAmount,
            feeAmount: 0,
            validTo: _deadline,
            appData: 0,                 // no custom data for isValidsignature
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });
    }   
}