contract NNRegistryCoreTest {
    

    // stake
    // succeeds if lot is LISTED
    // reverts if lot is DELISTED, PURCHASING, BOUGHT
    // reverts if stakeAmount is 0
    // reverts if nnToken is not nnETH or nnUSDC
    // reverts if nnToken is not valid (no price feed) - stub oracle call to revert / return 0
    // stakeAmount is transferred from msg.sender to Registry
    // stake object is created with corect values
    // uses right stakeID.
    // stake is added to lot list
    // stakeID NFT owner == owner param
    // stake event is emitted

    // unstake
    // computes the right stakeID
    // reverts if lot is in LISTED
    // succeeds if lot is DELISTED, PURCHASING, BOUGHT
    // reverts if msg.sender != lot.buyer
    // stakeAmount is transferred to msg.sender
    // stake object is deleted
    // stake is removed from lot list
    // NFT owner is address 0
    // unstake event is emitted
    // reverts if stakeID == lot buyer


    // depositAndStakeUSDC
    // reduces USDC balance of depositor
    // increases nnUSDC supply
    // increases nnUSDC balance of registry
    // stake event with correct params with city + registry as referrer
    // stake object with proper stats

    // depositAndStakeETH
    // reduces ETH balance of depositor
    // increases nnETH supply
    // increases nnETH balance of registry
    // stake event with correct params with city + registry as referrer
    // stake event object with proper stats


    /** city ops */

    // listProperty
    // properties[nextLotID] is always empty
    // reverts if deposit is 0
    // reverts if price less than deposit
    // reverts if msg.sender is not a registered city
    // inits property storage with proper valuies
    // incs nextLotID
    // emits event

    // upodateListing
    // reverts if status != Li sted
    // reverts if not listing city
    // updates properties in storage properly
    // emits event

    // delist property
    // reverts if status != LISTED
    // reverts if not listing city
    // updates properties in storage properly
    // emits event

    // approveBuyer
    // reverts if lot is in LISTED
    // 

    // cancelPurchase

    
}