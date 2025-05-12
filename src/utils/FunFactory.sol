pragma solidity ^0.8.26;


import {LibClone} from "solady/utils/LibClone.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {IFunETH, IFunFunding, IFunCityLandRegistry} from "../Interfaces.sol";

import {FunETH} from "../FunETH.sol";
import {FunCityLandRegistry} from "../FunCityLandRegistry.sol";
import {FunFunding} from "./FunFunding.sol";

contract FunFactory is Ownable {
    address immutable aaveMarket;
    address immutable WETH;

    address public funTokenImplementation;
    address public rsaImplementation;
    address public landRegistryImplementation;

    address public funETH;
    address public funUSDC;
    uint16 public funLoanFee;
    uint16 public funCityClosingFee;
    
    constructor(address _aaveMarket, address _weth) {
        aaveMarket = _aaveMarket;
        WETH = _weth;
        _initializeOwner(msg.sender);

        funTokenImplementation = address(new FunETH());
        rsaImplementation = address(new FunFunding());
    }

    function initLandRegistry(address curator) public onlyOwner {
        assert(funETH != address(0) && funUSDC != address(0));
        landRegistryImplementation = address(new FunCityLandRegistry());
    }

    function deployFunToken(address reserveToken, address debtToken, string memory name, string memory symbol) public returns (address) {
        address clone = LibClone.cloneDeterministic(funTokenImplementation, keccak256(abi.encodePacked(name)));
        IFunETH(clone).initialize(reserveToken, aaveMarket, debtToken, name, symbol);
        return clone;
    }

    function deployFunFunding(address borrower, address loanToken, uint16 apr, string memory name, string memory symbol) public returns (address) {
        address clone = LibClone.cloneDeterministic(rsaImplementation, keccak256(abi.encodePacked(borrower, apr, name)));
        IFunFunding(clone).initialize(borrower, WETH, loanToken, apr, name, symbol);
        return clone;
    }

    function deployLandRegistry(address curator) public returns (address) {
        address clone = LibClone.cloneDeterministic(landRegistryImplementation, keccak256(abi.encodePacked(block.timestamp)));
        IFunCityLandRegistry(clone).initialize(funETH, funUSDC, curator);
        return clone;
    }

    /** admin functions */
    function setDefaultFunTokens(address _funETH, address _funUSDC) public onlyOwner {
        funETH = _funETH;
        funUSDC = _funUSDC;
    }

    function setFunLoanFee(uint16 _funLoanFee) public onlyOwner {
        funLoanFee = _funLoanFee;
    }

    function setFunCityClosingFee(uint16 _funCityClosingFee) public onlyOwner {
        funCityClosingFee = _funCityClosingFee;
    }
}