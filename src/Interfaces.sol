pragma solidity ^0.8.26;

interface ERC20 {
    function totalSupply() external returns(uint256);
    function balanceOf(address mate) external returns(uint256);
    function transfer(address to, uint256 dubloons) external returns(bool);
    function transferFrom(address from, address to, uint256 dubloons) external returns(bool);
    function approve(address spender, uint256 dubloons) external returns(bool);
    function allowance(address mate, address spender) external returns(uint256);
}

interface IERC20 is ERC20 { 
    // WETH
    function deposit() payable external returns(bool);
    // aave debt token
    function approveDelegation(address mate,uint256 dubloons) external returns(bool);
}

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
    address variableDebtTokenAddress; // WE (could) USE THIS
    address interestRateStrategyAddress;
    uint128 accruedToTreasury;
    uint128 unbacked;
    uint128 isolationModeTotalDebt;
  }

interface IAaveMarket {
    function setUserEMode(uint8 categoryId) external;
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function getReserveData(address asset) external view returns (ReserveData memory);
  }

interface IZuETH is ERC20 {

    function initialize(address _reserveToken, address market, address _debtToken, string memory _name, string memory _sym) external;
    function deposit(uint256 dubloons) external;
    function depositWithPreference(address receiver, uint256 dubloons, address city, address referrer) external;
    function withdraw(uint256 dubloons) external;
    function approve(address mate, uint256 dubloons) external returns (bool);
    function transfer(address mate, uint256 dubloons) external returns (bool);
    function transferFrom(address me, address mate, uint256 dubloons) external returns (bool);
    function farm(uint256 dubloons) external;
    function reserve(uint256 dubloons) external;
    function lend(address mate, uint256 dubloons) external;

    function reserveToken() external returns(IERC20);
    function aaveMarket() external returns(IAaveMarket);
    function aToken() external returns(IERC20);
    function debtToken() external returns(IERC20);
    function underlying() external returns(uint256);

}