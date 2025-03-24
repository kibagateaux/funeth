pragma solidity ^0.8.26;

// extr legl 
// staking to a property nor the initation of the sales process guarantees eventual ownership of the property
// possession of the NFT does not entitle you to any rights or ownership of the associate property.
// Only the entity that purchased the property and is listed on the deed has ownership and rights
// Individual Property owners may encode rights into the owning/operating entity of the property that gives NFT holders rights and/or ownership
// Only Niggano Land Management, subsidiary, or affiliate must have exclusive property managment entity for all properties listed in the registry after purchase
// 


// is NFT contract
// allows any nnToken to be staked
// has list of valid nnTokens
// list of properties is public. Though access to property details is restricted to nnToken holders
// property states = delisted, listed, purchasing, bought
// each property is an NFT

// Property struct ID > Property
// address city
// price USD 8 dec
// uri image
// uint32 buyer (stake)
// uint32[] stakes
// property details automapped to website via nft id

// Stakes struct ID > Stake
// uint32 lotID
// address staker
// address nnToken
// uint128 stakeAmount


// stake()
// multiple people can stake to the same property
// only callable when status == listed
// nnTokens locked until reserved
// if reserved and buyer != staker. can withdraw
// represents total amount you want to invest into property including renovations, furnishing, Akiya Collective art commisions, etc.

// approveBuyer(uint32 lot, address buyer)
// only cityOwner
// transfer NFT to them
// 

// unstake() 
// only callable when not listed
// only callable if not owner
// deletes stake from property
// returns all nnTokens to staker

// initBuy(uint32 lot, address buyer)
// only cityOwner
// transfers stake buyer stake asset to city
// removes all other stakes from property
// updates property state to reserved
// 

// cancelPurchase(uint32 lot)
// only cityOwner
// transfers buyers stake back to buyer
// 
// updates property state to listed

// delistProperty(uint32 lot)
// only cityOwner
// updates property state to delisted
// 

// listProperty(uint32 lot)
// only cityOwner
// updates property state to listed
// 



// addReserveToken(address nnToken)
// assert nnToken.ZU_CITY_TREASURY = nnCityTreasury (not a malicious tx, could be spoofed i guess)
// assert msg.sender = nnCityTreasury
// nnToken.reserveToken