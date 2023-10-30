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

    modifier onlyApprovedMinter() {
        if (!_isApprovedMinter(msg.sender)) revert NotApprovedMinter();

        _;
    }

    constructor(address spog_) StatelessERC712("Protocol") {
        spog = spog_;
    }

    /******************************************************************************************************************\
    |                                                Minter Functions                                                  |
    \******************************************************************************************************************/

    /// @notice Updates collateral for minters
    /// @param amount_ The amount of collateral
    /// @param timestamp_ The timestamp of the update
    /// @param metadata_ The metadata of the update, reserved for future informational use
    /// @param validators_ The list of validators
    /// @param signatures_ The list of signatures
    function updateCollateral(
        uint256 amount_,
        uint256 timestamp_,
        string memory metadata_,
        address[] calldata validators_,
        bytes[] calldata signatures_
    ) external onlyApprovedMinter {
        if (validators_.length != signatures_.length) revert InvalidSignaturesLength();

        address minter_ = msg.sender;

        // Timestamp sanity checks
        uint256 updateInterval_ = _getUpdateCollateralInterval();
        if (block.timestamp > timestamp_ + updateInterval_) revert ExpiredTimestamp();

        CollateralBasic storage minterCollateral_ = collateral[minter_];
        if (minterCollateral_.lastUpdated >= timestamp_) revert StaleTimestamp();

        // Core quorum validation, plus possible extension
        bytes32 updateCollateralDigest_ = _getUpdateCollateralDigest(minter_, amount_, metadata_, timestamp_);
        uint256 requiredQuorum_ = _getUpdateCollateralQuorum();
        _hasEnoughValidSignatures(updateCollateralDigest_, validators_, signatures_, requiredQuorum_);

        // accruePenalties(); // JIRA ticket https://mzerolabs.atlassian.net/jira/software/c/projects/WEB3/boards/10?selectedIssue=WEB3-396

        // Update collateral
        minterCollateral_.amount = amount_;
        minterCollateral_.lastUpdated = timestamp_;

        // accruePenalties(); // JIRA ticket

        emit CollateralUpdated(minter_, amount_, timestamp_, metadata_);
    }

    /// @dev Checks that enough valid unique signatures were provided
    /// @param digest_ The message hash for signing
    /// @param validators_ The list of validators who signed digest
    /// @param signatures_ The list of signatures
    /// @param requiredQuorum_ The number of signatures required for validated action
    function _hasEnoughValidSignatures(
        bytes32 digest_,
        address[] calldata validators_,
        bytes[] calldata signatures_,
        uint256 requiredQuorum_
    ) internal view {
        address[] memory uniqueValidators_ = new address[](validators_.length);
        uint256 validatorsNum_ = 0;

        if (requiredQuorum_ > validators_.length) revert NotEnoughValidSignatures();

        // TODO consider reverting if any of inputs are duplicate or invalid
        for (uint i = 0; i < signatures_.length; i++) {
            // check that signature is unique and not accounted for
            bool duplicate_ = _contains(uniqueValidators_, validators_[i], validatorsNum_);
            if (duplicate_) continue;

            // check that validator is approved by SPOG
            bool authorized_ = _isApprovedValidator(validators_[i]);
            if (!authorized_) continue;

            // check that ECDSA or ERC1271 signatures for given digest are valid
            bool valid_ = SignatureChecker.isValidSignature(validators_[i], digest_, signatures_[i]);
            // TODO add validation extension here

            if (!valid_) continue;

            uniqueValidators_[validatorsNum_++] = validators_[i];
        }

        if (validatorsNum_ < requiredQuorum_) revert NotEnoughValidSignatures();
    }

    /// @dev Returns the EIP-712 digest for updateCollateral method
    function _getUpdateCollateralDigest(
        address minter_,
        uint256 amount_,
        string memory metadata_,
        uint256 timestamp_
    ) internal view returns (bytes32) {
        return _getDigest(keccak256(abi.encode(UPDATE_COLLATERAL_TYPEHASH, minter_, amount_, metadata_, timestamp_)));
    }

    /// @dev Helper function to check if a given list contains an element
    function _contains(address[] memory arr_, address elem_, uint len_) internal pure returns (bool) {
        for (uint i = 0; i < len_; i++) {
            if (arr_[i] == elem_) {
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

    function _isApprovedMinter(address minter_) internal view returns (bool) {
        return ISPOG(spog).listContains(MINTERS_LIST_NAME, minter_);
    }

    function _isApprovedValidator(address validator_) internal view returns (bool) {
        return ISPOG(spog).listContains(VALIDATORS_LIST_NAME, validator_);
    }

    function _getUpdateCollateralInterval() internal view returns (uint256) {
        return uint256(ISPOG(spog).get(UPDATE_COLLATERAL_INTERVAL));
    }

    function _getUpdateCollateralQuorum() internal view returns (uint256) {
        return uint256(ISPOG(spog).get(UPDATE_COLLATERAL_QUORUM));
    }
}
