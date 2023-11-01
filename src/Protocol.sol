// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { SignatureChecker } from "./SignatureChecker.sol";

import { IProtocol } from "./interfaces/IProtocol.sol";
import { ISPOGRegistrar } from "./interfaces/ISPOGRegistrar.sol";

import { StatelessERC712 } from "./StatelessERC712.sol";

contract Protocol is IProtocol, StatelessERC712 {
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

    address public immutable spogRegistrar;

    mapping(address minter => CollateralBasic) public collateral;

    modifier onlyApprovedMinter() {
        if (!_isApprovedMinter(msg.sender)) revert NotApprovedMinter();

        _;
    }

    constructor(address spogRegistrar_) StatelessERC712("Protocol") {
        spogRegistrar = spogRegistrar_;
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
        _revertIfInsufficientValidSignatures(updateCollateralDigest_, validators_, signatures_, requiredQuorum_);

        // accruePenalties(); // JIRA ticket https://mzerolabs.atlassian.net/jira/software/c/projects/WEB3/boards/10?selectedIssue=WEB3-396

        // Update collateral
        minterCollateral_.amount = amount_;
        minterCollateral_.lastUpdated = timestamp_;

        // accruePenalties(); // JIRA ticket

        emit CollateralUpdated(minter_, amount_, timestamp_, metadata_);
    }

    /// @dev Checks that enough valid unique signatures were provided
    /// @dev Validators need to be sorted in ascending order
    /// @param digest_ The message hash for signing
    /// @param validators_ The sorted list of validators who signed digest
    /// @param signatures_ The list of signatures
    /// @param requiredQuorum_ The number of signatures required for the action to be validated
    function _revertIfInsufficientValidSignatures(
        bytes32 digest_,
        address[] calldata validators_,
        bytes[] calldata signatures_,
        uint256 requiredQuorum_
    ) internal view {
        if (validators_.length < requiredQuorum_) revert NotEnoughValidSignatures();

        uint256 validSignaturesNum_ = 0;

        for (uint256 index_ = 0; index_ < signatures_.length; index_++) {
            address validator_ = validators_[index_];

            // Check that validator address is unique and not accounted for
            bool duplicate_ = index_ > 0 && validator_ <= validators_[index_ - 1];
            if (duplicate_) continue;

            // Check that validator is approved by SPOG
            bool authorized_ = _isApprovedValidator(validator_);
            if (!authorized_) continue;

            // Check that ECDSA or ERC1271 signatures for given digest are valid
            bool valid_ = SignatureChecker.isValidSignature(validator_, digest_, signatures_[index_]);
            if (!valid_) continue;

            // Stop processing if quorum was reached
            if (++validSignaturesNum_ == requiredQuorum_) return;
        }

        revert NotEnoughValidSignatures();
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
        return ISPOGRegistrar(spogRegistrar).listContains(MINTERS_LIST_NAME, minter_);
    }

    function _isApprovedValidator(address validator_) internal view returns (bool) {
        return ISPOGRegistrar(spogRegistrar).listContains(VALIDATORS_LIST_NAME, validator_);
    }

    function _getUpdateCollateralInterval() internal view returns (uint256) {
        return uint256(ISPOGRegistrar(spogRegistrar).get(UPDATE_COLLATERAL_INTERVAL));
    }

    function _getUpdateCollateralQuorum() internal view returns (uint256) {
        return uint256(ISPOGRegistrar(spogRegistrar).get(UPDATE_COLLATERAL_QUORUM));
    }
}
