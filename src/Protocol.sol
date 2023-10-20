// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

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
    bytes32 public constant UPDATE_COLLATERAL_QUORUM = "updateCollateral_quorum";
    bytes32 public constant UPDATE_COLLATERAL_INTERVAL = "updateCollateral_interval";

    address public immutable spog;

    mapping(address minter => CollateralBasic) public collateral;

    modifier onlyApprovedMinter(address minter) {
        if (msg.sender != minter || !_isApprovedMinter(minter)) revert NotApprovedMinter();

        _;
    }

    constructor(address spog_) StatelessERC712("Protocol") {
        spog = spog_;
    }

    /******************************************************************************************************************\
    |                                                Minter Functions                                                  |
    \******************************************************************************************************************/

    /// @notice Updates collateral for minters
    /// @param minter The address of the minter
    /// @param amount The amount of collateral
    /// @param timestamp The timestamp of the update
    /// @param metadata The metadata of the update, reserved for future informational use
    /// @param validators The list of validators
    /// @param signatures The list of signatures
    function updateCollateral(
        address minter,
        uint256 amount,
        uint256 timestamp,
        string memory metadata,
        address[] calldata validators,
        bytes[] calldata signatures
    ) external onlyApprovedMinter(minter) {
        if (validators.length != signatures.length) revert InvalidSignaturesLength();

        // Timestamp sanity checks
        uint256 updateInterval = _getUpdateCollateralInterval();
        if (block.timestamp > timestamp + updateInterval) revert ExpiredTimestamp();

        CollateralBasic storage minterCollateral = collateral[minter];
        if (minterCollateral.lastUpdated > timestamp) revert StaleTimestamp();

        // Core quorum validation, plus possible extension
        bytes32 updateCollateralDigest = _getUpdateCollateralDigest(minter, amount, metadata, timestamp);
        uint256 requiredQuorum = _getUpdateCollateralQuorum();
        _hasEnoughValidSignatures(updateCollateralDigest, validators, signatures, requiredQuorum);

        // accruePenalties(); // JIRA ticket https://mzerolabs.atlassian.net/jira/software/c/projects/WEB3/boards/10?selectedIssue=WEB3-396

        // Update collateral
        minterCollateral.amount = amount;
        minterCollateral.lastUpdated = timestamp;

        // accruePenalties(); // JIRA ticket

        emit CollateralUpdated(minter, amount, timestamp, metadata);
    }

    /// @dev Checks that enough valid unique signatures were provided
    /// @param digest The message hash for signing
    /// @param validators The list of validators who signed digest
    /// @param signatures The list of signatures
    /// @param requiredQuorum The number of signatures required for validated action
    function _hasEnoughValidSignatures(
        bytes32 digest,
        address[] calldata validators,
        bytes[] calldata signatures,
        uint256 requiredQuorum
    ) internal view {
        address[] memory uniqueValidators = new address[](validators.length);
        uint256 validatorsNum = 0;

        if (requiredQuorum > validators.length) revert NotEnoughValidSignatures();

        // TODO consider reverting if any of inputs are duplicate or invalid
        for (uint i = 0; i < signatures.length; i++) {
            // check that signature is unique and not accounted for
            bool duplicate = _contains(uniqueValidators, validators[i], validatorsNum);
            if (duplicate) continue;

            // check that validator is approved by SPOG
            bool authorized = _isApprovedValidator(validators[i]);
            if (!authorized) continue;

            // check that ECDSA or ERC1271 signatures for given digest are valid
            bool valid = SignatureChecker.isValidSignature(validators[i], digest, signatures[i]);
            // TODO add validation extension here

            if (!valid) continue;

            uniqueValidators[validatorsNum++] = validators[i];
        }

        if (validatorsNum < requiredQuorum) revert NotEnoughValidSignatures();
    }

    /// @dev Returns the EIP-712 digest for updateCollateral method
    function _getUpdateCollateralDigest(
        address minter,
        uint256 amount,
        string memory metadata,
        uint256 timestamp
    ) internal view returns (bytes32) {
        return _getDigest(keccak256(abi.encode(UPDATE_COLLATERAL_TYPEHASH, minter, amount, metadata, timestamp)));
    }

    /// @dev Helper function to check if a given list contains an element
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

    function _getUpdateCollateralInterval() internal view returns (uint256) {
        return uint256(ISPOG(spog).get(UPDATE_COLLATERAL_INTERVAL));
    }

    function _getUpdateCollateralQuorum() internal view returns (uint256) {
        return uint256(ISPOG(spog).get(UPDATE_COLLATERAL_QUORUM));
    }
}
