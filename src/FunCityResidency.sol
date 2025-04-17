pragma solidity ^0.8.26;

// extr legl
// receiving your funCityResidency does not gaurantee access to funCity locations. funCity does not own properties.Individual property owners have the right to approve or reject any visitors
// One residency NFT is required per person to stay in a funCity.

// is NFT contract
// NFT ID incs on every staker
// Struct ResidencyType - bool active, uint64 amount, address reserveToken, address nnToken, uint32 minStakeLength
// Struct Residency - uint8 residencyType, uint32 releaseDate
// mapping residencies - nftIf -> Residency
// e.g. Base = WETH, funETH, 64ETH (~$250k, $13k /yr in yield)

// claim - deposit nnToken, claim residency
// stakeAndClaim - take reserveToken, deposit to nnToken, claim residency in one tx

// add nnToken
// - valid chainlink oracle
// - nnToken.FUN_OPS = funCityTreasury
