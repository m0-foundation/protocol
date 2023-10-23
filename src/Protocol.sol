// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { Bytes32AddressLib } from "solmate/utils/Bytes32AddressLib.sol";

import { SignatureChecker } from "./SignatureChecker.sol";

import { IProtocol } from "./interfaces/IProtocol.sol";
import { ISPOG } from "./interfaces/ISPOG.sol";

import { StatelessERC712 } from "./StatelessERC712.sol";

/**
 * @title Protocol
 * @author M^ZERO LABS_
 * @notice Core protocol of M^ZERO ecosystem. TODO Add description.
 */
contract Protocol is IProtocol, StatelessERC712 {
    using Bytes32AddressLib for bytes32;

    // TODO bit-packing
    struct CollateralBasic {
        uint256 amount;
        uint256 lastUpdated;
    }

    struct MintRequest {
        uint256 amount;
        uint256 createdAt;
    }

    /// @notice The EIP-712 typehash for updateCollateral method
    bytes32 public constant UPDATE_COLLATERAL_TYPEHASH =
        keccak256("UpdateCollateral(address minter,uint256 amount,uint256 timestamp,string metadata)");

    /// @notice The minters' list name as known by SPOG
    bytes32 public constant MINTERS_LIST_NAME = "minters";
    /// @notice The validators' list name as known by SPOG
    bytes32 public constant VALIDATORS_LIST_NAME = "validators";
    /// @notice The name of parameter that defines number of signatures required for successful collateral update
    bytes32 public constant UPDATE_COLLATERAL_QUORUM = "updateCollateral_quorum";
    /// @notice The name of parameter that required interval to update collateral
    bytes32 public constant UPDATE_COLLATERAL_INTERVAL = "updateCollateral_interval";
    /// @notice The name of parameter that defines the time to wait for mint request to be processed
    bytes32 public constant MINT_REQUEST_QUEUE_TIME = "mint_queueTime";
    /// @notice The name of parameter that defines the time while mint request can still be processed
    bytes32 public constant MINT_REQUEST_EXPIRATION_TIME = "mint_expirationTime";

    /// @notice The address of SPOG
    address public immutable spog;

    /// @notice The collateral information of minters
    mapping(address minter => CollateralBasic basic) public collateral;

    /// @notice The mint requests of minters, only 1 request per minter
    mapping(address minter => MintRequest request) public mintRequests;

    modifier onlyApprovedMinter() {
        if (!_isApprovedMinter(msg.sender)) revert NotApprovedMinter();

        _;
    }

    /**
     * @notice Constructor.
     * @param spog_ The address of SPOG
     */
    constructor(address spog_) StatelessERC712("Protocol") {
        spog = spog_;
    }

    /******************************************************************************************************************\
    |                                                Minter Functions                                                  |
    \******************************************************************************************************************/

    /**
     * @notice Updates collateral for minters
     * @param amount_ The amount of collateral
     * @param timestamp_ The timestamp of the update
     * @param metadata_ The metadata of the update, reserved for future informational use
     * @param validators_ The list of validators
     * @param signatures_ The list of signatures
     */
    function updateCollateral(
        uint256 amount_,
        uint256 timestamp_,
        string memory metadata_,
        address[] calldata validators_,
        bytes[] calldata signatures_
    ) external onlyApprovedMinter {
        if (validators_.length != signatures_.length) revert InvalidSignaturesLength();

        // Timestamp sanity checks
        uint256 updateInterval_ = _getUpdateCollateralInterval();
        if (block.timestamp > timestamp_ + updateInterval_) revert ExpiredTimestamp();

        address minter_ = msg.sender;

        CollateralBasic storage minterCollateral_ = collateral[minter_];
        if (minterCollateral_.lastUpdated > timestamp_) revert StaleTimestamp();

        // Core quorum validation, plus possible extension
        bytes32 updateCollateralDigest_ = _getUpdateCollateralDigest(minter_, amount_, metadata_, timestamp_);
        uint256 requiredQuorum_ = _getUpdateCollateralQuorum();
        _hasEnoughValidSignatures(updateCollateralDigest_, validators_, signatures_, requiredQuorum_);

        // _accruePenalties(); // JIRA ticket https://mzerolabs.atlassian.net/jira/software/c/projects/WEB3/boards/10?selectedIssue=WEB3-396

        // Update collateral
        minterCollateral_.amount = amount_;
        minterCollateral_.lastUpdated = timestamp_;

        // _accruePenalties(); // JIRA ticket

        emit CollateralUpdated(minter_, amount_, timestamp_, metadata_);
    }

    function proposeMint(uint256 amount, address to) external onlyApprovedMinter returns (uint256) {
        // MintRequest storage mintRequest = mintRequests[msg.sender];
        // uint256 queueTime = _getMintRequestQueueTime();
        // if (mintRequest.amount > 0 && block.timestamp < mintRequest.createdAt + queueTime)
        //     revert OnlyOneMintRequestAtTime();
        // // _accruePenalties();
    }

    function mint(uint256 proposeId) external {}

    function cancel(uint256 proposeId) external {}

    function freeze(address minter) external {}

    /**
     * @notice Checks that enough valid unique signatures were provided
     * @param digest_ The message hash for signing
     * @param validators_ The list of validators who signed digest
     * @param signatures_ The list of signatures
     * @param requiredQuorum_ The number of signatures required for validated action
     */
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

    /**
     * @notice Returns the EIP-712 digest for updateCollateral method
     * @param minter_ The address of the minter
     * @param amount_ The amount of collateral
     * @param metadata_ The metadata of the collateral update, reserved for future informational use
     * @param timestamp_ The timestamp of the collateral update
     */
    function _getUpdateCollateralDigest(
        address minter_,
        uint256 amount_,
        string memory metadata_,
        uint256 timestamp_
    ) internal view returns (bytes32) {
        return _getDigest(keccak256(abi.encode(UPDATE_COLLATERAL_TYPEHASH, minter_, amount_, metadata_, timestamp_)));
    }

    /**
     * @notice Helper function to check if a given list contains an element
     * @param arr_ The list to check
     * @param elem_ The element to check for
     * @param len_ The length of the list
     */
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

    function _getMintRequestQueueTime() internal view returns (uint256) {
        return uint256(ISPOG(spog).get(MINT_REQUEST_QUEUE_TIME));
    }

    function _getMintRequestExpirationTime() internal view returns (uint256) {
        return uint256(ISPOG(spog).get(MINT_REQUEST_EXPIRATION_TIME));
    }
}
