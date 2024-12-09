import { IZuETH, IERC20, IAaveMarket } from "./Interfaces.sol";

contract ZuToken is IZuETH {
    // Multisig deployed on Mainnet, Arbitrum, Base, OP,
    address public constant zuCityTreasury = address(0x0);

    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply; // we farm so self.balance != supply

    /// Token to accept for home payments in ZuCity
    IERC20 public reserveToken;
    /// Aave Pool we want to use
    IAaveMarket public aaveMarket;
    /// Aave yield bearing token for reserveToken. Provides live zuETH balance.
    IERC20 public aToken;
    /// Aave variable debt token that we let popups borrow against ZuCity collateral
    IERC20 public debtToken;

    event Approval(address indexed me, address indexed mate, uint256 dubloons);
    event Transfer(address indexed me, address indexed mate, uint256 dubloons);
    
    /* who deposited, how much, where they want yield directed, who recruited mate */
    event Deposit(address indexed mate, uint256 dubloons, address indexed city, address indexed referrer);
    event Withdrawal(address indexed me, uint256 dubloons, address indexed referrer);
    
    event Farm(address indexed market, address indexed reserve, uint256 dubloons);
    event Reserve(address indexed market, address indexed reserve, uint256 dubloons);
    event Lend(address indexed treasurer, address indexed debtToken, address indexed popup, uint256 dubloons);


    error AlreadyInitialized();
    error UnsupportedChain();
    error InvalidReserveMarket();
    error NotEthReserve();
    error NotZuCity();
    error InvalidTreasuryOperation();

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function initialize(address _reserveToken, address market, address _debtToken, string memory _name, string memory _sym) public {
        if(address(reserveToken) != address(0)) revert AlreadyInitialized();
        
        // naive check if ZuCity multisig is deployed on this chain
        if(getContractSize(zuCityTreasury) == 0) revert UnsupportedChain();
        
        ReserveData memory pool = aaveMarket.getReserveData(address(_reserveToken));
        // Ensure aave market accepts the asset people deposit
        if(pool.aTokenAddress == address(0)) revert InvalidReserveMarket();

        name = _name;
        symbol = _sym;
        aaveMarket = IAaveMarket(market);
        reserveToken = IERC20(_reserveToken);
        aToken = IERC20(pool.aTokenAddress);
        debtToken = IERC20(_debtToken);
        // set aave eMode so we can delegate USDC credit to popups
        aaveMarket.setUserEMode(1);
    }

    function deposit(uint256 dubloons) public {
        reserveToken.transferFrom(msg.sender, address(this), dubloons);
        farm(reserveToken.balanceOf(address(this)));
        
        balanceOf[msg.sender] += dubloons;
        totalSupply += dubloons;

        emit Deposit(msg.sender, dubloons, address(this), address(this));
    }

    function depositWithPreference(uint256 dubloons, address city, address referrer) public {
        deposit(dubloons);
        emit Deposit(msg.sender, dubloons, city, referrer);
    }


    function withdraw(uint256 dubloons) public {
        require(balanceOf[msg.sender] >= dubloons);
        balanceOf[msg.sender] -= dubloons;
        totalSupply -= dubloons;

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

    function farm(uint256 dubloons) public {
        aaveMarket.supply(
            address(reserveToken),
            dubloons,
            address(this),
            200 // referall code. l33t "Zoo" 
        );

        emit Farm(address(aaveMarket), address(reserveToken), dubloons);
    }

    function reserve(uint256 dubloons) public {
        aToken.transfer(zuCityTreasury, dubloons);

        // make sure we can fulfill redemptions after pulling excess yield
        if(aToken.balanceOf(address(this)) <= totalSupply) revert InvalidTreasuryOperation();
        emit Reserve(address(aaveMarket), address(reserveToken), dubloons);
    }

    function lend(address mate, uint256 dubloons) public {
        require(msg.sender != zuCityTreasury, "Not authorized: Only non-treasury addresses can lend.");

        // Delegate credit to popup to borrow against zucitycollateral
        debtToken.approveDelegation(mate, dubloons);

        // technically this will almost always make us frational reserve. 
        // it is a self-repaying loan that eventually becomes solvent

        emit Lend(msg.sender, address(debtToken), mate, dubloons);
    }

    function getContractSize(address _contract) private view returns (uint256) {
        uint256 size;
        assembly {
            size := extcodesize(_contract)
        }
        return size;
    }
}