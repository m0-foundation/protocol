// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import { Bytes32AddressLib } from "solmate/utils/Bytes32AddressLib.sol";

import { IProtocol } from "./interfaces/IProtocol.sol";
import { ISPOG } from "./interfaces/ISPOG.sol";
import { ICollateralVerifier } from "./interfaces/ICollateralVerifier.sol";

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
    bytes32 public constant COLLATERAL_VERIFIER = "collateral_verifier";
    bytes32 public constant UPDATE_COLLATERAL_SIG_NUMBER = "update_collateral";

    mapping(address minter => CollateralBasic basic) public collateral;

    constructor(address spog_) {
        spog = spog_;
    }

    /******************************************************************************************************************\
    |                                                Minter Functions                                                  |
    \******************************************************************************************************************/

    function updateCollateral(
        uint256 minter,
        uint256 amount,
        uint256 timestamp,
        string memory metadata,
        address[] validators,
        bytes[] calldata signatures
    ) external {
        address verifierContract = _getCollateralVerifier();
        uint256 requiredSigNumber = ISPOG(spog).
        (address minter, uint256 amount, uint256 timestamp) = ICollateralVerifier(verifierContract).decode(spog, data);

        if (msg.sender != minter) revert NotMinter();

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

    function _getCollateralVerifier() internal view returns (address) {
        return ISPOG(spog).get(COLLATERAL_VERIFIER).fromLast20Bytes();
    }
}
