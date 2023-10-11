// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import { Bytes32AddressLib } from "solmate/utils/Bytes32AddressLib.sol";

import { IProtocol } from "./interfaces/IProtocol.sol";
import { ISPOG } from "./interfaces/ISPOG.sol";
import { IUpdateCollateralSigVerifier } from "./interfaces/IUpdateCollateralSigVerifier.sol";

contract Protocol is IProtocol {
    using Bytes32AddressLib for bytes32;

    // TODO figure out proper bit-packing and size of fields
    struct CollateralBasic {
        uint256 amount;
        uint64 lastUpdated;
    }

    // Protocol variables
    address public immutable spog;

    // SPOG lists and variables names
    bytes32 public constant MINTERS_LIST_NAME = "minters";
    bytes32 public constant VALIDATORS_LIST_NAME = "validators";
    bytes32 public constant COLLATERAL_SIG_VERIFIER = "collateral_sig_verifier";

    mapping(address minter => CollateralBasic) public collateral;

    constructor(address spog_) {
        spog = spog_;
    }

    /******************************************************************************************************************\
    |                                                Minter Functions                                                  |
    \******************************************************************************************************************/
    function updateCollateral(
        address minter,
        uint256 amount,
        string memory metadata,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (!_isApprovedMinter(minter)) revert InvalidMinter();
        // if (msg.sender != minter) revert NotMinter();

        address verifierContract = _getCollateralSigVerifier();
        address validator = IUpdateCollateralSigVerifier(verifierContract).recoverValidator(
            minter,
            amount,
            metadata,
            nonce,
            expiry,
            v,
            r,
            s
        );

        if (!_isApprovedValidator(validator)) revert InvalidValidator();

        // accruePenalties();

        CollateralBasic storage minterCollateral = collateral[minter];

        minterCollateral.amount = amount;
        minterCollateral.lastUpdated = uint64(block.timestamp);

        // accruePenalties();
    }

    //
    //
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

    /******************************************************************************************************************\
    |                                                SPOG Configs                                                      |
    \******************************************************************************************************************/

    function _isApprovedMinter(address minter) internal view returns (bool) {
        return ISPOG(spog).listContains(MINTERS_LIST_NAME, minter);
    }

    function _isApprovedValidator(address validator) internal view returns (bool) {
        return ISPOG(spog).listContains(VALIDATORS_LIST_NAME, validator);
    }

    function _getCollateralSigVerifier() internal view returns (address) {
        return ISPOG(spog).get(COLLATERAL_SIG_VERIFIER).fromLast20Bytes();
    }
}
