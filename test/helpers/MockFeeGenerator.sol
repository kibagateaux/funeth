pragma solidity ^0.8.26;

import {ERC20} from "solady/tokens/ERC20.sol";

contract MockFeeGenerator {
    address owner;
    address constant ETH = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    ERC20 revenueToken;

    constructor(address _owner, address token) {
        owner = _owner;
        revenueToken = ERC20(token);
    }

    function claimPullPayment() external returns (bool) {
        require(msg.sender == owner, "Revenue: Only owner can claim");
        if (address(revenueToken) != ETH) {
            require(revenueToken.transfer(owner, revenueToken.balanceOf(address(this))), "Revenue: bad transfer");
        } else {
            payable(owner).transfer(address(this).balance);
        }
        return true;
    }

    function sendPushPayment() external returns (bool) {
        if (address(revenueToken) != ETH) {
            require(revenueToken.transfer(owner, revenueToken.balanceOf(address(this))), "Revenue: bad transfer");
        } else {
            payable(owner).transfer(address(this).balance);
        }
        return true;
    }

    function doAnOperationsThing() external returns (bool) {
        require(msg.sender == owner, "Revenue: Only owner can operate");
        return true;
    }

    function doAnOperationsThingWithArgs(uint256 val) external returns (bool) {
        require(val > 10, "too small");
        if (val % 2 == 0) return true;
        else return false;
    }

    function transferOwnership(address newOwner) external returns (bool) {
        require(msg.sender == owner, "Revenue: Only owner can transfer");
        owner = newOwner;
        return true;
    }

    receive() external payable {}
}
