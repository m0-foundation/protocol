// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

contract Protocol {
    address public immutable mToken;

    constructor(address mToken_) {
        mToken = mToken_;
    }

    /******************************************************************************************************************\
    |                                                Minter Functions                                                  |
    \******************************************************************************************************************/
    //
    //
    // updateCollateral
    // proposeMint, mint, cancel, freeze
    // burn
    // proposeRedeem, redeem
    // quit, leave / remove
    //
    //
    /******************************************************************************************************************\
    |                                                Primary Functions                                                 |
    \******************************************************************************************************************/
    //
    //
    // stake
    // withdraw
    //
    //
    /******************************************************************************************************************\
    |                                                Brains Functions                                                  |
    \******************************************************************************************************************/
    //
    //
    // updateIndices, updateBorrowIndex, updateStakingIndex
    // accruePenalties
    // mintRewardsToZeroHolders
    //
    //
}
