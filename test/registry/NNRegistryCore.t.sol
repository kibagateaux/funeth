contract NNRegistryCoreTest {
    

    // stake
    // succeeds if lot is LISTED
    // succeeds if lot is DELISTED, PURCHASING, BOUGHT
    // reverts if stakeAmount is 0
    // reverts if nnToken is not nnETH or nnUSDC
    // reverts if nnToken is not valid (no price feed) - stub oracle call to revert / return 0
    // stakeAmount is transferred from msg.sender to Registry
    // stake object is created
    // uses right stakeID.
    // stake is added to lot list
    // stake event is emitted

    // unstake
    // computes the right stakeID
    // reverts if lot is in LISTED
    // succeeds if lot is DELISTED, PURCHASING, BOUGHT
    // reverts if msg.sender != lot.buyer
    // stakeAmount is transferred to msg.sender
    // stake object is deleted
    // stake is removed from lot list
    // unstake event is emitted

    // approveBuyer
    // reverts if lot is in LISTED
    
}