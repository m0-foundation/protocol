// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { ISPOGRegistrar } from "../interfaces/ISPOGRegistrar.sol";

library SPOGRegistrarReader {
    /// @notice The minters' list name in SPOG
    bytes32 public constant MINTERS_LIST_NAME = "minters";

    /// @notice The validators' list name in SPOG
    bytes32 public constant VALIDATORS_LIST_NAME = "validators";

    /// @notice The name of parameter in SPOG that required interval to update collateral
    bytes32 public constant UPDATE_COLLATERAL_INTERVAL = "updateCollateral_interval";

    /// @notice The name of parameter that defines number of signatures required for successful collateral update
    bytes32 public constant UPDATE_COLLATERAL_QUORUM = "updateCollateral_quorum";

    /// @notice The name of parameter in SPOG that defines the time to wait for mint request to be processed
    bytes32 public constant MINT_REQUEST_QUEUE_TIME = "mintRequest_queue_time";

    /// @notice The name of parameter in SPOG that defines the time while mint request can still be processed
    bytes32 public constant MINT_REQUEST_TTL = "mintRequest_ttl";

    /// @notice The name of parameter in SPOG that defines the time to freeze minter
    bytes32 public constant MINTER_FREEZE_TIME = "minter_freeze_time";

    /// @notice The name of parameter in SPOG that defines the borrow rate
    bytes32 public constant BORROW_RATE_MODEL = "borrow_rate_model";

    /// @notice The name of parameter in SPOG that defines the mint ratio
    bytes32 public constant MINT_RATIO = "mint_ratio"; // bps

    function isApprovedMinter(address registrar_, address minter_) internal view returns (bool isApproved_) {
        return _contains(registrar_, MINTERS_LIST_NAME, minter_);
    }

    function isApprovedValidator(address registrar_, address validator_) internal view returns (bool isApproved_) {
        return _contains(registrar_, VALIDATORS_LIST_NAME, validator_);
    }

    function getUpdateCollateralInterval(address registrar_) internal view returns (uint256 interval_) {
        return uint256(_get(registrar_, UPDATE_COLLATERAL_INTERVAL));
    }

    function getUpdateCollateralQuorum(address registrar_) internal view returns (uint256 quorum_) {
        return uint256(_get(registrar_, UPDATE_COLLATERAL_QUORUM));
    }

    function getMintRequestQueueTime(address registrar_) internal view returns (uint256 queueTime_) {
        return uint256(_get(registrar_, MINT_REQUEST_QUEUE_TIME));
    }

    function getMintRequestTimeToLive(address registrar_) internal view returns (uint256 timeToLive_) {
        return uint256(_get(registrar_, MINT_REQUEST_TTL));
    }

    function getMinterFreezeTime(address registrar_) internal view returns (uint256 freezeTime_) {
        return uint256(_get(registrar_, MINTER_FREEZE_TIME));
    }

    function getBorrowRateModel(address registrar_) internal view returns (address rateModel_) {
        return _toAddress(_get(registrar_, BORROW_RATE_MODEL));
    }

    function getMintRatio(address registrar_) internal view returns (uint256 ratio_) {
        return uint256(_get(registrar_, MINT_RATIO));
    }

    function _get(address registrar_, bytes32 key_) private view returns (bytes32 value_) {
        return ISPOGRegistrar(registrar_).get(key_);
    }

    function _contains(address registrar_, bytes32 listName_, address account_) private view returns (bool contains_) {
        return ISPOGRegistrar(registrar_).listContains(listName_, account_);
    }

    function _toAddress(bytes32 input_) private pure returns (address output_) {
        return address(uint160(uint256(input_)));
    }
}
