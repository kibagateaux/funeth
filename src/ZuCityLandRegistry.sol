pragma solidity ^0.8.26;

// extr legl 
// staking to a property nor the initation of the sales process guarantess eventual ownership of the property
// possession of the NFT does not entitle you to any rights or ownership of the associate property




// is NFT contract
// allows any zuToken to be staked
// has list of valid zuTokens
// list of properties 
// property states = delisted, listed, reserved, purchasing, bought
// each property is an NFT

// stake()
// multiple people can stake to the same property
// zuTokens locked until reserved
// if reserved and buyer != staker. can withdraw
// represents total amount you want to invest into property including renovations, furnishing, Akiya Collective art commisions, etc.



// approveBuyer(uint256 lot, address buyer)
// 

// initBuy(uint256 lot)

// addZuToken(address zuToken)
// assert zuToken.ZU_CITY_TREASURY = zuCityTreasury (not a malicious tx, could be spoofed i guess)
// assert msg.sender = zuCityTreasury
// zuToken.reserveToken