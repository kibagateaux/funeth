pragma solidity ^0.8.26;

import {ERC20} from "solady/tokens/ERC20.sol";
import {ERC4626} from "solady/tokens/ERC4626.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {GPv2Order} from "../lib/GPv2.sol";
import {IFunETH, IERC20x, IFunFactory, IAaveMarket, ReserveData} from "../Interfaces.sol";

// TODO add full solmate/ERC4626 functionality. Must functions super simple since static vars e.g. convertToShares, .

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
 
 // TODO make ERC4626 ERC4626
 contract FunFunding is ERC20, Ownable {
    // TODO inherit ERC4626 for easier calcs
    using GPv2Order for GPv2Order.Data;

    enum STATUS {
        INACTIVE,
        INIT,
        ACTIVE,
        REPAID,
        CANCELED
    }

    uint16 internal constant BPS_COEFFICIENT = 10_000; // offset bps decimals

    bytes4 internal constant ERC_1271_MAGIC_VALUE = 0x1626ba7e;
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
    // TODO add network fee as param/call from factory?
    uint16 public NETWORK_FEE_BPS; // origination fee 0.33%
    uint8 _decimals;
    STATUS public status;
    ///@notice  how many tokens minted per deposit to make redemptions 1:1 per RSA token. BPS decimals. e.g. 10_600 = 6% apr
    // TODO make a variable version for partial redeems not first come first serve.
    uint16 public rewardRate;
    address public asset;
    /// @notice FUN network curator/manager to send fees to
    address public networkFeeRecipient;
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
    error DepositsNotReached();
    error InvalidToken();
    error NotNetworkFeeRecipient();

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
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
    event TermInitiated(uint256 deposited, uint256 fees);

    constructor() ERC20() {}

    modifier whileActive() {
        if (status != STATUS.ACTIVE) {
            revert InvalidStatus();
        }
        _;
    }

    /**
     *
     * @notice Initialize the RSA
     * @dev assumes deployed thru factory so credit network is msg.sender in FeeClaimer
     * @param _borrower - address of the borrower
     * @param _creditToken - address of the credit token
     * @param _apr - rate of return on RSA financing in BPS. e.g. 600 = 6% more tokens claimable by depositors
     * @param __name - name of the RSA
     * @param __symbol - symbol of the RSA
     */
    function initialize(
        address _borrower,
        address _weth,
        address _creditToken,
        uint16 _apr,
        string memory __name,
        string memory __symbol
    ) external {
        if (status != STATUS.INACTIVE) revert AlreadyInitialized();
        if (_borrower == address(0)) revert InvalidBorrowerAddress();

        // ERC20 vars
        _name = string.concat("Revenue Share: ", __name);
        _symbol = string.concat("RSA-", __symbol);
        WETH = IERC20x(_weth);
        _decimals = IERC20x(_creditToken).decimals();

        // RSA financial terms
        status = STATUS.INIT;
        rewardRate = _apr + BPS_COEFFICIENT; // apr depositor reward to make redemptions 1:1 per apr;
        asset = _creditToken;
        NETWORK_FEE_BPS = IFunFactory(msg.sender).funLoanFee();
        // set FUN Treasury as fee recipient
        _initializeOwner(_borrower);
        networkFeeRecipient = IFunFactory(msg.sender).owner();
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /**
     * @notice Returns the amount of assets yet to be redeemed from RSA
     * @dev ERC4626
     * @return total assets owned by RSA that are eventually claimable
     */
    function totalAssets() public view returns (uint256) {
        return totalOwed + claimableAmount;
    }


    // TODO add mint() + withdraw() for 4626 compliance


    function mint(uint256 amount, address _receiver) external returns (uint256) {
        uint256 assets = (amount * BPS_COEFFICIENT) / rewardRate;
        _deposit(amount, assets, _receiver, _receiver);
        return assets;
    }

    /**
     * @notice __
     * @dev callable by anyone if offer not accepted yet
     * @return redeemable shares minted. more than amount based on apr for 1:1 redemption
     */
    function deposit(uint256 amount, address _receiver) public returns (uint256) {
        uint256 shares = (amount * rewardRate) / BPS_COEFFICIENT;
        _deposit(shares, amount, _receiver, _receiver);
        return shares;
    }

    function _deposit(uint256 shares, uint256 assets, address to, address receiver) internal {
        if (status != STATUS.INIT) {
            revert InvalidStatus();
        }

        // issue RSA token to lender to redeem later. Mint > deposit to account for yield
        // TODO i like 1:1 token ratio better than redeem rate. Update FunETH.lend() + repay() logic as necessary
        _mint(receiver, shares);

        ERC20(asset).transferFrom(msg.sender, address(this), assets);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @notice Lets Lender redeem their original tokens.
     * @param _amount - amount of shares to redeem @ 1:1 ratio for asset
     * @param _to - who to send claimed creditTokens to
     * @dev callable by anyone if round not closed by borrower yet.
     * @dev results vary based on status of round.
     * @return redeemable - underlying assets returned for shares
     */
    function redeem(uint256 _amount, address _to, address _owner) public returns (uint256) {
        uint256 assets = _amount;
        if (status == STATUS.INIT || status == STATUS.CANCELED) {
            // offset increase in shares for rewardRate if cancelled
            assets = (_amount * BPS_COEFFICIENT) / rewardRate;
        }
        _withdraw(_amount, assets, _to, _owner);
        return assets;
      
    }

    function withdraw(uint256 _amount, address _to, address _owner) external returns (uint256) {
        uint256 shares = _amount;
        if (status == STATUS.INIT || status == STATUS.CANCELED) {
            shares = (_amount * BPS_COEFFICIENT) / rewardRate;
        }
        _withdraw(shares, _amount, _to, _owner);
        return shares;
    }

    function _withdraw(uint256 shares, uint256 assets, address _to, address _owner) internal returns (uint256 redeemable) {

          if (status == STATUS.ACTIVE || status == STATUS.REPAID) {
            // _burn only checks their RSA token balance so asset.transfer may move tokens
            // we havent properly accounted for as revenue yet.
            // If asset.balanceOf(this) > _amount but redeem() fails then call
            // repay() to account for the missing tokens and redeem() again.
            if (assets > claimableAmount) {
                revert ExceedClaimableTokens(claimableAmount);
            }

            claimableAmount -= assets;
        }

        // @NOTE use _amount here as initial shares.
        // check that caller has approval on _owner tokens
        if (msg.sender != _owner) {
            _spendAllowance(_owner, msg.sender, shares);
        }
        _burn(_owner, shares);
        // if RSA not actived then redeem at 1:1 ratio. else redeem at rate of return
        ERC20(asset).transfer(_to, assets);


        emit Withdraw(msg.sender, _to, _owner, assets, shares);
    }



    /**
     * @notice Accounts for all credit tokens bought and updates debt and deposit balances
     * @dev callable by anyone.
     */
    function repay() external whileActive returns (uint256 claimed) {
        // The lender can only deposit once and lent tokens are NOT stored in this contract
        // so any new tokens are from fees and we just check against current fees deposits
        uint256 currBalance = ERC20(asset).balanceOf(address(this));
        uint256 newPayments = currBalance - claimableAmount;
        uint256 maxPayable = totalOwed; // cache in memory

        if (newPayments >= maxPayable) {
            // if fees > debt then repay all debt
            claimableAmount += maxPayable;
            totalOwed = 0;
            _completeTerm();
            emit Repay(maxPayable);
            return maxPayable;
            // borrower can now sweep() excess funds
        } else {
            claimableAmount += newPayments;
            totalOwed -= newPayments;
            emit Repay(newPayments);
            return newPayments;
        }
    }

    /**
     * @notice Distributes all deposits to borrower and updates total returns + fees based on redeem rate
     * @dev callable by anyone.
     */
    function initiateTerm() external onlyOwner {
        if (status != STATUS.INIT) {
            revert InvalidStatus();
        }
        // prevent reentrancy so before all external calls
        status = STATUS.ACTIVE;

        uint256 deposited = ERC20(asset).balanceOf(address(this));

        return _distribute(deposited);
    }

    function _distribute(uint256 deposited) internal {
        // TODO should be on initial value here or include rewardRate upscaling?
        // i think initial value like now is appropriate
        uint256 fee = (deposited * NETWORK_FEE_BPS) / BPS_COEFFICIENT;

        totalOwed = totalSupply() + fee; // supply = deposited * rewardRate
        _mint(networkFeeRecipient, fee);

        ERC20(asset).transfer(owner(), deposited);

        emit TermInitiated(deposited, fee);
    }

    function cancel() external onlyOwner {
        if (status != STATUS.INIT) {
            revert InvalidStatus();
        }

        status = STATUS.CANCELED;
        // TODO anything else to do? Me thinks no
    }

    function _completeTerm() internal {
        status = STATUS.REPAID;
        // TODO anything else to do? Me thinks no
    }

    /**
     * @notice Gives Credit Network the ability to trade any revenue token into the token owed by lenders
     *   trading access on factory allowing multiple methodlogies/traders for resistance.
     * @param _sellToken - The token claimed from Spigot to sell for asset
     * @param _sellAmount - How many revenue tokens to sell. MUST be > 0
     * @param _minBuyAmount - Minimum amount of asset to buy during trade. Can be 0
     * @param _deadline - block timestamp that trade is valid until
     */
    function initiateOrder(address _sellToken, uint256 _sellAmount, uint256 _minBuyAmount, uint32 _deadline)
        external
        whileActive
        returns (bytes32 tradeHash)
    {
        // TODO anyone or only owner+borrower? Depends how much we want to trust cowswap system vs counterparty risk

        _assertOrderParams(_sellToken, _sellAmount, _minBuyAmount, _deadline);

        // not sure if we need to check balance, order would just fail.
        // might be an issue with approving an invalid order that could be exploited later
        // require(_sellAmount >= ERC20(_sellToken).balanceOf(address(this)), "No tokens to trade");

        // call max so multiple orders/revenue streams with same token dont override each other
        // we always specify a specific amount of revenue tokens to sell but not all tokens support increaseAllowance
        ERC20(_sellToken).approve(COWSWAP_SETTLEMENT_ADDRESS, type(uint256).max);

        tradeHash = generateOrder(_sellToken, _sellAmount, _minBuyAmount, _deadline).hash(COWSWAP_DOMAIN_SEPARATOR);
        // hash order with settlement contract as EIP-712 verifier
        // Then settlement calls back to our isValidSignature to verify trade

        orders[tradeHash] = uint32(block.timestamp + MAX_TRADE_DEADLINE);
        emit OrderInitiated(asset, _sellToken, tradeHash, _sellAmount, _minBuyAmount, _deadline);
    }

    /**
     * @notice Verifies that a trade is valid and has not expired for CowSwap execution
     * @param _tradeHash - The hash of the trade that was initiated within generateOrder()
     * @param _encodedOrder - The encoded order by CowSwap network
     * @return ERC_1271_MAGIC_VALUE if the trade is valid. ERC_1271_NON_MAGIC_VALUE otherwise
     */
    function isValidSignature(bytes32 _tradeHash, bytes calldata _encodedOrder) external view returns (bytes4) {
        GPv2Order.Data memory _order = abi.decode(_encodedOrder, (GPv2Order.Data));

        // if order created by RSA with initiateTrade() then auto-approve.
        if (orders[_tradeHash] != 0) {
            // TODO simplify by moving order validation logic here so only 1 tx needed?. Depends if permissionless or not
            if (_order.validTo <= block.timestamp) {
                revert InvalidTradeDeadline();
            }

            return ERC_1271_MAGIC_VALUE;
        }

        // if not manually initiated or invalid order then revert
        return ERC_1271_NON_MAGIC_VALUE;
    }

    function _assertOrderParams(address _sellToken, uint256 _sellAmount, uint256 _minBuyAmount, uint32 _deadline)
        internal
        view
    {
        // require()s ordered by least gas intensive
        /// @dev https://docs.cow.fi/tutorials/how-to-submit-orders-via-the-api/4.-signing-the-order#security-notice
        require(_sellAmount != 0, "Invalid trade amount");
        require(totalOwed != 0, "No debt to trade for");
        require(_sellToken != asset, "Cant sell token being bought");
        if (_deadline < block.timestamp || _deadline > block.timestamp + MAX_TRADE_DEADLINE) {
            revert InvalidTradeDeadline();
        }
    }

    function generateOrder(address _sellToken, uint256 _sellAmount, uint256 _minBuyAmount, uint32 _deadline)
        public
        view
        returns (GPv2Order.Data memory)
    {
        return GPv2Order.Data({
            kind: GPv2Order.KIND_SELL, // market sell revenue tokens, dont specify zamount bought.
            receiver: address(this), // hardcode so trades are trustless
            sellToken: _sellToken,
            buyToken: asset, // hardcode so trades are trustless
            sellAmount: _sellAmount,
            buyAmount: _minBuyAmount,
            feeAmount: 0,
            validTo: _deadline,
            appData: 0, // no custom data for isValidsignature
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });
    }

    /**
     * @notice Lets Borrower redeem any excess fee not needed to repay lenders.
     *         We assume any token in this contract is a fee token and is collateral
     *         so only callable if no lender deposits yet or after RSA is fully repaid.
     *         Full token balance is swept to `_to`.
     * @dev   If you need to sweep raw ETH call wrapETH() first.
     * @param _token - amount of RSA tokens to redeem @ 1:1 ratio for asset
     * @param _to    - who to sweep tokens to
     */
    function sweep(address _token, address _to) external onlyOwner returns (bool) {
        if (status == STATUS.ACTIVE) revert InvalidStatus();

        if (_token == address(0)) {
            (bool success,) = owner().call{value: address(this).balance}("");
            assert(success);
        }

        uint256 balance = ERC20(_token).balanceOf(address(this));
        if (_token == asset) {
            // for native loan asset, diff calculations if it was not inited/cancelled or repaid.
            uint256 withholdings = status == STATUS.REPAID
                // If all debt is repaid but lenders still havent claimed underlying
                // keep enough underlying for redemptions
                ? claimableAmount
                // if INIT/CANCELED prevent user deposits from being swept
                : totalSupply(); // TODO if updating rewardRate scheme then update this
            
            if (withholdings > balance) {
                revert InsufficientBalance();
            }
            ERC20(_token).transfer(_to, balance - withholdings);
        } else {
            ERC20(_token).transfer(_to, balance);
        }
    }

    /**
     * @notice Wraps ETH to WETH (or other respective asset) because CoWswap only supports ERC20 tokens.
     *         This is easier than using their ETH flow.
     *         We dont allow native ETH as asset so any ETH is revenue and should be wrapped.
     * @dev callable by anyone. no state change, MEV, exploit potential
     * @return amount - amount of ETH wrapped
     */
    function wrap() external returns (uint256 amount) {
        uint256 initialBalance = WETH.balanceOf(address(this));
        amount = address(this).balance;

        WETH.deposit{value: amount}();

        uint256 postBalance = WETH.balanceOf(address(this));
        if (postBalance - initialBalance != amount) {
            revert InvalidWETHDeposit();
        }
    }

    /**
     * @notice Sends credit network fees
     *     Callable after all debt repaid and everyone else has claimed
     * @param to - who to send fees to
     */
    function claimNetworkFees(address to) external {
        address network = networkFeeRecipient;
        if (msg.sender != network) {
            revert NotNetworkFeeRecipient();
        }
        // can only claim after everyone else claims for incentive alignment
        if (status != STATUS.REPAID) {
            revert NotRepaid();
        }

        redeem(balanceOf(network), to, network);
    }
}
