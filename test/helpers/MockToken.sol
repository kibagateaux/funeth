import {ERC20} from "solady/tokens/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20() {}

    function name() public view virtual override returns (string memory) {
        return "Mock Token";
    }

    function symbol() public view virtual override returns (string memory) {
        return "MOCK";
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burnFrom(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
