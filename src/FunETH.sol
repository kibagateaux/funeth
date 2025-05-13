pragma solidity ^0.8.26;

import {ERC20} from "solady/tokens/ERC20.sol";
import {IFunETH, IERC20x, IAaveMarket, ReserveData, IFunFactory, IFunFunding} from "./Interfaces.sol";
import {Ownable} from "solady/auth/Ownable.sol";

contract FunETH is IFunETH, ERC20, Ownable {
    // from solady/ERC20 for increaseAllowance (important for LandRegistry security)
    uint256 private constant _ALLOWANCE_SLOT_SEED = 0x7f5e9f20;
    /// @dev `keccak256(bytes("Approval(address,address,uint256)"))`.
    uint256 private constant _APPROVAL_EVENT_SIGNATURE =
        0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925;

    // Multisig deployed on Mainnet, Arbitrum, Base, OP,
    // TODO deprecate, make internal, and use owner()
    address private constant FUN_OPS = address(0xC958dEeAB982FDA21fC8922493d0CEDCD26287C3);
    uint64 public constant MIN_DEPOSIT = 100_000_000; // to prevent aave math from causing reverts on small amounts from rounding decimal diffs. $100 USDC or 0.5 ETH ETH
    // TODO figure out lowest amount where aave tests dont fail

    /// @notice min health factor for user to redeem to prevent malicious liquidations. 2 = Redeems until debt = 50% of funETH TVL
    uint8 public constant MIN_REDEEM_FACTOR = 2;
    /// @notice min health factor for treasury to pull excess interest. 8 = ~12% of total funETH TVL can be delegated
    uint8 public constant MIN_RESERVE_FACTOR = 6;
    /// @notice Aave variable debt mode for all borrowing. 2 = variable
    uint8 internal constant AAVE_DEBT_INTEREST_MODE = 2;

    string internal _name;
    string internal _symbol;
    /// @notice funETH token decimals. same as reserveToken decimals
    uint8 internal _decimals;
    
    /// @notice totalSupply() = total reserveToken deposited, denominated in reserve decimals.

    // TODO these necessary? outside of testing?
    /// @notice full decimal offset between reserveToken and aToken e.g. 1e10 not 10
    uint256 public reserveVsATokenDecimalOffset;

    /// @notice Token to accept for home payments in funCity
    IERC20x public reserveToken;
    // TODO does anything below need to actually be public except for testing?
    /// @notice Aave Pool for lending + borrowing
    IAaveMarket public aaveMarket;
    /// @notice Aave yield bearing token for reserveToken. Provides total ETH balance of funETH contract.
    IERC20x public aToken;
    /// @notice Aave variable debt token that we let popups borrow against funCity collateral
    IERC20x public debtToken; // TODO remove this and debtTokenDecimals vestigial
    /// @notice Address of the actual debt asset. e.g. USDC
    address public debtAsset;

    struct City {
        address fun_dingo; // current lend contract
        uint256 owed; // how many tokens funETH can redeem on fun_dingo
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
    event PullReserves(address indexed treasurer, address indexed token, uint256 dubloons);
    ///@notice who underwrote loan, what token is borrowed, who loan was given to, amount of tokens lent
    event Lend(
        address indexed treasurer, address indexed debtToken, address indexed city, uint256 dubloons, address fun_dingo
    );
    event LoanRepaid(address indexed city, address indexed fun_dingo, uint256 dubloons);
    event LoanClosed(address indexed city, address indexed fun_dingo);

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
        // TODO add owner param
        address _reserveToken,
        address market,
        address _debtToken,
        string memory name_,
        string memory symbol_
    ) public {
        _initializeOwner(FUN_OPS);
        if (address(reserveToken) != address(0)) revert AlreadyInitialized();

        // naive check if funCity governance is deployed on this chain
        if (getContractSize(FUN_OPS) == 0) revert UnsupportedChain();

        ReserveData memory pool = IAaveMarket(market).getReserveData(address(_reserveToken));
        // Ensure aave market accepts the asset people deposit
        if (pool.aTokenAddress == address(0)) revert InvalidReserveMarket();

        _name = name_;
        _symbol = symbol_;
        aaveMarket = IAaveMarket(market);
        reserveToken = IERC20x(_reserveToken);
        aToken = IERC20x(pool.aTokenAddress);
        debtToken = IERC20x(_debtToken); // TODO dont think we need this anymore w/ delegateCredit
        debtAsset = debtToken.UNDERLYING_ASSET_ADDRESS();

        // approve aave market for both assets so we dont have to call refresh()
        ERC20(debtAsset).approve(address(aaveMarket), type(uint256).max);
        reserveToken.approve(address(aaveMarket), type(uint256).max);

        uint8 reserveDecimals = reserveToken.decimals();
        _decimals = reserveDecimals;
        uint8 aTokenDecimals = aToken.decimals();
        // assume aToken = 18 decimals and reserve token <= 18 decimals
        if (aTokenDecimals >= reserveDecimals) {
            // = 1 if decimals are same value aka no change
            reserveVsATokenDecimalOffset = 10 ** (aTokenDecimals - reserveDecimals);
        }
    }

    /// @dev WETH compliant interface
    function deposit(uint256 dubloons) public {
        _deposit(msg.sender, msg.sender, dubloons, address(FUN_OPS), address(this));
    }

    /// @dev ERC4626 compliant interface
    function deposit(uint256 dubloons, address receiver) public {
        _deposit(msg.sender, receiver, dubloons, address(FUN_OPS), address(this));
    }

    function depositWithPreference(uint256 dubloons, address receiver, address city, address referrer) public {
        _deposit(msg.sender, receiver, dubloons, city, referrer);
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
        farm(address(reserveToken), reserveToken.balanceOf(address(this))); // schloop tokens sent directly too
        _mint(receiver, dubloons);

        emit Deposit(owner, receiver, dubloons, city, referrer);
    }

    function farm(address _reserveToken, uint256 dubloons) public {
        // token approval in pullReserves
        aaveMarket.supply(address(_reserveToken), dubloons, address(this), 200); // 200 = referall code. l33t "Zoo"
        emit Farm(address(aaveMarket), address(_reserveToken), dubloons);
    }

    /// @dev WETH compliant interface
    function withdraw(uint256 dubloons) public {
        _withdraw(msg.sender, msg.sender, dubloons);
    }

    /// @dev ERC4626 compliant interface
    function redeem(uint256 shares, address to, address owner) public {
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        _withdraw(owner, to, shares);
    }

    function _withdraw(address owner, address to, uint256 dubloons) internal {
        _burn(owner, dubloons);
        aaveMarket.withdraw(address(reserveToken), dubloons, to);
        // check *after* withdrawing and aave updates collateral balance
        if (getExpectedHF() < MIN_REDEEM_FACTOR) revert MaliciousWithdraw();
        emit Withdrawal(owner, to, dubloons);
    }

    function _assertFinancialHealth() internal view {
        if (totalSupply() > underlying()) revert InsufficientReserves();
        if (getExpectedHF() < MIN_RESERVE_FACTOR) revert CreditRisk();
    }

    /* funETH Treasury functions */
    /**
     * @dev generalized implementation to allow different fun tokens/ configs without lots of params needed
     */
    function pullReserves(uint256 dubloons, address debtAssetFunToken) public onlyOwner {

        if (debtAssetFunToken == address(0)) {
            // mint excess yield as funToken to treasury
            _mint(FUN_OPS, dubloons); // reverts on assertFinHealth if > underlying() automatically
            emit PullReserves(msg.sender, address(reserveToken), dubloons);
        } else {
            // If we want to directly swap with another fun token
            // aDebtAssert (>funReserve) -> debtAsset (>funReserve) -> funDebtAsset (>funOps)
            aaveMarket.withdraw(debtAsset, dubloons, address(this));
            IERC20x(debtAsset).approve(debtAssetFunToken, dubloons);
            IFunFunding(debtAssetFunToken).deposit(dubloons, FUN_OPS);

            // or more general just transfer debtAToken to ops
            // debtAssetAToken.transfer(FUN_OPS,dubloons);

            emit PullReserves(msg.sender, address(debtAsset), dubloons);
        }

        // assert financial health *after* pulling reserves.
        _assertFinancialHealth();
    }

    /**
     * @notice Allows anyone to refresh token approvals for aave market.
     *     This is necessary if reserveToken does not support infinite approve.
     *      Can enable debtAsset to be used as collateral if excess after repaying debt.
     * @dev Must be called with `reserveToken` before lend() can work
     */
    function refresh(address _reserveToken) public {
        IERC20x(_reserveToken).approve(address(aaveMarket), type(uint256).max);
        aaveMarket.setUserUseReserveAsCollateral(_reserveToken, true);
    }

    /**
     * @notice Allow projects to borrow against funCity collateral with Aave credit delegation.
     *     Technically this will almost always make us frational reserve.
     *     But it is a self-repaying loan that eventually becomes solvent
     * @param city - nnzalu popup city to receive loan.
     * @param fun_dingo - ERC4626 to deposit for yield. We assume only FunFunding contract
     * @param dubloons - Should be Aave market denominated. Usually USD to 10 decimals
     */
    function lend(address city, address fun_dingo, uint256 dubloons) public onlyOwner {
        if (cities[city].fun_dingo != address(0)) revert CityAlreadyLent();

        aaveMarket.borrow(debtAsset, dubloons, AAVE_DEBT_INTEREST_MODE, 200, address(this));
        
        IERC20x(debtAsset).approve(fun_dingo, dubloons);
        uint256 newShares = IFunFunding(fun_dingo).deposit(dubloons, address(this));

        cities[city] = City({
            fun_dingo: fun_dingo,
            //  allow doing multiple deposits to same fun_dingo
            owed: cities[city].owed + newShares
        });

        _assertFinancialHealth();

        emit Lend(msg.sender, address(debtAsset), city, dubloons, fun_dingo);
    }

    function repay(address city, uint256 dubloons) public {
        City memory creditInfo = cities[city];

        if (creditInfo.fun_dingo == address(0)) revert CityNotLent();
        if (dubloons > creditInfo.owed) revert InvalidLoanClaim();

        // Even if status == INIT/CANCELED we get back total expected tokens with redeem()
        try IFunFunding(creditInfo.fun_dingo).redeem(dubloons, address(this), address(this)) {
            // TODO should save rsa rate in cities? Easier to calculate non-funfunding here while maintaining assurances
            // making lend/repay more flexible for higher yield strategies is pretty good.

            // _repayOrComp deals with aave specific lending/farming logic.
            _repayOrCompound(dubloons);

            // our accounting is based on cities[city].owed
            if (dubloons == creditInfo.owed) {
                emit LoanRepaid(city, creditInfo.fun_dingo, dubloons);
                emit LoanClosed(city, creditInfo.fun_dingo);
                delete cities[city];
            } else {
                cities[city].owed -= dubloons;
                emit LoanRepaid(city, creditInfo.fun_dingo, dubloons);
            }
        } catch {
            revert InvalidLoanClaim();
        }
    }

    function _repayOrCompound(uint256 dubloons) internal {
        (, uint256 debtBase,,,,) = aaveMarket.getUserAccountData(address(this));
        if (debtBase == 0) {
            // no debt, perfect health
            // turn excess debtAsset yield into aTokens
            farm(debtAsset, dubloons);
        } else {
            // else paydown global debt

            // Aave lets you send # > debt so you can pay off all interest accrued and sets borrowing to off for u
            // https://github.com/aave-dao/aave-v3-origin/blob/464a0ea5147d204140ceda42a433656a58c8e212/src/contracts/protocol/libraries/logic/BorrowLogic.sol#L197
            aaveMarket.repay(debtAsset, dubloons, AAVE_DEBT_INTEREST_MODE, address(this));
        }
    }

    /// Helper functions

    /// @notice returns worst case scenario health factor if all credit extended is borrowed at the same time
    function getExpectedHF() public view returns (uint8) {
        (,,,,, uint256 hf) = aaveMarket.getUserAccountData(address(this));
        return uint8(convertToDecimal(hf, 18, 0));
    }

    /// @notice total amount of tokens deposited in aave. Denominated in reserrveToken decimals
    function underlying() public view returns (uint256) {
        return aToken.balanceOf(address(this)) / reserveVsATokenDecimalOffset;
    }

    /// @notice returns current health factor disregarding future potential debt from NN loans
    function getYieldEarned() public view returns (uint256) {
        // TODO delete  - 1 suffix
        return (underlying() - totalSupply()) - 1; // -1 to account for rounding errors in aave
    }

    // TODO Basically here down should turn price + decimals func into lib for all Fun contracts

    /// @notice returns price of asset in USD 8 decimals from Aave/Chainlink oracles
    /// @dev Assumes Aave only uses USD price oracles. e.g. not stETH/ETH but shouldnt be relevant for simple assets
    function price(bool isReserveRequest) public view returns (uint256) {
        return IAaveMarket(aaveMarket.ADDRESSES_PROVIDER())
            .getPriceOracle()
            .getAssetPrice(isReserveRequest ? address(reserveToken) : debtAsset);
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

    function recoverTokens(address token) public returns (uint256 amount) {
        if (token == address(0)) {
            // retrieve raw eth sent to ops multisig
            amount = address(this).balance;
            (bool success,) = FUN_OPS.call{value: amount}("");
            assert(success);
        } else {
            // use pullReserves() for these
            if (token == address(reserveToken)) revert InvalidToken();
            if (token == address(aToken)) revert InvalidToken();

            amount = IERC20x(token).balanceOf(address(this));
            
            // in the case we repay all debt and still have raw debtAsset left over from yield strategy
            // redeposit all debtAsset into aave. can pullReserves later if needed.
            if (token == address(debtAsset)) farm(debtAsset, amount);
            
            // retrieve raw tokens sent to ops multisig
            else IERC20x(token).transfer(FUN_OPS, IERC20x(token).balanceOf(address(this)));
        }

        emit PullReserves(msg.sender, token, amount);
    }

    function getContractSize(address _contract) private view returns (uint256 size) {
        assembly {
            size := extcodesize(_contract)
        }
    }
}
