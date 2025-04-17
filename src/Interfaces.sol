pragma solidity ^0.8.26;

/* General */

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function decimals() external view returns (uint8);
    function balanceOf(address mate) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address mate, address spender) external view returns (uint256);
}

interface IERC20x is IERC20 {
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // WETH
    function deposit() external payable returns (bool);
    // aave debt token
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
    function approveDelegation(address mate, uint256 dubloons) external;
    function borrowAllowance(address guarantor, address debtor) external view returns (uint256); //to - value
}

/* NN Core */
interface IFunETH {
    function initialize(
        address _reserveToken,
        address market,
        address _debtToken,
        string memory _name,
        string memory _sym
    ) external;

    // basic getters
    function decimals() external view returns (uint8);
    function reserveToken() external returns (IERC20x);
    function aaveMarket() external returns (IAaveMarket);
    function aToken() external returns (IERC20x);
    function debtToken() external returns (IERC20x);

    // Treasurer functions
    function lend(address mate, uint256 dubloons) external;
    function pullReserves(uint256 dubloons) external;

    // WETH functionality
    function deposit(uint256 dubloons) external;
    function depositAndApprove(address spender, uint256 dubloons) external;
    function depositOnBehalfOf(uint256 dubloons, address receiver, address referrer) external;
    function depositWithPreference(uint256 dubloons, address city, address referrer) external;
    function withdraw(uint256 dubloons) external;
    function withdrawTo(uint256 dubloons, address to) external;
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);

    // aave integrations
    function farm(uint256 dubloons) external;
    function underlying() external returns (uint256);
    function getYieldEarned() external returns (uint256);
    function getExpectedHF() external returns (uint8);
    function price(address asset) external returns (uint256);

    function reserveAssetPrice() external view returns (uint256);
    function debtAssetPrice() external view returns (uint256);

    function convertToDecimal(uint256 amount, uint8 currentDecimals, uint8 targetDecimals)
        external
        view
        returns (uint256);
}

interface IRevenueShareAgreement {
    error AlreadyInitialized();

    function initialize(
        address _borrower,
        address _creditToken,
        uint8 _lenderRevenueSplit,
        uint256 _initialPrincipal,
        uint256 _totalOwed,
        string memory _name,
        string memory _sym
    ) external;
}

interface IFeeClaimer {
    function claimFees(address revenueContract, address token, bytes calldata data)
        external
        returns (uint256 claimed);
    function operate(address revenueContract, bytes calldata data) external returns (bool);

    // owner funcs
    function claimOwnerTokens(address token) external returns (uint256 claimed);
    function claimOperatorTokens(address token) external returns (uint256 claimed);
    // function addSpigot(address revenueContract, Setting memory setting) external returns (bool);
    function removeSpigot(address revenueContract) external returns (bool);

    // stakeholder funcs
    function updateOwnerSplit(address revenueContract, uint8 ownerSplit) external returns (bool);
    function updateOwner(address newOwner) external returns (bool);
    function updateOperator(address newOperator) external returns (bool);
    function updateWhitelistedFunction(bytes4 func, bool allowed) external returns (bool);

    // Getters
    function owner() external view returns (address);
    function operator() external view returns (address);
    function isWhitelisted(bytes4 func) external view returns (bool);
    function getOwnerTokens(address token) external view returns (uint256);
    function getOperatorTokens(address token) external view returns (uint256);
    function getSetting(address revenueContract)
        external
        view
        returns (uint8 split, bytes4 claimFunc, bytes4 transferFunc);
}

/* AAVE PROTOCOL / LENDING + CREDIT */
struct ReserveConfigurationMap {
    uint256 data; // uint encoded. not important to us. see https://github.com/aave/aave-v3-core/blob/782f51917056a53a2c228701058a6c3fb233684a/contracts/protocol/libraries/types/DataTypes.sol
}

struct ReserveData {
    ReserveConfigurationMap configuration;
    uint128 liquidityIndex;
    uint128 currentLiquidityRate;
    uint128 variableBorrowIndex;
    uint128 currentVariableBorrowRate;
    uint128 currentStableBorrowRate;
    uint40 lastUpdateTimestamp;
    uint16 id;
    address aTokenAddress; // WE USE THIS
    address stableDebtTokenAddress;
    address variableDebtTokenAddress;
    address interestRateStrategyAddress;
    uint128 accruedToTreasury;
    uint128 unbacked;
    uint128 isolationModeTotalDebt;
}

interface IAaveMarket {
    function getReserveData(address asset) external view returns (ReserveData memory);
    /**
     * @notice Returns the user account data across all the reserves
     * @param user The address of the user
     * @return totalCollateralBase The total collateral of the user in the base currency used by the price feed
     * @return totalDebtBase The total debt of the user in the base currency used by the price feed
     * @return availableBorrowsBase The borrowing power left of the user in the base currency used by the price feed
     * @return currentLiquidationThreshold The liquidation threshold of the user
     * @return ltv The loan to value of the user
     * @return healthFactor The current health factor of the user
     *
     */
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );

    function setUserEMode(uint8 categoryId) external;
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);

    // function borrow(address asset, uint256 amount, address to) external returns (uint256);
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)
        external;

    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external;

    function ADDRESSES_PROVIDER() external view returns (address);
    /// @dev actually on IPoolAddressProvider not IPool
    function getPriceOracle() external view returns (IAaveMarket);
    function getAssetPrice(address asset) external view returns (uint256);
}

library AaveErrors {
    string public constant CALLER_NOT_POOL_ADMIN = "1"; // 'The caller of the function is not a pool admin'
    string public constant CALLER_NOT_EMERGENCY_ADMIN = "2"; // 'The caller of the function is not an emergency admin'
    string public constant CALLER_NOT_POOL_OR_EMERGENCY_ADMIN = "3"; // 'The caller of the function is not a pool or emergency admin'
    string public constant CALLER_NOT_RISK_OR_POOL_ADMIN = "4"; // 'The caller of the function is not a risk or pool admin'
    string public constant CALLER_NOT_ASSET_LISTING_OR_POOL_ADMIN = "5"; // 'The caller of the function is not an asset listing or pool admin'
    string public constant CALLER_NOT_BRIDGE = "6"; // 'The caller of the function is not a bridge'
    string public constant ADDRESSES_PROVIDER_NOT_REGISTERED = "7"; // 'Pool addresses provider is not registered'
    string public constant INVALID_ADDRESSES_PROVIDER_ID = "8"; // 'Invalid id for the pool addresses provider'
    string public constant NOT_CONTRACT = "9"; // 'Address is not a contract'
    string public constant CALLER_NOT_POOL_CONFIGURATOR = "10"; // 'The caller of the function is not the pool configurator'
    string public constant CALLER_NOT_ATOKEN = "11"; // 'The caller of the function is not an AToken'
    string public constant INVALID_ADDRESSES_PROVIDER = "12"; // 'The address of the pool addresses provider is invalid'
    string public constant INVALID_FLASHLOAN_EXECUTOR_RETURN = "13"; // 'Invalid return value of the flashloan executor function'
    string public constant RESERVE_ALREADY_ADDED = "14"; // 'Reserve has already been added to reserve list'
    string public constant NO_MORE_RESERVES_ALLOWED = "15"; // 'Maximum amount of reserves in the pool reached'
    string public constant EMODE_CATEGORY_RESERVED = "16"; // 'Zero eMode category is reserved for volatile heterogeneous assets'
    string public constant INVALID_EMODE_CATEGORY_ASSIGNMENT = "17"; // 'Invalid eMode category assignment to asset'
    string public constant RESERVE_LIQUIDITY_NOT_ZERO = "18"; // 'The liquidity of the reserve needs to be 0'
    string public constant FLASHLOAN_PREMIUM_INVALID = "19"; // 'Invalid flashloan premium'
    string public constant INVALID_RESERVE_PARAMS = "20"; // 'Invalid risk parameters for the reserve'
    string public constant INVALID_EMODE_CATEGORY_PARAMS = "21"; // 'Invalid risk parameters for the eMode category'
    string public constant BRIDGE_PROTOCOL_FEE_INVALID = "22"; // 'Invalid bridge protocol fee'
    string public constant CALLER_MUST_BE_POOL = "23"; // 'The caller of this function must be a pool'
    string public constant INVALID_MINT_AMOUNT = "24"; // 'Invalid amount to mint'
    string public constant INVALID_BURN_AMOUNT = "25"; // 'Invalid amount to burn'
    string public constant INVALID_AMOUNT = "26"; // 'Amount must be greater than 0'
    string public constant RESERVE_INACTIVE = "27"; // 'Action requires an active reserve'
    string public constant RESERVE_FROZEN = "28"; // 'Action cannot be performed because the reserve is frozen'
    string public constant RESERVE_PAUSED = "29"; // 'Action cannot be performed because the reserve is paused'
    string public constant BORROWING_NOT_ENABLED = "30"; // 'Borrowing is not enabled'
    string public constant NOT_ENOUGH_AVAILABLE_USER_BALANCE = "32"; // 'User cannot withdraw more than the available balance'
    string public constant INVALID_INTEREST_RATE_MODE_SELECTED = "33"; // 'Invalid interest rate mode selected'
    string public constant COLLATERAL_BALANCE_IS_ZERO = "34"; // 'The collateral balance is 0'
    string public constant HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD = "35"; // 'Health factor is lesser than the liquidation threshold'
    string public constant COLLATERAL_CANNOT_COVER_NEW_BORROW = "36"; // 'There is not enough collateral to cover a new borrow'
    string public constant COLLATERAL_SAME_AS_BORROWING_CURRENCY = "37"; // 'Collateral is (mostly) the same currency that is being borrowed'
    string public constant NO_DEBT_OF_SELECTED_TYPE = "39"; // 'For repayment of a specific type of debt, the user needs to have debt that type'
    string public constant NO_EXPLICIT_AMOUNT_TO_REPAY_ON_BEHALF = "40"; // 'To repay on behalf of a user an explicit amount to repay is needed'
    string public constant NO_OUTSTANDING_VARIABLE_DEBT = "42"; // 'User does not have outstanding variable rate debt on this reserve'
    string public constant UNDERLYING_BALANCE_ZERO = "43"; // 'The underlying balance needs to be greater than 0'
    string public constant INTEREST_RATE_REBALANCE_CONDITIONS_NOT_MET = "44"; // 'Interest rate rebalance conditions were not met'
    string public constant HEALTH_FACTOR_NOT_BELOW_THRESHOLD = "45"; // 'Health factor is not below the threshold'
    string public constant COLLATERAL_CANNOT_BE_LIQUIDATED = "46"; // 'The collateral chosen cannot be liquidated'
    string public constant SPECIFIED_CURRENCY_NOT_BORROWED_BY_USER = "47"; // 'User did not borrow the specified currency'
    string public constant INCONSISTENT_FLASHLOAN_PARAMS = "49"; // 'Inconsistent flashloan parameters'
    string public constant BORROW_CAP_EXCEEDED = "50"; // 'Borrow cap is exceeded'
    string public constant SUPPLY_CAP_EXCEEDED = "51"; // 'Supply cap is exceeded'
    string public constant UNBACKED_MINT_CAP_EXCEEDED = "52"; // 'Unbacked mint cap is exceeded'
    string public constant DEBT_CEILING_EXCEEDED = "53"; // 'Debt ceiling is exceeded'
    string public constant UNDERLYING_CLAIMABLE_RIGHTS_NOT_ZERO = "54"; // 'Claimable rights over underlying not zero (aToken supply or accruedToTreasury)'
    string public constant VARIABLE_DEBT_SUPPLY_NOT_ZERO = "56"; // 'Variable debt supply is not zero'
    string public constant LTV_VALIDATION_FAILED = "57"; // 'Ltv validation failed'
    string public constant INCONSISTENT_EMODE_CATEGORY = "58"; // 'Inconsistent eMode category'
    string public constant PRICE_ORACLE_SENTINEL_CHECK_FAILED = "59"; // 'Price oracle sentinel validation failed'
    string public constant ASSET_NOT_BORROWABLE_IN_ISOLATION = "60"; // 'Asset is not borrowable in isolation mode'
    string public constant RESERVE_ALREADY_INITIALIZED = "61"; // 'Reserve has already been initialized'
    string public constant USER_IN_ISOLATION_MODE_OR_LTV_ZERO = "62"; // 'User is in isolation mode or ltv is zero'
    string public constant INVALID_LTV = "63"; // 'Invalid ltv parameter for the reserve'
    string public constant INVALID_LIQ_THRESHOLD = "64"; // 'Invalid liquidity threshold parameter for the reserve'
    string public constant INVALID_LIQ_BONUS = "65"; // 'Invalid liquidity bonus parameter for the reserve'
    string public constant INVALID_DECIMALS = "66"; // 'Invalid decimals parameter of the underlying asset of the reserve'
    string public constant INVALID_RESERVE_FACTOR = "67"; // 'Invalid reserve factor parameter for the reserve'
    string public constant INVALID_BORROW_CAP = "68"; // 'Invalid borrow cap for the reserve'
    string public constant INVALID_SUPPLY_CAP = "69"; // 'Invalid supply cap for the reserve'
    string public constant INVALID_LIQUIDATION_PROTOCOL_FEE = "70"; // 'Invalid liquidation protocol fee for the reserve'
    string public constant INVALID_EMODE_CATEGORY = "71"; // 'Invalid eMode category for the reserve'
    string public constant INVALID_UNBACKED_MINT_CAP = "72"; // 'Invalid unbacked mint cap for the reserve'
    string public constant INVALID_DEBT_CEILING = "73"; // 'Invalid debt ceiling for the reserve
    string public constant INVALID_RESERVE_INDEX = "74"; // 'Invalid reserve index'
    string public constant ACL_ADMIN_CANNOT_BE_ZERO = "75"; // 'ACL admin cannot be set to the zero address'
    string public constant INCONSISTENT_PARAMS_LENGTH = "76"; // 'Array parameters that should be equal length are not'
    string public constant ZERO_ADDRESS_NOT_VALID = "77"; // 'Zero address not valid'
    string public constant INVALID_EXPIRATION = "78"; // 'Invalid expiration'
    string public constant INVALID_SIGNATURE = "79"; // 'Invalid signature'
    string public constant OPERATION_NOT_SUPPORTED = "80"; // 'Operation not supported'
    string public constant DEBT_CEILING_NOT_ZERO = "81"; // 'Debt ceiling is not zero'
    string public constant ASSET_NOT_LISTED = "82"; // 'Asset is not listed'
    string public constant INVALID_OPTIMAL_USAGE_RATIO = "83"; // 'Invalid optimal usage ratio'
    string public constant UNDERLYING_CANNOT_BE_RESCUED = "85"; // 'The underlying asset cannot be rescued'
    string public constant ADDRESSES_PROVIDER_ALREADY_ADDED = "86"; // 'Reserve has already been added to reserve list'
    string public constant POOL_ADDRESSES_DO_NOT_MATCH = "87"; // 'The token implementation pool address and the pool address provided by the initializing pool do not match'
    string public constant SILOED_BORROWING_VIOLATION = "89"; // 'User is trying to borrow multiple assets including a siloed one'
    string public constant RESERVE_DEBT_NOT_ZERO = "90"; // the total debt of the reserve needs to be 0
    string public constant FLASHLOAN_DISABLED = "91"; // FlashLoaning for this asset is disabled
    string public constant INVALID_MAX_RATE = "92"; // The expect maximum borrow rate is invalid
    string public constant WITHDRAW_TO_ATOKEN = "93"; // Withdrawing to the aToken is not allowed
    string public constant SUPPLY_TO_ATOKEN = "94"; // Supplying to the aToken is not allowed
    string public constant SLOPE_2_MUST_BE_GTE_SLOPE_1 = "95"; // Variable interest rate slope 2 can not be lower than slope 1
    string public constant CALLER_NOT_RISK_OR_POOL_OR_EMERGENCY_ADMIN = "96"; // 'The caller of the function is not a risk, pool or emergency admin'
    string public constant LIQUIDATION_GRACE_SENTINEL_CHECK_FAILED = "97"; // 'Liquidation grace sentinel validation failed'
    string public constant INVALID_GRACE_PERIOD = "98"; // Grace period above a valid range
    string public constant INVALID_FREEZE_STATE = "99"; // Reserve is already in the passed freeze state
    string public constant NOT_BORROWABLE_IN_EMODE = "100"; // Asset not borrowable in eMode
}

interface IGPSettlement {
    function filledAmount(bytes calldata _orderUid) external view returns (uint256);
}

interface IMilkman {
    function requestSwapExactTokensForTokens(
        uint256 amountIn,
        IERC20 fromToken,
        IERC20 toToken,
        address to,
        address priceChecker,
        bytes calldata priceCheckerData
    ) external;

    function cancelSwap(
        uint256 amountIn,
        IERC20 fromToken,
        IERC20 toToken,
        address to,
        address priceChecker,
        bytes calldata priceCheckerData
    ) external;
}
