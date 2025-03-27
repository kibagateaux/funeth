pragma solidity ^0.8.26;

import {ERC20} from "solady/tokens/ERC20.sol";
import {FeeClaimer} from "./FeeClaimer.sol";
import {INNETH, IERC20x, IAaveMarket, ReserveData, GPv2Order} from "../Interfaces.sol";

/**
* @title Revenue Share Agreemnt
* @author Kiba Gateaux
* @notice Allows a borrower with revenue streams collateralized in a Spigot to borrow against them from a single lender
* Lender is guaranteed a specific return but payments are variable based on revenue and % split between borrower and lender.
* Claims on revenue are tokenized as ERC20 at 1:1 redemption rate for the credit token being lent/repaid.
* All claim tokens are minted immediately to the lender and must be burnt to claim credit tokens. 
* Borrower or Lender can trade any revenue token at any time to the token owed to lender using CowSwap Smart Orders
* @dev - reference  https://github.com/charlesndalton/milkman/blob/main/contracts/Milkman.sol
*/
contract RevenueShareAgreement is ERC20, FeeClaimer {
    using GPv2Order for GPv2Order.Data;
    enum STATUS { INACTIVE, INIT, ACTIVE, REPAID }

    // TODO add network fee as param?
    uint16 internal constant NETWORK_FEE_BPS = 333; // origination fee 3.33%
    uint16 internal constant BPS_COEFFICIENT = 10_000; // offset bps decimals

    bytes4 internal constant ERC_1271_MAGIC_VALUE =  0x1626ba7e;
    bytes4 internal constant ERC_1271_NON_MAGIC_VALUE = 0xffffffff;
    uint32 internal constant MAX_TRADE_DEADLINE = uint32(1 days);
    /// @notice The contract that settles all trades. Must approve sell tokens to this address.
    /// @dev Same address across all chains
    address internal constant COWSWAP_SETTLEMENT_ADDRESS = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    /// @notice The settlement contract's EIP-712 domain separator. Milkman uses this to verify that a provided UID matches provided order parameters.
    /// @dev Same acorss all chains because settlement address is the same
    bytes32 internal constant COWSWAP_DOMAIN_SEPARATOR =
        0xc078f884a2676e1345748b1feace7b0abee5d00ecadb6e574dcdd109a63e8943;

    IERC20x internal WETH;
    STATUS public status;
    uint16 public redeemRate; // how many underlying redeemable for 1 RSA token
    address public borrower;
    address public asset;
    // denominated in asset
    uint256 public totalOwed; // amount claimable by depositors. exclusive of network fees
    uint256 public claimableAmount; // total repaid from revenue - total withdrawn by
    mapping(bytes32 => uint32) public orders; // deadline for order
    /// @dev Returns the name of the token.
    string internal _name;
    /// @dev Returns the symbol of the token.
    string internal _symbol;

    error InvalidPaymentSetting();
    error InvalidRevenueSplit();
    error CantSweepWhileInDebt();
    error DepositsFull();
    error NotRepaid();
    error ExceedClaimableTokens(uint256 claimable);
    error NotBorrower();
    error InvalidStatus();
    error InvalidBorrowerAddress();

    /// integration errors
    // cowswap integration
    error InvalidTradeId();
    error InvalidTradeData();
    error InvalidTradeDomain();
    error InvalidTradeDeadline();
    error InvalidTradeTokens();
    error InvalidTradeBalanceDestination();
    error MustBeSellOrder();
    error MustSellMoreThan0();
    // weth integration
    error WETHDepositFailed();
    error InvalidWETHDeposit();

    event OrderInitiated(
        address indexed asset,
        address indexed revenueToken,
        bytes32 tradeHash,
        uint256 sellAmount,
        uint256 minBuyAmount,
        uint32 validTo
    );
    event OrderFinalized(bytes32 indexed tradeHash);
    event Repay(uint256 amount);
    event Deposit(
        address indexed sender,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    constructor() ERC20() {}

    /***
    * @notice Initialize the RSA
    * @dev assumes deployed thru factory so credit network is msg.sender in FeeClaimer
    * @param _borrower - address of the borrower
    * @param _creditToken - address of the credit token
    * @param _revenueSplit - revenue split between borrower and lender
    * @param apr - rate of return on RSA financing in BPS. e.g. 600 = 6% more tokens claimable by depositors
    * @param _name - name of the RSA
    * @param _symbol - symbol of the RSA
     */
    function initialize(
        address _borrower,
        address _weth,
        address _creditToken,
        uint8 _revenueSplit,
        uint16 apr, 
        string memory __name,
        string memory __symbol
    ) external {
        if(status != STATUS.INACTIVE)   revert AlreadyInitialized();
        if(_borrower == address(0))     revert InvalidBorrowerAddress();
        if(_revenueSplit > MAX_SPLIT)   revert InvalidRevenueSplit();

        // ERC20 vars
        _name = string.concat("Revenue Share: ", __name);
        _symbol = string.concat("RSA-", __symbol);
        WETH = IERC20x(_weth);

        // RSA financial terms
        status = STATUS.INIT;
        borrower = _borrower;
        redeemRate = BPS_COEFFICIENT + apr;
        asset = _creditToken;
        ownerSplit = _revenueSplit;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
    * @notice Returns the total assets deposited into RSA
    * @dev ERC4626 function
    * @return total assets owned by RSA that are eventually claimable
    */
    function totalAssets() public view returns(uint256) {
        return totalOwed + claimableAmount;
    }

    /**
    * @notice Lets lenders deposit Borrower's requested loan amount into RSA and receive back redeemable shares of revenue stream
    * @dev callable by anyone if offer not accepted yet
    */
    function deposit(uint256 amount, address _receiver) public returns(bool) {
        if(status != STATUS.INIT) {
            revert InvalidStatus();
        }

        if(amount + totalSupply() > totalOwed) {
            // deposit would be greater than expected repay amount
            revert DepositsFull();
        }

        // issue RSA token to lender to redeem later. Mint > deposit to account for yield
        _mint(_receiver, amount);

        // extend credit to borrower
        ERC20(asset).transferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, _receiver, amount, amount); // unknown assets until completeTerm so default 1:1

        return true;
    }

    /**
    * @notice Lets Lender redeem their original tokens.
    * @param _amount - amount of RSA tokens to redeem @ 1:1 ratio for asset
    * @param _to - who to send claimed creditTokens to
    * @dev callable by anyone if offer not accepted yet
    */
    function redeem(uint256 _amount, address _to, address _owner) public returns(bool) {
        if(_amount > claimableAmount) {
            // _burn only checks their RSA token balance so
            // asset.transfer may move tokens we havent
            // properly accountted for as revenue yet.

            // If asset.balanceOf(this) > _amount but redeem() fails then call
            // repay() to account for the missing tokens.
            revert ExceedClaimableTokens(claimableAmount);
        }
        
        // check that caller has approval on _owner tokens
        if(msg.sender != _owner) {
            _spendAllowance(_owner, msg.sender, _amount);
        }

        // anyone can redeem not restricted to original lender
        claimableAmount -= _amount;
        _burn(_owner, _amount);

        // if RSA not actived then redeem at 1:1 ratio. else redeem at rate of return
        uint256 underlying = status == STATUS.INIT ? _amount : (_amount * redeemRate) / BPS_COEFFICIENT;
        ERC20(asset).transfer(_to, underlying);
        
        emit Withdraw(msg.sender, _to, _owner, underlying, _amount);
        return true;
    }


    /**
    * @notice Distributes all deposits to borrower and updates total returns + fees based on redeem rate
    * @dev callable by anyone.
    */
    function initiateTerm() external {
        if(status != STATUS.INIT) {
            revert InvalidStatus();
        }

        status = STATUS.ACTIVE;
        // can only call once full principal deposited
        uint256 deposited = ERC20(asset).balanceOf(address(this));
        uint256 baseReturn = (deposited * redeemRate) / BPS_COEFFICIENT;
        uint256 fee = (baseReturn * NETWORK_FEE_BPS) / BPS_COEFFICIENT;

        totalOwed = baseReturn + fee;
        address owner = owner();
        _mint(owner, fee);

        ERC20(asset).transfer(borrower, deposited);

        // emit
    }

    function cancel() external {
        if(status != STATUS.INIT) {
            revert InvalidStatus();
        }
        // enable 1:1 redemptions
        redeemRate = BPS_COEFFICIENT;
        _complete();
    }
    
    function completeTerm() external {
        if(status != STATUS.ACTIVE) {
            revert InvalidStatus();
        }
        _complete();
    }

    function _complete() internal {
        if(msg.sender != borrower) {
            revert NotBorrower();
        }

        if(totalOwed == 0) {
            status = STATUS.REPAID;
            // TODO anything else to do? Me thinks no
        } else {
            revert NotRepaid();
        }

        // TODO anything else to do? Me thinks not
    }

    /**
    * @notice Gives Credit Network the ability to trade any revenue token into the token owed by lenders
    *   trading access on factory allowing multiple methodlogies/traders for resistance.
    * @param _revenueToken - The token claimed from Spigot to sell for asset
    * @param _sellAmount - How many revenue tokens to sell. MUST be > 0
    * @param _minBuyAmount - Minimum amount of asset to buy during trade. Can be 0
    * @param _deadline - block timestamp that trade is valid until
    */
    function initiateOrder(
        address _revenueToken,
        uint256 _sellAmount,
        uint256 _minBuyAmount,
        uint32 _deadline
    ) external onlyOwner returns(bytes32 tradeHash) {
        if(status != STATUS.ACTIVE) {
            revert InvalidStatus();
        }

        _assertOrderParams(_revenueToken, _sellAmount, _minBuyAmount, _deadline);

        // not sure if we need to check balance, order would just fail.
        // might be an issue with approving an invalid order that could be exploited later
        // require(_sellAmount >= ERC20(_revenueToken).balanceOf(address(this)), "No tokens to trade");

        // call max so multiple orders/revenue streams with same token dont override each other
        // we always specify a specific amount of revenue tokens to sell but not all tokens support increaseAllowance
        ERC20(_revenueToken).approve(COWSWAP_SETTLEMENT_ADDRESS, type(uint256).max);

        tradeHash = generateOrder(
            _revenueToken,
            _sellAmount,
            _minBuyAmount,
            _deadline
        ).hash(COWSWAP_DOMAIN_SEPARATOR);
        // hash order with settlement contract as EIP-712 verifier
        // Then settlement calls back to our isValidSignature to verify trade

        orders[tradeHash] = uint32(block.timestamp + MAX_TRADE_DEADLINE);
        emit OrderInitiated(asset, _revenueToken, tradeHash, _sellAmount, _minBuyAmount, _deadline);
    }

     
    function isValidSignature(bytes32 _tradeHash, bytes calldata _encodedOrder) external view returns (bytes4) {
        GPv2Order.Data memory _order = abi.decode(_encodedOrder, (GPv2Order.Data));

        // if order created by RSA with initiateTrade() then auto-approve.
        if(orders[_tradeHash] != 0) {
            if(_order.validTo <= block.timestamp) {
                revert InvalidTradeDeadline();
            }

            return ERC_1271_MAGIC_VALUE;
        }

        // if not manually initiated or invalid order then revert
        return ERC_1271_NON_MAGIC_VALUE;
    }

    function _assertOrderParams(
        address _revenueToken,
        uint256 _sellAmount,
        uint256 _minBuyAmount,
        uint32 _deadline
    ) internal view {
        // require()s ordered by least gas intensive
        /// @dev https://docs.cow.fi/tutorials/how-to-submit-orders-via-the-api/4.-signing-the-order#security-notice
        require(_sellAmount != 0, "Invalid trade amount");
        require(totalOwed != 0, "No debt to trade for");
        require(_revenueToken != asset, "Cant sell token being bought");
        if(
            _deadline < block.timestamp ||
            _deadline > block.timestamp + MAX_TRADE_DEADLINE
        ) { 
            revert InvalidTradeDeadline();
        }
    }

    function generateOrder(
        address _sellToken, 
        uint256 _sellAmount, 
        uint256 _minBuyAmount, 
        uint32 _deadline
    )
        public view
        returns(GPv2Order.Data memory) 
    {
        return GPv2Order.Data({
            kind: GPv2Order.KIND_SELL,  // market sell revenue tokens, dont specify zamount bought.
            receiver: address(this),    // hardcode so trades are trustless 
            sellToken: _sellToken,
            buyToken: asset,      // hardcode so trades are trustless 
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

    /**
    * @notice Accounts for all credit tokens bought and updates debt and deposit balances
    * @dev callable by anyone.
    */
    function repay() external returns(uint256 claimed) {
        if(status != STATUS.ACTIVE) {
            revert InvalidStatus();
        }

        // The lender can only deposit once and lent tokens are NOT stored in this contract
        // so any new tokens are from revenue and we just check against current revenue deposits
        uint256 currBalance = ERC20(asset).balanceOf(address(this));
        uint256 newPayments = currBalance - claimableAmount;
        uint256 maxPayable = totalOwed; // cache in memory

        if(newPayments > maxPayable) {
            // if revenue > debt then repay all debt
            // and return excess to borrower
            claimableAmount = maxPayable;
            totalOwed = 0;
            emit Repay(maxPayable);
            return maxPayable;
            // borrower can now sweep() excess funds + returnFeeOwnership()
        } else {
            claimableAmount += newPayments;
            totalOwed -= newPayments; // TODO technically breaks 4626. totalOwed should be totalOwed + claimable
            emit Repay(newPayments);
            return newPayments;
        }
    }

    /**
    * @notice Lets Borrower redeem any excess revenue not needed to repay lenders.
    *         We assume any token in this contract is a revenue token and is collateral
    *         so only callable if no lender deposits yet or after RSA is fully repaid.
    *         Full token balance is swept to `_to`.
    * @dev   If you need to sweep raw ETH call wrapETH() first.
    * @param _token - amount of RSA tokens to redeem @ 1:1 ratio for asset
    * @param _to    - who to sweep tokens to
    */
    function sweep(address _token, address _to) external returns(bool) {
        if(msg.sender != borrower) {
            revert NotBorrower();
        }

        if(status != STATUS.REPAID) {
            revert CantSweepWhileInDebt();
        }

        uint256 balance = ERC20(_token).balanceOf(address(this));
        if(_token == asset) {
            // If all debt is repaid but lenders still havent claimed underlying
            // keep enough underlying for redemptions
            // NOTE: totalSupply == 0 until deposit() called
            ERC20(_token).transfer(_to, balance - totalAssets());
        } else {
            ERC20(_token).transfer(_to, balance);
        }

        
        return true;
    }   


    /**
    * @notice Wraps ETH to WETH (or other respective asset) because CoWswap only supports ERC20 tokens.
    *         This is easier than using their ETH flow.
    *         We dont allow native ETH as asset so any ETH is revenue and should be wrapped.
    * @dev callable by anyone. no state change, MEV, exploit potential
    * @return amount - amount of ETH wrapped 
    */
    function wrap() external returns(uint256 amount) {
        uint256 initialBalance = WETH.balanceOf(address(this));
        amount = address(this).balance;

        WETH.deposit{value: amount}();
        
        uint256 postBalance = WETH.balanceOf(address(this));
        if(postBalance - initialBalance != amount) {
            revert InvalidWETHDeposit();
        }
    }

    /**
    * @notice Sends credit network fees 
        Callable after all other tokens deposited
    * @param to - who to send fees to
    */
    function claimNetworkFees(address to) external {
        address owner = owner();
        if(msg.sender != owner) {
            revert Unauthorized();
        }

        // can only claim after everyone else claims for incentive alignment
        if(status != STATUS.REPAID) {
            revert NotRepaid();
        }

        redeem(balanceOf(owner), to, owner);
    }



    /**
    * @notice Lets Borrower reclaim their Spigot after paying off all their debt.
    * @dev    Only callable if RSA not initiated yet or after RSA is fully repaid.
    * @param _to    - who to give ownerhsip of Spigot to
    */
    function returnFeeOwnership(address _to) external virtual returns(bool) {
        if(msg.sender != borrower) {
            revert NotBorrower();
        }

        if(_to == address(0)) {
            revert NewOwnerIsZeroAddress();
        }

        // can reclaim if no lender has deposited yet, else
        // cannot Redeem spigot until the RSA has been repaid
        if(status != STATUS.REPAID) {
            revert CantSweepWhileInDebt();
        }

        _setOwner(_to); // give FeeClaimer ownership to borrower
    }
}
