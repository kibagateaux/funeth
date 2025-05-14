pragma solidity ^0.8.26;

import {ERC4626} from "solady/tokens/ERC4626.sol";
import {IFunETH, IERC20x, IAaveMarket, ReserveData, IFunFactory, IFunFunding} from "./Interfaces.sol";
import {Ownable} from "solady/auth/Ownable.sol";

// TODO make ERC4626. add reindexShares() that adds getYieldEarned() to underlying share value.

contract FunETH is IFunETH, ERC4626, Ownable {
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
    IERC20x internal reserveToken;
    // TODO does anything below need to actually be public except for testing?
    /// @notice Aave Pool for lending + borrowing
    IAaveMarket public aaveMarket;
    /// @notice Aave yield bearing token for reserveToken. Provides total ETH balance of funETH contract.
    IERC20x public aToken;
    /// @notice Aave variable debt token that we let popups borrow against funCity collateral
    IERC20x public debtToken; // TODO remove this and debtTokenDecimals vestigial
    /// @notice Address of the actual debt asset. e.g. USDC
    address public debtAsset;

    mapping(address => uint256) public vaults;

    ///@notice who deposited, how much, where they want yield directed, who recruited mate
    event Deposit(
        address indexed mate, address indexed receiver, uint256 dubloons, address indexed vault, address referrer
    );
    event Signal(address indexed mate, address indexed vault, address indexed referrer, uint256 shares);
    ///@notice who withdrew, how much
    event Withdrawal(address indexed me, address indexed to, uint256 dubloons);
    ///@notice where we are farming, what token, how much was deposited
    event Farm(address indexed market, address indexed reserve, uint256 dubloons);
    ///@notice where yield was sent to, how much
    event PullReserves(address indexed treasurer, address indexed token, uint256 dubloons);
    ///@notice who underwrote loan, what token is borrowed, who loan was given to, amount of tokens lent
    event Lend(
        address indexed treasurer, address indexed debtToken, address indexed vault, uint256 dubloons, address fun_dingo
    );
    event LoanRepaid(address indexed vault, address indexed fun_dingo, uint256 dubloons);
    event LoanClosed(address indexed vault, address indexed fun_dingo);

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

    function decimals() public view override(IFunETH, ERC4626) returns (uint8) {
        return _decimals;
    }

    function asset() public view override(IFunETH, ERC4626) returns (address) {
        return address(reserveToken);
    }

    function totalAssets() public view override returns (uint256) {
        return underlying();
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
        if(address(reserveToken) != address(0)) revert AlreadyInitialized();

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
        ERC4626(debtAsset).approve(address(aaveMarket), type(uint256).max);
        reserveToken.approve(address(aaveMarket), type(uint256).max);

        uint8 reserveDecimals = reserveToken.decimals();
        _decimals = reserveDecimals;
        uint8 aTokenDecimals = aToken.decimals();
        // assume aToken = 18 decimals and reserve token <= 18 decimals
        if (aTokenDecimals >= reserveDecimals) {
            // = 1 if decimals are same value aka no change
            reserveVsATokenDecimalOffset = 10 ** (aTokenDecimals - reserveDecimals);
        }

        // aave automatically enables non-isolated assets (aka majors) on initial supply

    }

    function _useVirtualShares() internal view virtual override returns (bool) {
        return false;
    }

    /// @dev WETH compliant interface
    function deposit(uint256 dubloons) public virtual returns (uint256 shares) {
        shares = convertToAssets(dubloons);
        _deposit(msg.sender, msg.sender, dubloons, shares);
        emit Signal(msg.sender, address(FUN_OPS), address(this), shares);
    }

    /// @dev ERC4626 compliant interface
    function deposit(uint256 dubloons, address receiver) public virtual override returns (uint256 shares) {
        shares = convertToAssets(dubloons);
        _deposit(msg.sender, receiver, dubloons, shares);
        emit Signal(msg.sender, address(FUN_OPS), address(this), shares);
    }

    function depositWithPreference(uint256 dubloons, address receiver, address vault, address referrer) public returns (uint256 shares) {
        shares = convertToAssets(dubloons);
        _deposit(msg.sender, receiver, dubloons, shares);
        emit Signal(msg.sender, vault, referrer, shares);
    }

    /// @notice helper function for integrators e.g. LP farming to simplify UX
    function depositAndApprove(address spender, uint256 dubloons) public returns (uint256 shares) {  
        shares = convertToAssets(dubloons);
        approve(spender, shares);
        _deposit(msg.sender, msg.sender, dubloons, shares);
        emit Signal(msg.sender, address(FUN_OPS), address(this), shares);
    }

    function _deposit(address by, address to, uint256 assets, uint256 shares) internal virtual override {
        if (assets < MIN_DEPOSIT) revert BelowMinDeposit(); // TODO remove?
        if (to == address(0)) revert InvalidReceiver();

        super._deposit(by, to, assets, shares);

        farm(address(reserveToken), assets); // schloop tokens sent directly too
    }

    function farm(address _reserveToken, uint256 dubloons) public {
        // token approval in pullReserves
        aaveMarket.supply(address(_reserveToken), dubloons, address(this), 200); // 200 = referall code. l33t "Zoo"
        emit Farm(address(aaveMarket), address(_reserveToken), dubloons);
    }

    /// @dev WETH compliant interface
    function withdraw(uint256 dubloons) public returns (uint256 shares) {
        shares = convertToShares(dubloons);
        _withdraw(msg.sender, msg.sender, msg.sender, dubloons, shares);
    }

    function _withdraw(address by, address to, address owner, uint256 assets, uint256 shares) internal virtual override {
        super._withdraw(owner, to, owner, assets, 0);

        aaveMarket.withdraw(address(reserveToken), assets, to);
        // check *after* withdrawing and aave updates collateral balance
        if (getExpectedHF() < MIN_REDEEM_FACTOR) revert MaliciousWithdraw();
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
            // aDebtAsset (>funReserve) -> debtAsset (>funReserve) -> funDebtAsset (>funOps)
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
    function refresh(bool isReserveToken) public {
        if (isReserveToken) {
            reserveToken.approve(address(aaveMarket), type(uint256).max);
        } else {
            IERC20x(debtAsset).approve(address(aaveMarket), type(uint256).max);
            ReserveData memory pool = aaveMarket.getReserveData(debtAsset);
        }
    }

    /**
     * @notice Allow projects to borrow against funCity collateral with Aave credit delegation.
     *     Technically this will almost always make us frational reserve.
     *     But it is a self-repaying loan that eventually becomes solvent
     * @param vault - nnzalu popup vault to receive loan.
     * @param fun_dingo - ERC4626 to deposit for yield. We assume only FunFunding contract
     * @param dubloons - Should be Aave market denominated. Usually USD to 10 decimals
     */
    function lend(address vault, address fun_dingo, uint256 dubloons) public onlyOwner {
        // TODO remove vault struct? more brittle code and doesnt serve a purpose except 
        // ensuring 1:1 loan per vault which can be gamed anyway by using a different ctiy address

        aaveMarket.borrow(debtAsset, dubloons, AAVE_DEBT_INTEREST_MODE, 200, address(this));
        IERC20x(debtAsset).approve(fun_dingo, dubloons);

        vaults[vault] = vaults[vault] + IFunFunding(fun_dingo).deposit(dubloons, address(this));
        _assertFinancialHealth();

        emit Lend(msg.sender, address(debtAsset), vault, dubloons, fun_dingo);
    }

    function repay(address vault, uint256 dubloons) public {
        // TODO no problem letting anyone call for loans bc alwauys profit
        // but if supporting any 4626 then need to gatekeep to prevent griefing by making us pull at a loss, taking withdraw fees immeditaely, etc.

        // TODO decide if tracking in shares vs assets per vault. assets is easier for aave integration
        uint256 owed = vaults[vault];
        if (owed == 0) revert CityNotLent();
        // if (dubloons > creditInfo.owed) revert InvalidLoanClaim();

        // Even if status == INIT/CANCELED we get back total expected tokens with redeem()
        try IFunFunding(vault).withdraw(dubloons, address(this), address(this)) returns (uint256 assets) {
            // TODO should save rsa rate in cities? Easier to calculate non-funfunding here while maintaining assurances
            // making lend/repay more flexible for higher yield strategies is pretty good.

            // _repayOrComp deals with aave specific lending/farming logic.
            _repayOrCompound(dubloons);

            // our accounting is based on vaults[vault].owed
            if (dubloons == owed) {
                emit LoanRepaid(vault, vault, dubloons);
                emit LoanClosed(vault, vault);
                delete vaults[vault];
            } else {
                vaults[vault] = owed - dubloons;
                emit LoanRepaid(vault, vault, dubloons);
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
    // TODO remove, vesitigial with totalAssets() for 4626
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
