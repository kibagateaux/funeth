pragma solidity ^0.8.26;

import {ERC20} from "solady/tokens/ERC20.sol";
import {IFunETH, IERC20x, IAaveMarket, ReserveData, IFunFactory, IRevenueShareAgreement} from "./Interfaces.sol";

contract FunETH is IFunETH, ERC20 {
    // from solady/ERC20 for increaseAllowance (important for LandRegistry security)
    uint256 private constant _ALLOWANCE_SLOT_SEED = 0x7f5e9f20;
    /// @dev `keccak256(bytes("Approval(address,address,uint256)"))`.
    uint256 private constant _APPROVAL_EVENT_SIGNATURE =
        0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925;

    // Multisig deployed on Mainnet, Arbitrum, Base, OP,
    address public constant FUN_OPS = address(0xC958dEeAB982FDA21fC8922493d0CEDCD26287C3);
    uint64 public constant MIN_DEPOSIT = 100_000_000; // to prevent aave math from causing reverts on small amounts from rounding decimal diffs. $100 USDC or 0.5 ETH ETH
    // TODO figure out lowest amount where aave tests dont fail

    /// @notice min health factor for user to redeem to prevent malicious liquidations. 2 = Redeems until debt = 50% of funETH TVL
    uint8 public constant MIN_REDEEM_FACTOR = 2;
    /// @notice min health factor for treasury to pull excess interest. 8 = ~12% of total funETH TVL can be delegated
    uint8 public constant MIN_RESERVE_FACTOR = 8;
    /// @notice used to convert AAVE LTV to HF calc
    uint16 public constant BPS_COEFFICIENT = 1e4;
    /// @notice Aave variable debt mode for all borrowing
    uint8 internal constant AAVE_INTEREST_MODE = 0;
    IFunFactory internal factory;

    string internal _name;
    string internal _symbol;
    /// @notice funETH token decimals. same as reserveToken decimals
    uint8 internal _decimals;
    /// @notice totalSupply() = total reserveToken deposited, denominated in reserve decimals.

    // TODO these necessary? outside of testing?
    /// @notice full decimal offset between reserveToken and aToken e.g. 1e10 not 10
    uint256 public reserveVsATokenDecimalOffset;
    /// @notice decimals for token we borrow for use in HF calculations
    uint8 public debtTokenDecimals;

    /// @notice Token to accept for home payments in funCity
    IERC20x public reserveToken;
    // TODO does anything below need to actually be public except for testing?
    /// @notice Aave Pool for lending + borrowing
    IAaveMarket public aaveMarket;
    /// @notice Aave yield bearing token for reserveToken. Provides total ETH balance of funETH contract.
    IERC20x public aToken;
    /// @notice Aave variable debt token that we let popups borrow against funCity collateral
    IERC20x public debtToken;
    /// @notice Address of the actual debt asset. e.g. USDC
    address internal debtAsset;

    /// @notice total delegated. NOT total currently borrowed. Denominated in debtToken
    uint256 public totalCreditDelegated;

    struct City {
        address rsa;
        uint256 owed;
    }
    mapping(address => City) public cities;

    ///@notice who deposited, how much, where they want yield directed, who recruited mate
    event Deposit(
        address indexed mate, address indexed receiver, uint256 dubloons, address indexed city, address referrer
    );
    ///@notice who withdrew, how much
    event Withdrawal(address indexed me, address indexed to, uint256 dubloons);
    ///@notice where we are farming, what token, how much was deposited
    event Farm(address indexed market, address indexed reserve, uint256 dubloons);
    ///@notice where yield was sent to, how much
    event PullReserves(address indexed treasurer, uint256 dubloons);
    ///@notice who underwrote loan, what token is borrowed, who loan was given to, amount of tokens lent
    event Lend(address indexed treasurer, address indexed debtToken, address indexed city, uint256 dubloons, address rsa);
    event LoanRepaid(address indexed city, address indexed rsa, uint256 dubloons);
    event LoanClosed(address indexed city, address indexed rsa);

    error AlreadyInitialized();
    error UnsupportedChain();
    error InvalidReserveMarket();
    error InvalidToken();
    error InvalidReceiver();
    error BelowMinDeposit();
    error NotEthReserve();
    error NotfunCity();
    error LoanFailed();
    error InvalidTreasuryOperation();
    error InsufficientReserves();
    error MaliciousWithdraw();
    error CreditRisk();
    error NoCredit();
    error CityAlreadyLent();
    error CityNotLent();
    error InvalidLoanClaim();

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override(IFunETH, ERC20) returns (uint8) {
        return _decimals;
    }

    function initialize(
        address _reserveToken,
        address market,
        address _debtToken,
        string memory name_,
        string memory symbol_
    ) public {
        if (address(reserveToken) != address(0)) revert AlreadyInitialized();

        // naive check if funCity governance is deployed on this chain
        if (getContractSize(FUN_OPS) == 0) revert UnsupportedChain();

        ReserveData memory pool = IAaveMarket(market).getReserveData(address(_reserveToken));
        // Ensure aave market accepts the asset people deposit
        if (pool.aTokenAddress == address(0)) revert InvalidReserveMarket();

        factory = IFunFactory(msg.sender); // assumes only deployed + configured through factory contract that includes RSA deployments
        _name = name_;
        _symbol = symbol_;
        aaveMarket = IAaveMarket(market);
        reserveToken = IERC20x(_reserveToken);
        aToken = IERC20x(pool.aTokenAddress);
        debtToken = IERC20x(_debtToken);
        debtAsset = debtToken.UNDERLYING_ASSET_ADDRESS();

        // Aave docs say eMode must be the same for delegator + borrower. 0 = none is fine.
        // aaveMarket.setUserEMode(eMode);

        reserveToken.approve(address(aaveMarket), type(uint256).max);

        uint8 reserveDecimals = reserveToken.decimals();
        _decimals = reserveDecimals;
        uint8 aTokenDecimals = aToken.decimals();
        // assume aToken = 18 decimals and reserve token <= 18 decimals
        if (aTokenDecimals >= reserveDecimals) {
            // = 1 if decimals are same value aka no change
            reserveVsATokenDecimalOffset = 10 ** (aTokenDecimals - reserveDecimals);
        }

        // assumes aave debt token decimals = actual debt asset token decimals
        debtTokenDecimals = debtToken.decimals();

        // Would make sense to do here but reverts if caller has no collateral yet
        // aaveMarket.setUserUseReserveAsCollateral(address(reserveToken), true);
    }

    /// TODO make ERC4626 compliant?
    function deposit(uint256 dubloons) public {
        _deposit(msg.sender, msg.sender, dubloons, address(FUN_OPS), address(this));
    }

    function depositOnBehalfOf(uint256 dubloons, address to, address referrer) public {
        _deposit(msg.sender, to, dubloons, address(FUN_OPS), referrer);
    }

    function depositWithPreference(uint256 dubloons, address city, address referrer) public {
        _deposit(msg.sender, msg.sender, dubloons, city, referrer);
    }

    /// @notice helper function for integrators e.g. LP farming to simplify UX
    function depositAndApprove(address spender, uint256 dubloons) public {
        _deposit(msg.sender, msg.sender, dubloons, address(FUN_OPS), address(this));
        approve(spender, dubloons);
    }

    function _deposit(address owner, address receiver, uint256 dubloons, address city, address referrer) public {
        if (dubloons < MIN_DEPOSIT) revert BelowMinDeposit();
        if (receiver == address(0)) revert InvalidReceiver();

        reserveToken.transferFrom(owner, address(this), dubloons);
        farm(reserveToken.balanceOf(address(this))); // schloop tokens sent directly too
        _mint(receiver, dubloons);

        emit Deposit(owner, receiver, dubloons, city, referrer);
    }

    function farm(uint256 dubloons) public {
        // token approval in pullReserves
        aaveMarket.supply(address(reserveToken), dubloons, address(this), 200); // 200 = referall code. l33t "Zoo"
        emit Farm(address(aaveMarket), address(reserveToken), dubloons);
    }

    /// TODO make ERC4626 compliant?
    function withdraw(uint256 dubloons) public {
        _withdraw(msg.sender, msg.sender, dubloons);
    }

    function withdrawTo(uint256 dubloons, address to) public {
        _withdraw(msg.sender, to, dubloons);
    }

    function _withdraw(address owner, address to, uint256 dubloons) internal {
        _burn(owner, dubloons);
        aaveMarket.withdraw(address(reserveToken), dubloons, to);
        // check *after* withdrawing and aave updates collateral balance
        if (getExpectedHF() < MIN_REDEEM_FACTOR) revert MaliciousWithdraw();
        emit Withdrawal(owner, to, dubloons);
    }

    /* funETH Treasury functions */

    modifier onlyTreasury() {
        if (msg.sender != FUN_OPS) revert NotfunCity();
        _;
    }

    function _assertFinancialHealth() internal view {
        if (totalSupply() > underlying()) revert InsufficientReserves();
        if (getExpectedHF() < MIN_RESERVE_FACTOR) revert CreditRisk();
    }

    function pullReserves(uint256 dubloons) onlyTreasury public {

        aToken.transfer(FUN_OPS, dubloons);

        // assert financial health *after* pulling reserves.
        _assertFinancialHealth();

        // incase reserveToken doesnt support infinite approve, refresh but not on every deposit
        reserveToken.approve(address(aaveMarket), type(uint256).max);

        emit PullReserves(msg.sender, dubloons);
    }

    /**
     * @notice Allow projects to borrow against funCity collateral with Aave credit delegation.
     *     Technically this will almost always make us frational reserve. 
     *     But it is a self-repaying loan that eventually becomes solvent
     * @param city - nnzalu popup city to receive loan
     * @param dubloons - Should be Aave market denominated. Usually USD to 10 decimals
     */
    function lend(address city, uint256 dubloons, uint16 apr, string memory name_, string memory symbol_) onlyTreasury public {
        if(cities[city].rsa != address(0)) revert CityAlreadyLent();

        // totalCreditDelegated += dubloons;

        IRevenueShareAgreement rsa = IRevenueShareAgreement(factory.deployRevenueShareAgreement(
            city,
            debtAsset,
            apr,
            name_,
            symbol_
        ));
        aaveMarket.borrow(debtAsset, dubloons, AAVE_INTEREST_MODE, 200, address(this));
        rsa.deposit(dubloons, address(this));
        cities[city] = City({
            rsa: address(rsa),
            owed: rsa.balanceOf(address(this)) // total debt including apr not initial loan
        });
        rsa.initiateTerm();

        _assertFinancialHealth();

        // throws error if u set collateral with 0 deposits so cant do on initialize.
        aaveMarket.setUserUseReserveAsCollateral(address(reserveToken), true);
        // todo add active rsa to city struct? No loan if active rsa, delete on repay if rsa.balanceOf(this) == 0?

        emit Lend(msg.sender, address(debtToken), city, dubloons, address(rsa));
    }

    function repay(address city, uint256 dubloons) public {
        City memory creditInfo = cities[city];

        if(creditInfo.rsa == address(0)) revert CityNotLent();
        if(dubloons > creditInfo.owed) revert InvalidLoanClaim();

        try IRevenueShareAgreement(creditInfo.rsa).redeem(dubloons, address(this), address(this)) {
            ERC20(debtAsset).approve(address(aaveMarket), dubloons);
            aaveMarket.repay(debtAsset, dubloons, AAVE_INTEREST_MODE, address(this));

            if(dubloons == creditInfo.owed) {
                emit LoanRepaid(city, creditInfo.rsa, dubloons);
                emit LoanClosed(city, creditInfo.rsa);
                delete cities[city];
            } else {
                cities[city].owed -= dubloons;
                emit LoanRepaid(city, creditInfo.rsa, dubloons);
            }

            // TODO what if loan canceled so city.owed > tokens redeemable?
        } catch {
            revert InvalidLoanClaim();
        }
    }

    /// @notice returns worst case scenario health factor if all credit extended is borrowed at the same time
    function getExpectedHF() public view returns (uint8) {
        // ideally use liquidationThreshold not ltv for more safety but aave uses ltv for "borrowable" amount so would make tests messier
        (uint256 totalCollateralBase, uint256 totalDebtBase,,, uint256 ltv, uint256 hf) =
            aaveMarket.getUserAccountData(address(this));

        // TODO shouldnt need to calculate if all borowing managed thru this contract
        return uint8(convertToDecimal(hf, 18, 0));

        // aave *internally assumes* debt amount is usd in 8 decimals. convert debt token decimals to match
        // https://github.com/aave-dao/aave-v3-origin/blob/a0512f8354e97844a3ed819cf4a9a663115b8e20/src/contracts/protocol/libraries/logic/LiquidationLogic.sol#L72
        // Also assumes debtToken decimals = actual token decimals
        // uint256 scaledDelegatedCredit = convertToDecimal(
        //     totalCreditDelegated * price(debtAsset),
        //     debtTokenDecimals + 8, // offset token + new price decimals to match aave usd decimals
        //     8
        // );

        // // debt > credit delegated e.g. interest or price increase since delegation
        // // So of debt exceeds delegation then assume all credit is borrowed. Not 100% accurate but reasonable
        // // Since borrowing not internal to contract we cant know how much credit was borrowed vs reserve price dropping.
        // uint256 unborrowedDebt =
        //     totalDebtBase > scaledDelegatedCredit ? totalDebtBase : scaledDelegatedCredit - totalDebtBase;
        // uint256 maxDebt = totalDebtBase + unborrowedDebt;

        // // Avoid division by zero
        // if (maxDebt == 0) return uint8(convertToDecimal(hf, 18, 2)); // returns 100
        // // max debt borrowed already
        // if (unborrowedDebt == totalDebtBase) return uint8(convertToDecimal(hf, 18, 0));

        // return uint8((totalCollateralBase * ltv) / maxDebt / BPS_COEFFICIENT);
    }

    /// Helper functions

    /// @notice total amount of tokens deposited in aave. Denominated in reserrveToken decimals
    function underlying() public view returns (uint256) {
        return aToken.balanceOf(address(this)) / reserveVsATokenDecimalOffset;
    }

    /// @notice returns current health factor disregarding future potential debt from NN loans
    function getYieldEarned() public view returns (uint256) {
        return underlying() - totalSupply() - 1; // -1 to account for rounding errors in aave
    }

    // TODO should turn price + decimals func into lib for NNTokens

    /// @notice returns price of asset in USD 8 decimals from Aave/Chainlink oracles
    /// @dev Assumes Aave only uses USD price oracles. e.g. not stETH/ETH but shouldnt be relevant for simple assets
    function price(address asset) public view returns (uint256) {
        return IAaveMarket(aaveMarket.ADDRESSES_PROVIDER()).getPriceOracle().getAssetPrice(asset);
    }

    function reserveAssetPrice() public view returns (uint256) {
        return price(address(reserveToken));
    }

    function debtAssetPrice() public view returns (uint256) {
        return price(address(debtAsset));
    }

    function convertToDecimal(uint256 amount, uint8 currentDecimals, uint8 targetDecimals)
        public
        pure
        returns (uint256)
    {
        if (currentDecimals == targetDecimals) return amount;
        if (currentDecimals > targetDecimals) {
            return amount / (10 ** (currentDecimals - targetDecimals));
        } else {
            return amount * (10 ** (targetDecimals - currentDecimals));
        }
    }

    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        assembly {
            mstore(0x20, spender)
            mstore(0x0c, _ALLOWANCE_SLOT_SEED)
            mstore(0x00, caller())
            let allowanceSlot := keccak256(0x0c, 0x34)
            let currentAllowance := sload(allowanceSlot)
            let newAllowance := add(currentAllowance, addedValue)

            // prevent overflow
            if gt(currentAllowance, newAllowance) { revert(0, 0) }

            sstore(allowanceSlot, newAllowance)

            // emit event
            mstore(0x00, newAllowance)
            log3(0x00, 0x20, _APPROVAL_EVENT_SIGNATURE, caller(), spender)
        }
        return true;
    }

    function recoverTokens(address token) public {
        if (token == address(aToken)) revert InvalidToken();
        // TODO add debtAsset once we add RSA
        if (token == address(0)) {
            (bool success,) = FUN_OPS.call{value: address(this).balance}("");
            assert(success);
        } else {
            IERC20x(token).transfer(FUN_OPS, IERC20x(token).balanceOf(address(this)));
        }
    }

    function getContractSize(address _contract) private view returns (uint256 size) {
        assembly {
            size := extcodesize(_contract)
        }
    }
}
