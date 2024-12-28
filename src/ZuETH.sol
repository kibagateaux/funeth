pragma solidity ^0.8.26;

import "forge-std/console.sol";
import {IZuETH, IERC20x, IAaveMarket, ReserveData} from "./Interfaces.sol";

contract ZuETH is IZuETH {
    // Multisig deployed on Mainnet, Arbitrum, Base, OP,
    address public constant zuCityTreasury = address(0xC958dEeAB982FDA21fC8922493d0CEDCD26287C3);
    uint256 public constant MIN_DEPOSIT = 100_000_000; // to prevent aave math from causing reverts on small amounts from rounding decimal diffs. $100 USDC or 1e-9 ETH
    // uint256 public constant MIN_DEPOSIT = 100; // to prevent aave math from causing reverts on small amounts. $100 USDC or 1e-9 ETH
    uint256 public constant MIN_HEALTH_FACTOR = 6; // max 1/6 debt ratio on zueth deposits for loans
    uint256 public constant MIN_RESERVE_FACTOR = 18; // max debt ratio for treasury to pull excess interest

    uint8 public decimals;
    uint256 public totalSupply; // WETH change: we farm so self.balance != supply
    uint256 public totalCreditDelegated; // total delegated. NOT total currently borrowed.
    string public name;
    string public symbol;

    uint256 internal reserveVsATokenDecimals;
    /// Token to accept for home payments in ZuCity
    IERC20x public reserveToken;
    /// Aave Pool we want to use
    IAaveMarket public aaveMarket;
    /// Aave yield bearing token for reserveToken. Provides live zuETH balance.
    IERC20x public aToken;
    /// Aave variable debt token that we let popups borrow against ZuCity collateral
    IERC20x public debtToken;

    event Approval(address indexed me, address indexed mate, uint256 dubloons);
    event Transfer(address indexed me, address indexed mate, uint256 dubloons);
    
    /* who deposited, how much, where they want yield directed, who recruited mate */
    event Deposit(address indexed mate, address indexed receiver, uint256 dubloons, address indexed city, address referrer);
    event Withdrawal(address indexed me, uint256 dubloons);
    
    event Farm(address indexed market, address indexed reserve, uint256 dubloons);
    event PullReserves(address indexed market, address indexed reserve, uint256 dubloons);
    event Lend(address indexed treasurer, address indexed debtToken, address indexed popup, uint256 dubloons);


    error AlreadyInitialized();
    error UnsupportedChain();
    error InvalidReserveMarket();
    error InvalidTokens();
    error BelowMinDeposit();
    error NotEthReserve();
    error NotZuCity();
    error LoanFailed();
    error InvalidTreasuryOperation();

    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public creditOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function initialize(address _reserveToken, address market, address _debtToken, uint8 eMode, string memory _name, string memory _sym) public {
        if(address(reserveToken) != address(0)) revert AlreadyInitialized();
        
        // naive check if ZuCity governance is deployed on this chain
        if(getContractSize(zuCityTreasury) == 0) revert UnsupportedChain();
        
        ReserveData memory pool = IAaveMarket(market).getReserveData(address(_reserveToken));
        // Ensure aave market accepts the asset people deposit
        if(pool.aTokenAddress == address(0)) revert InvalidReserveMarket();

        name = _name;
        symbol = _sym;
        aaveMarket = IAaveMarket(market);
        reserveToken = IERC20x(_reserveToken);
        aToken = IERC20x(pool.aTokenAddress);
        debtToken = IERC20x(_debtToken);

        // Aave docs say eMode must be the same for delegator + borrower. Evidently not true and 0 is fine too.
        // aaveMarket.setUserEMode(eMode);
        reserveToken.approve(address(aaveMarket), type(uint256).max);

        uint8 reserveDecimals = reserveToken.decimals();
        decimals = reserveDecimals;
        uint8 aTokenDecimals = aToken.decimals();
        // assume aToken = 18 decimals and reserve token <= 18 decimals
        if(aTokenDecimals > reserveDecimals){
            reserveVsATokenDecimals = 10**(aTokenDecimals - reserveDecimals);
        }
        
        // Would make sense to do here but reverts if caller has no collateral yet
        // aaveMarket.setUserUseReserveAsCollateral(address(reserveToken), true);
    }


    function deposit(uint256 dubloons) public {
        _deposit(msg.sender, dubloons, address(this), address(this));
    }

    function depositWithPreference(address to, uint256 dubloons, address city, address referrer) public {
        _deposit(to, dubloons, city, referrer);
    }
    
    function depositAndApprove(address spender, uint256 dubloons) public {
        _deposit(msg.sender, dubloons, address(this), address(this));
        approve(spender, dubloons);
    }

    function _deposit(address receiver, uint256 dubloons, address city, address referrer) public {
        if(dubloons < MIN_DEPOSIT) revert BelowMinDeposit();
        reserveToken.transferFrom(msg.sender, address(this), dubloons);
        farm(reserveToken.balanceOf(address(this))); // implictly handles tokens sent directly
        console.log("depositng", dubloons);

        balanceOf[receiver] += dubloons;
        totalSupply += dubloons;
        emit Deposit(msg.sender, receiver, dubloons, city, referrer);
    }

    function farm(uint256 dubloons) public {
        // token approval in constructor and pullReserves
        aaveMarket.supply(address(reserveToken), dubloons, address(this), 200); // 200 = referall code. l33t "Zoo" 
        emit Farm(address(aaveMarket), address(reserveToken), dubloons);
    }

    function withdraw(uint256 dubloons) public {
        require(balanceOf[msg.sender] >= dubloons);
        balanceOf[msg.sender] -= dubloons;
        totalSupply -= dubloons;

        console.log("aToken balance", underlying());
        console.log("withdrawing", dubloons);

        // reserveToken.approve(address(aaveMarket), dubloons);
        aaveMarket.withdraw(address(reserveToken), dubloons, msg.sender);
        
        emit Withdrawal(msg.sender, dubloons);
    }

    function approve(address mate, uint256 dubloons) public returns (bool) {
        allowance[msg.sender][mate] = dubloons;
        emit Approval(msg.sender, mate, dubloons);
        return true;
    }

    function transfer(address mate, uint256 dubloons) public returns (bool) {
        return transferFrom(msg.sender, mate, dubloons);
    }

    function transferFrom(address me, address mate, uint256 dubloons) public returns (bool) {
        require(balanceOf[me] >= dubloons);

        if (me != msg.sender && allowance[me][msg.sender] != type(uint256).max) {
            require(allowance[me][msg.sender] >= dubloons);
            allowance[me][msg.sender] -= dubloons;
        }

        balanceOf[me] -= dubloons;
        balanceOf[mate] += dubloons;

        emit Transfer(me, mate, dubloons);

        return true;
    }

    function pullReserves(uint256 dubloons) public {
        _assertZuCity();
        
        aToken.transfer(zuCityTreasury, dubloons);
        
        reserveToken.approve(address(aaveMarket), type(uint256).max);
        
        // incase reserveToken doesnt support infinite approve, refresh on regular updates, not every deposit
        if(getHF() < MIN_RESERVE_FACTOR) revert InvalidTreasuryOperation();

        // make sure we can fulfill redemptions after pulling excess yield
        // TODO need to think through algo for calculating this. not that simple (or it could be)
        // deposits + interest - loans?, But dont want all loans repaid bc thats likely never to happen
        // if(underlying() < totalSupply) revert InvalidTreasuryOperation();
        emit PullReserves(address(aaveMarket), address(reserveToken), dubloons);
    }


    /**
     * @notice
     * @param city - zuzalu popup city to receive loan
     * @param dubloons - Should be Aave market denominated. Usually USD to 10 decimals
    */
    function lend(address city, uint256 dubloons) public {
        _assertZuCity();

        uint256 currentCredit = creditOf[city];
        creditOf[city] = dubloons;
        if(currentCredit > dubloons) {
            // new credit rating lower than before so reduce total
            totalCreditDelegated -= currentCredit - dubloons;
        } else {
            // improved credit rating so inc by diff
            totalCreditDelegated += dubloons - currentCredit;
        }

        // TODO calculate LTV of totalCreditDelegated < MIN_HEALTH_FACTOR
        // instead of current borrowed to ensure financial health
        // NEW:
        console.log("underlying bal before: ", underlying());
        _assertFinancialHealth(dubloons);
        console.log("underlying bal after: ", underlying());
        // OLD:
        // ensure we have a safe >5x overcollateralized to prevent liquidation
        // if(getHF() < MIN_HEALTH_FACTOR) revert InvalidTreasuryOperation();

        // retards throw error if u set collateral with 0 deposits so cant do on initialize.
        aaveMarket.setUserUseReserveAsCollateral(address(reserveToken), true);

        // allow popup to borrow against zucity collateral
        debtToken.approveDelegation(city, dubloons);

        // technically this will almost always make us frational reserve. 
        // but it is a self-repaying loan that eventually becomes solvent
        emit Lend(msg.sender, address(debtToken), city, dubloons);
    }

    
    function _assertZuCity() internal view {
        if(msg.sender != zuCityTreasury) revert NotZuCity();
    }

    function _assertFinancialHealth(uint256 newCreditAmount) internal {
        if(underlying() >= totalSupply) revert InvalidTreasuryOperation();
        if(getExpectedHF() < MIN_RESERVE_FACTOR) revert InvalidTreasuryOperation();
    }

    // function farmDeposits() public view returns(uint256) {
    //     return aToken.balanceOf(address(this));
    // }

    function underlying() public returns (uint256) {
        uint256 aTokenBalance = aToken.balanceOf(address(this));
        if(aTokenBalance == 0) return 0; //Early return if no balance

        // update liq index for accurate reporting. no ETH unfarmed!
        aaveMarket.withdraw(address(reserveToken), 1, address(this));
        aaveMarket.supply(address(reserveToken), 1, address(this), 200); // 200 = referall code. l33t "Zoo" 

        uint256 liquidityIndex = aaveMarket.getReserveData(address(reserveToken)).liquidityIndex;

        uint256 scaledBalance = aToken.scaledBalanceOf(address(this));
        console.log("svcaled b", scaledBalance);

        uint256 underlyingBalance = (scaledBalance * liquidityIndex) / 1e27;
        console.log("underlyingh b", underlyingBalance);

        if(reserveVsATokenDecimals != 0){
            underlyingBalance = underlyingBalance / reserveVsATokenDecimals;
        }
        console.log("decimaled b", underlyingBalance);
        // if(aTokenDecimals > decimals){
        //     underlyingBalance = underlyingBalance / (10**(aTokenDecimals - decimals));
        // } else if (decimals > aTokenDecimals){
        //      underlyingBalance = underlyingBalance * (10**(decimals - aTokenDecimals));
        // }

        return underlyingBalance;
    }


    /// @notice returns current health factor disregarding future potential debt from popup loans
    function getHF() public view returns (uint256) {
        (,,,,,uint256 healthFactor) = aaveMarket.getUserAccountData(address(this));
        return healthFactor;
    }

    /// @notice returns theoretical health factor if all credit extended is called at the same time
    function getExpectedHF() public view returns (uint256) {
        (,uint256 totalDebtBase,/*uint256 availableBorrow*/,,/* uint256 ltv */,uint256 hf) = aaveMarket.getUserAccountData(address(this));
        // TODO refactor to be predictive of credit delegated and max loans pulled
        // easiest / most gas efficient?
        // get current ltv and debt amounts? would need to scale dubloons to debt
        uint256 maxBorrowHF = (totalDebtBase * hf / totalCreditDelegated);
        // just approximate via proportion of current debt + LTV to simulated debt + LTV
        // if(totalCreditDelegated + newCreditAmount) * getHF() / totalCreditDelegated > MIN_LYV_THRESHOLD

        console.log("max borrow hf", maxBorrowHF);

        // return healthFactor;
        return maxBorrowHF;
    }
    
    function getCredit() public view returns (uint256) {
        (,,uint256 credit,,,) = aaveMarket.getUserAccountData(address(this));
        return credit;
    }

    function getCityCredit(address city) public view returns (uint256) {
        return debtToken.borrowAllowance(address(this), city);
    }

    function getDebt() public view returns (uint256) {
        (,uint256 debt,,,,) = aaveMarket.getUserAccountData(address(this));
        return debt;
    }

    function getContractSize(address _contract) private view returns (uint256) {
        uint256 size;
        assembly {
            size := extcodesize(_contract)
        }
        return size;
    }

    // TODO add rescue() = WETH.call{value: this.balance}; farm(this.balance); allows zuCity to send back to original sender bc not included in totalSupply
}