
// // SPDX-License-Identifier: MIT

// pragma solidity ^0.8.16;

// import {Clones} from  "openzeppelin/proxy/Clones.sol";
// import {IModuleFactory} from "../../interfaces/IModuleFactory.sol";
// import {IRSAFactory} from "../../interfaces/IRSAFactory.sol";

// import {RevenueShareAgreement} from "./RevenueShareAgreement.sol";
// import {Spigot} from "../../modules/spigot/Spigot.sol";

// /**
//  * @title   - Debt DAO RSAFactory
//  * @notice  - Factory contract to deploy Spigot and Revenue Share Agreements
//  * @dev     - use ERC-1167 immutable proxies
//  */
// contract Factory is IModuleFactory, is Ownable {
//     address public rsaImpl;
//     address public WETH;
//     mapping(address => bool) public canTrade;

//     constructor(address _weth) {
//         rsaImpl = address(new RevenueShareAgreement());
//         WETH = _weth;
//     }

//     function deployRSA(
//         address _borrower,
//         address _creditToken,
//         uint8 _revenueSplit,
//          uint16 apr,
//         string memory _name,
//         string memory _symbol
//     ) public returns (address clone) {
//         clone = Clones.clone(rsaImpl);
//         RevenueShareAgreement(clone).initialize(
//             _borrower,
//             WETH,
//             _creditToken,
//             _apr,
//             _totalOwed,
//             _name,
//             _symbol
//         );

//         emit DeployedRSA(_borrower, _creditToken, clone, _initialPrincipal, _totalOwed, _revenueSplit);
//     }


// claimFees(address rsa, address to) { rsa.redeem(address(this), to, rsa.balanceOf(address(this))) }
// setTrader(address trader) { canTrade[trader] = true }
// initiateOrder(address rsa, address token, uint256 sellAmount, uint256 minBuyAmount, uint32 deadline) { if(!canTrade[msg.sender]) { revert NoTrade() }  rsa.initiateOrder(token, sellAmount, minBuyAmount, deadline) } }    
// }