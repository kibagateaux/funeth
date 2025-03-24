pragma solidity ^0.8.26;

// extr legl 
// staking to a property nor the initation of the sales process guarantess eventual ownership of the property
// possession of the NFT does not entitle you to any rights or ownership of the associate property.
// Only the entity that purchased the property and is listed on the deed has ownership and rights


// is NFT contract
// allows any nnToken to be staked
// has list of valid nnTokens
// list of properties is public. Though access to property details is restricted to nnToken holders
// property states = delisted, listed, reserved, purchasing, bought
// each property is an NFT

// Property struct ID > Property
// address city
// price USD 8 dec
// uri image
// Stakes[] stakes
// property details automapped to website via nft id

// Stakes struct
// uint128 lotID
// address nnToken
// uint256 stakeAmount
// address staker

// stake()
// multiple people can stake to the same property
// nnTokens locked until reserved
// if reserved and buyer != staker. can withdraw
// represents total amount you want to invest into property including renovations, furnishing, Akiya Collective art commisions, etc.

// approveBuyer(uint256 lot, address buyer)
// only cityOwner
// transfer NFT to them
// 


// initBuy(uint256 lot, address buyer)
// only cityOwner
// 

// addReserveToken(address nnToken)
// assert nnToken.ZU_CITY_TREASURY = nnCityTreasury (not a malicious tx, could be spoofed i guess)
// assert msg.sender = nnCityTreasury
// nnToken.reserveToken