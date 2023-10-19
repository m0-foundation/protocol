// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import { Bytes32AddressLib } from "solmate/utils/Bytes32AddressLib.sol";

import { SignatureChecker } from "./SignatureChecker.sol";

import { IProtocol } from "./interfaces/IProtocol.sol";
import { ISPOG } from "./interfaces/ISPOG.sol";

import { StatelessERC712 } from "./StatelessERC712.sol";

contract Protocol is IProtocol, StatelessERC712 {
    using Bytes32AddressLib for bytes32;

    // TODO bit-packing
    struct CollateralBasic {
        uint256 amount;
        uint256 lastUpdated;
    }

    /// @dev The EIP-712 typehash for updateCollateral method
    bytes32 public constant UPDATE_COLLATERAL_TYPEHASH =
        keccak256("UpdateCollateral(address minter,uint256 amount,uint256 timestamp,string metadata)");

    // SPOG lists and variables names
    bytes32 public constant MINTERS_LIST_NAME = "minters";
    bytes32 public constant VALIDATORS_LIST_NAME = "validators";
    bytes32 public constant UPDATE_COLLATERAL_REQUIRED_SIGS_NUM = "update_collateral_required_sigs_number";

    address public immutable spog;

    mapping(address minter => CollateralBasic basic) public collateral;

    constructor(address spog_) StatelessERC712("Protocol") {
        spog = spog_;
    }

    /******************************************************************************************************************\
    |                                                Minter Functions                                                  |
    \******************************************************************************************************************/

    function updateCollateral(
        address minter,
        uint256 amount,
        uint256 timestamp,
        string memory metadata,
        address[] calldata validators,
        bytes[] calldata signatures
    ) external {
        if (msg.sender != minter) revert NotMinter();
        if (!_isApprovedMinter(minter)) revert InvalidMinter();

        if (validators.length != signatures.length) revert InvalidSignaturesLength();

        CollateralBasic storage minterCollateral = collateral[minter];

        if (minterCollateral.lastUpdated >= timestamp) revert InvalidTimestamp();

        // TODO check that timestamp is not too old
        // if (block.timestamp > timestamp + 1 days) revert InvalidTimestamp();

        // verify that enough valid unique signatures were provided
        bytes32 updateCollateralDigest = _getUpdateCollateralDigest(minter, amount, metadata, timestamp);
        uint256 requiredSigsNum = _getSigsNumRequiredToUpdateCollateral();
        _hasEnoughValidSignatures(updateCollateralDigest, validators, signatures, requiredSigsNum);

        // accruePenalties();

        minterCollateral.amount = amount;
        // minterCollateral.lastUpdated = uint64(block.timestamp);
        minterCollateral.lastUpdated = timestamp;

        // accruePenalties();
        emit CollateralUpdated(minter, amount, timestamp, metadata);
    }

    function _hasEnoughValidSignatures(
        bytes32 digest,
        address[] calldata validators,
        bytes[] calldata signatures,
        uint256 requiredSigsNum
    ) internal view {
        address[] memory uniqueValidators = new address[](validators.length);
        uint256 validatorsNum = 0;

        if (requiredSigsNum > validators.length) revert NotEnoughSignatures();

        // TODO consider reverting if any of inputs is duplicate or invalid
        for (uint i = 0; i < signatures.length; i++) {
            // check that signature is unique and not accounted for
            bool duplicate = _contains(uniqueValidators, validators[i], validatorsNum);
            if (duplicate) continue;

            // check that validator is approved by SPOG
            bool authorized = _isApprovedValidator(validators[i]);
            if (!authorized) continue;

            // check that ECDSA or ERC1271 signatures for given digest are valid
            bool valid = SignatureChecker.isValidSignature(validators[i], digest, signatures[i]);
            // bool validExtension = IValidationExtension(_getValidationExtension()).isValidSignature(
            //     validator[i],
            //     digest,
            //     signatures[i]
            // );
            if (!valid) continue;

            uniqueValidators[validatorsNum++] = validators[i];
        }

        if (validatorsNum < requiredSigsNum) revert NotEnoughSignatures();
    }

    function _getUpdateCollateralDigest(
        address minter,
        uint256 amount,
        string memory metadata,
        uint256 timestamp
    ) internal view returns (bytes32) {
        return _getDigest(keccak256(abi.encode(UPDATE_COLLATERAL_TYPEHASH, minter, amount, metadata, timestamp)));
    }

    // function _getProposeMintDigest(
    //     address minter,
    //     uint256 amount,
    //     string memory metadata,
    //     uint256 timestamp
    // ) internal view returns (bytes32) {
    //     return _getDigest(keccak256(abi.encode(PROPOSE_MINT_TYPEHASH, minter, amount, metadata, timestamp)));
    // }

    // Helper function to check if a given list contains an element
    function _contains(address[] memory arr, address elem, uint len) internal pure returns (bool) {
        for (uint i = 0; i < len; i++) {
            if (arr[i] == elem) {
                return true;
            }
        }
        return false;
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

    // function _getValidationExtension() internal view returns (address) {
    //     return ISPOG(spog).get(COLLATERAL_VERIFIER).fromLast20Bytes();
    // }

    function _getSigsNumRequiredToUpdateCollateral() internal view returns (uint256) {
        return uint256(ISPOG(spog).get(UPDATE_COLLATERAL_REQUIRED_SIGS_NUM));
    }
}
