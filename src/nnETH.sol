pragma solidity ^0.8.26;

import "forge-std/console.sol";
import {INNETH, IERC20x, IAaveMarket, ReserveData} from "./Interfaces.sol";

contract NNETH is INNETH {
    // Multisig deployed on Mainnet, Arbitrum, Base, OP,
    address public constant ZU_CITY_TREASURY = address(0xC958dEeAB982FDA21fC8922493d0CEDCD26287C3);
    uint64 public constant MIN_DEPOSIT = 100_000_000; // to prevent aave math from causing reverts on small amounts from rounding decimal diffs. $100 USDC or 0.5 ETH ETH
    // TODO figure out lowest amount where aave tests dont fail
    // uint256 public constant MIN_DEPOSIT = 100; // to prevent aave math from causing reverts on small amounts. $100 USDC or 1e-9 ETH
    
    /// @notice min health factor for user to redeem to prevent malicious liquidations. 2 = Redeems until debt = 50% of nnETH TVL
    uint8 public constant MIN_REDEEM_FACTOR = 2;
    /// @notice min health factor for treasury to pull excess interest. 8 = ~12% of total nnETH TVL can be delegated
    uint8 public constant MIN_RESERVE_FACTOR = 8;
    /// @notice used to convert AAVE LTV to HF calc
    uint16 public constant BPS_COEFFICIENT = 1e4;

    /// @notice full decimal offset between reserveToken and aToken e.g. 1e10 not 10
    uint256 public reserveVsATokenDecimalOffset;

    /// @notice nnETH token decimals. same as reserveToken decimals
    uint8 public decimals;
    /// @notice decimals for token we borrow for use in HF calculations
    uint8 public debtTokenDecimals;
    /// @notice total reserveToken deposited, denominated in reserve decimals.
    uint256 public totalSupply;
    /// @notice total delegated. NOT total currently borrowed. Denominated in debtToken
    uint256 public totalCreditDelegated;

    string public name;
    string public symbol;


    /// @notice Token to accept for home payments in nnCity
    IERC20x public reserveToken;
    /// @notice Aave Pool for lending + borrowing
    IAaveMarket public aaveMarket;
    /// @notice Aave yield bearing token for reserveToken. Provides total ETH balance of nnETH contract.
    IERC20x public aToken;
    /// @notice Aave variable debt token that we let popups borrow against nnCity collateral
    IERC20x public debtToken;

    event Approval(address indexed me, address indexed mate, uint256 dubloons);
    event Transfer(address indexed me, address indexed mate, uint256 dubloons);

    ///@notice who deposited, how much, where they want yield directed, who recruited mate
    event Deposit(address indexed mate, address indexed receiver, uint256 dubloons, address indexed city, address referrer);
    ///@notice who withdrew, how much
    event Withdrawal(address indexed me, uint256 dubloons);
    ///@notice where we are farming, what token, how much was deposited
    event Farm(address indexed market, address indexed reserve, uint256 dubloons);
    ///@notice where yield was sent to, how much
    event PullReserves(address indexed treasurer, uint256 dubloons);
    ///@notice who underwrote loan, what token is borrowed, who loan was given to, amount of tokens lent
    event Lend(address indexed treasurer, address indexed debtToken, address indexed popup, uint256 dubloons);

    error AlreadyInitialized();
    error UnsupportedChain();
    error InvalidReserveMarket();
    error InvalidTokens();
    error BelowMinDeposit();
    error NotEthReserve();
    error NotnnCity();
    error LoanFailed();
    error InvalidTreasuryOperation();
    error InsufficientReserves();
    error MaliciousWithdraw();
    error CreditRisk();
    error NoCredit();

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // TODO easier to enfore loans within the contract e.g. nnETH.borrow()instead of delegated credit
    mapping(address => uint256) public credited; // TODO? make City struct with creditedUSDC + delegatedETH

    // TODO if delegated credit doesnt work just track everything in this contract. maznn
    // struct Loan {
    //     uint256 totalCredit; // total credit extended to city. revolving.
    //     uint256 currentDebt; // includes principal + all interest accrued up until lastLiquidityIndex
    //     uint256 lastLiquidityIndex; // last time loan was updated
    // }
    // mapping(address => Loan) public cityLoans;
    //     function borrow(address city, uint256 amount) public {
    //     if(cityLoans[city].totalCredit == 0) revert NoCredit();
    //     if(msg.sender != city) revert NotnnCity();
    //     (,,,,,,,, uint256 liquidityIndex, uint256 variableBorrowIndex,,,,, , , , ) = IAaveDataProvider(aaveDataProvider).getReserveData(address(debtToken));

    //     cityLoans[city].currentDebt += amount;
    //     cityLoans[city].lastLiquidityIndex = liquidityIndex;
    //     aaveMarket.borrow(address(debtToken), amount, 2, 200, address(this));
    //     debtToken.transfer(city, amount);
    // }


    // function repay(address city, uint256 amount) external {
    //     (,,,,,,,, uint256 liquidityIndex, uint256 variableBorrowIndex,,,,, , , , ) = IAaveDataProvider(aaveDataProvider).getReserveData(asset);
    //     uint256 lastIndex = userDebtInfo[user][asset].lastBorrowIndex;
    //     uint256 currentPrincipal = userDebtInfo[user][asset].principalDebt;

    //     // Simplified interest calculation (needs refinement based on Aave's formula)
    //     uint256 interestAccrued = (currentPrincipal * (variableBorrowIndex - lastIndex)) / lastIndex;

    //     // Update principal after repaying (ignoring interest in this simplified example)
    //     userDebtInfo[user][asset].principalDebt -= amount;
    //     userDebtInfo[user][asset].lastBorrowIndex = variableBorrowIndex;
    // }


    function initialize(address _reserveToken, address market, address _debtToken, uint8 eMode, string memory _name, string memory _sym) public {
        if(address(reserveToken) != address(0)) revert AlreadyInitialized();
        
        // naive check if nnCity governance is deployed on this chain
        if(getContractSize(ZU_CITY_TREASURY) == 0) revert UnsupportedChain();
        
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
        if(aTokenDecimals >= reserveDecimals) {
            // = 1 if decimals are same value
            reserveVsATokenDecimalOffset = 10**(aTokenDecimals - reserveDecimals);
        }
        
        try debtToken.decimals() returns (uint8 dec) {
            debtTokenDecimals = dec;
            return;
        } catch (bytes memory _err) {
            debtTokenDecimals = 18;
        }

        // Would make sense to do here but reverts if caller has no collateral yet
        // aaveMarket.setUserUseReserveAsCollateral(address(reserveToken), true);
    }



    function deposit(uint256 dubloons) public {
        _deposit(msg.sender, dubloons, address(ZU_CITY_TREASURY), address(this));
    }

    function depositWithPreference(address to, uint256 dubloons, address city, address referrer) public {
        _deposit(to, dubloons, city, referrer);
    }
    
    /// @notice helper function for integrators e.g. LP farming to simplify UX
    function depositAndApprove(address spender, uint256 dubloons) public {
        _deposit(msg.sender, dubloons, address(ZU_CITY_TREASURY), address(this));
        approve(spender, dubloons);
    }

    function _deposit(address receiver, uint256 dubloons, address city, address referrer) public {
        if(dubloons < MIN_DEPOSIT) revert BelowMinDeposit();
        reserveToken.transferFrom(msg.sender, address(this), dubloons);
        farm(reserveToken.balanceOf(address(this))); // scoop tokens sent directly too
        mint(receiver, dubloons);
        emit Deposit(msg.sender, receiver, dubloons, city, referrer);
    }

    function mint(address to, uint256 dubloons) private {
        balanceOf[to] += dubloons;
        totalSupply += dubloons;
    }

    function farm(uint256 dubloons) public {
        // token approval in constructor and pullReserves
        aaveMarket.supply(address(reserveToken), dubloons, address(this), 200); // 200 = referall code. l33t "Zoo" 

        emit Farm(address(aaveMarket), address(reserveToken), dubloons);
    }

    function withdraw(uint256 dubloons) public {
        balanceOf[msg.sender] -= dubloons;
        totalSupply -= dubloons;

        aaveMarket.withdraw(address(reserveToken), dubloons, msg.sender);
        
        if(getExpectedHF() < MIN_REDEEM_FACTOR) revert MaliciousWithdraw();

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
    
    // nnETH Treasury functions

    function _assertTreasury() internal view {
        if(msg.sender != ZU_CITY_TREASURY) revert NotnnCity();
    }

    function _assertFinancialHealth() internal view {
        if(totalSupply > underlying()) revert InsufficientReserves();
        if(getExpectedHF() < MIN_RESERVE_FACTOR) revert CreditRisk();
    }


    function pullReserves(uint256 dubloons) public {
        _assertTreasury();

        // checked in _assertFinancialHealth. Can do before external call if needed for security
        // if(getYieldEarned() < dubloons) revert InsufficientReserves();

        aToken.transfer(ZU_CITY_TREASURY, dubloons);
        
        // assert financial health *after* pulling reserves.
        _assertFinancialHealth();
        
        // incase reserveToken doesnt support infinite approve, refresh but not on every deposit
        reserveToken.approve(address(aaveMarket), type(uint256).max);

        emit PullReserves(msg.sender, dubloons);
    }


    /**
     * @notice Allow projects to borrow against nnCity collateral with Aave credit delegation.
        Technically this will almost always make us frational reserve. 
        But it is a self-repaying loan that eventually becomes solvent
     * @param city - nnzalu popup city to receive loan
     * @param dubloons - Should be Aave market denominated. Usually USD to 10 decimals
    */
    function lend(address city, uint256 dubloons) public {
        _assertTreasury();

        uint256 currentCredit = credited[city];
        credited[city] = dubloons;
        if(currentCredit > dubloons) {
            // new credit rating lower than before so reduce total
            totalCreditDelegated -= currentCredit - dubloons;
        } else {
            totalCreditDelegated += dubloons - currentCredit;
        }

        _assertFinancialHealth();

        // throws error if u set collateral with 0 deposits so cant do on initialize.
        aaveMarket.setUserUseReserveAsCollateral(address(reserveToken), true);

        // allow popup to borrow against nncity collateral
        debtToken.approveDelegation(city, dubloons);

        emit Lend(msg.sender, address(debtToken), city, dubloons);
    }

    /// @notice returns worst case scenario health factor if all credit extended is borrowed at the same time
    function getExpectedHF() public view returns (uint8) {
        // ideally use liquidationThreshold not ltv but aave uses ltv for "borrowable" amount so would make tests messier
        (uint256 totalCollateralBase,uint256 totalDebtBase,uint256 borrowable,uint256 liquidationThreshold, uint256 ltv, uint256 hf) = aaveMarket.getUserAccountData(address(this));

        
        // aave assumes debt amount is usd in 8 decimals. convert debt token decimals to match
        // https://github.com/aave-dao/aave-v3-origin/blob/a0512f8354e97844a3ed819cf4a9a663115b8e20/src/contracts/protocol/libraries/logic/LiquidationLogic.sol#L72
        // assumes we only allow stablecoins for borrowing.
        // Also assumes debtToken decimals = actual token decimals

        // TODO fails if we have debt > credit delegated e.g. interest or price increase since delegation
        uint256 scaledDelegatedCredit = convertToDecimal(totalCreditDelegated, debtTokenDecimals, 8);
        // uint256 unborrowedDebt = scaledDelegatedCredit - totalDebtBase;
        // console.log("getExpectedHF:  unborrowedDebt", unborrowedDebt);

        // uint256 scaledDelegatedCredit = convertToDecimal(totalCreditDelegated, debtTokenDecimals, 8);
        uint256 unborrowedDebt2 = totalDebtBase > scaledDelegatedCredit ? totalDebtBase : scaledDelegatedCredit - totalDebtBase;
        console.log("getExpectedHF:  totalDebtBase", totalDebtBase);
        console.log("getExpectedHF:  scaledDelegatedCredit", scaledDelegatedCredit);
        console.log("getExpectedHF:  unborrowedDebt2", unborrowedDebt2);

        uint256 maxDebt = totalDebtBase + unborrowedDebt2;

        // if already borrowing all available credit then current hf is accurate
        // if(unborrowedDebt2 == 0) return uint8(convertToDecimal(hf, 18, 2)); // returns 100

        if (maxDebt == 0) {
            // Avoid division by zero
            return uint8(convertToDecimal(hf, 18, 2)); // returns 100
        }

        uint256 maxBorrowedHF = (totalCollateralBase * ltv) / maxDebt / BPS_COEFFICIENT;
        return uint8(maxBorrowedHF);
        console.log("getExpectedHF:  maxBorrowedHF", maxDebt);
        console.log("getExpectedHF:  maxBorrowedHF", maxBorrowedHF);

        // get proportional hf based based on current vs future debt 
        // return uint8(convertToDecimal((hf * totalDebtBase) / maxDebt, 18, 0));
    }

    /// Getter functions 

    /// @notice total amount of tokens deposited in aave. Denominated in reserrveToken decimals
    function underlying() public view returns (uint256) {
        return aToken.balanceOf(address(this)) / reserveVsATokenDecimalOffset;
    }

    /// @notice returns current health factor disregarding future potential debt from NN loans
    function getYieldEarned() public view returns (uint256) {
        return underlying() - totalSupply - 1; // -1 to account for rounding errors in aave
    }

    /// @notice returns current health factor disregarding future potential debt from NN loans
    function getHF() public view returns (uint256) {
        (,,,,,uint256 healthFactor) = aaveMarket.getUserAccountData(address(this));
        return convertToDecimal(healthFactor, 18, 2);
    }

    function getDebt() public view returns (uint256) {
        (,uint256 debt,,,,) = aaveMarket.getUserAccountData(address(this));
        return convertToDecimal(debt, 8, debtTokenDecimals);
    }

    function getAvailableCredit() public view returns (uint256) {
        (,,uint256 creditLeft,,,) = aaveMarket.getUserAccountData(address(this));
        return convertToDecimal(creditLeft, 8, debtTokenDecimals);
    }

    function getTotalCredit() public view returns (uint256) {
        (,uint256 debt, uint256 creditLeft,,,) = aaveMarket.getUserAccountData(address(this));
        return convertToDecimal(debt + creditLeft, 8, debtTokenDecimals);
    }

    function getCityCredit(address city) public view returns (uint256) {
        return debtToken.borrowAllowance(address(this), city);
    }

    function getContractSize(address _contract) private view returns (uint256) {
        uint256 size;
        assembly {
            size := extcodesize(_contract)
        }
        return size;
    }

    function convertToDecimal(uint256 amount, uint8 currentDecimals, uint8 targetDecimals) public pure returns (uint256) {
        if(currentDecimals == targetDecimals) return amount;
        if(currentDecimals > targetDecimals) {
            return amount / 10**(currentDecimals - targetDecimals);
        } else {
            return amount * 10**(targetDecimals - currentDecimals);
        }
    }

    receive() external payable {
        if(msg.value < MIN_DEPOSIT) revert BelowMinDeposit();
        // assumes reserveToken is ETH. reverts on deposit/farm if not

        reserveToken.deposit{value: msg.value}();
        farm(msg.value);
        mint(msg.sender, msg.value);
    }
}