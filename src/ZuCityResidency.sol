// extr legl 
// receiving your ZuCityResidency does not gaurantee access to ZuCity locations. ZuCity does not own properties.Individual property owners have the right to approve or reject any visitors
// One residency NFT is required per person to stay in a ZuCity.

// is NFT contract
// NFT ID incs on every staker
// Struct ResidencyType - bool active, uint64 amount, address reserveToken, address zuToken, uint32 minStakeLength
// Struct Residency - uint8 residencyType, uint32 releaseDate
// mapping residencies - nftIf -> Residency
// e.g. Base = WETH, zuETH, 64 (~$250k, $13k /yr in yield)

// claim - deposit zuToken, claim residency
// stakeAndClaim - take reserveToken, deposit to zuToken, claim residency in one tx

// add zuToken
// - valid chainlink oracle
// - zuToken.zuCityTreasury = zuCityTreasury