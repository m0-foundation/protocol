// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { ISPOGRegistrar } from "../interfaces/ISPOGRegistrar.sol";

library SPOGRegistrarReader {
    /// @notice The interest earners list name in SPOG.
    bytes32 internal constant INTEREST_EARNERS_LIST = "interest_earners";

    /// @notice The name of parameter in SPOG that defines the interest rate model contract.
    bytes32 internal constant INTEREST_RATE_MODEL = "interest_rate_model";

    /// @notice The name of parameter in SPOG that defines the M rate
    bytes32 public constant M_RATE_MODEL = "m_rate_model";

    /// @notice The name of parameter in SPOG that defines the time to wait for mint request to be processed
    bytes32 public constant MINT_DELAY = "mint_delay";

    /// @notice The name of parameter in SPOG that defines the mint ratio.
    bytes32 internal constant MINT_RATIO = "mint_ratio"; // bps

    /// @notice The name of parameter in SPOG that defines the time while mint request can still be processed
    bytes32 public constant MINT_TTL = "mint_ttl";

    /// @notice The name of parameter in SPOG that defines the time to freeze minter
    bytes32 public constant MINTER_FREEZE_TIME = "minter_freeze_time";

    /// @notice The minters list name in SPOG.
    bytes32 internal constant MINTERS_LIST = "minters";

    /// @notice The name of parameter in SPOG that required interval to update collateral.
    bytes32 internal constant UPDATE_COLLATERAL_INTERVAL = "updateCollateral_interval";

    /// @notice The name of parameter that defines number of signatures required for successful collateral update
    bytes32 public constant UPDATE_COLLATERAL_QUORUM = "updateCollateral_quorum";

    /// @notice The validators list name in SPOG.
    bytes32 internal constant VALIDATORS_LIST = "validators";

    function isApprovedMinter(address registrar_, address minter_) internal view returns (bool isApproved_) {
        return _contains(registrar_, MINTERS_LIST, minter_);
    }

    function isApprovedInterestEarner(address registrar_, address earner_) internal view returns (bool isApproved_) {
        return _contains(registrar_, INTEREST_EARNERS_LIST, earner_);
    }

    function isApprovedValidator(address registrar_, address validator_) internal view returns (bool isApproved_) {
        return _contains(registrar_, VALIDATORS_LIST, validator_);
    }

    function getUpdateCollateralInterval(address registrar_) internal view returns (uint256 interval_) {
        return uint256(_get(registrar_, UPDATE_COLLATERAL_INTERVAL));
    }

    function getUpdateCollateralQuorum(address registrar_) internal view returns (uint256 quorum_) {
        return uint256(_get(registrar_, UPDATE_COLLATERAL_QUORUM));
    }

    function getMintDelay(address registrar_) internal view returns (uint256 queueTime_) {
        return uint256(_get(registrar_, MINT_DELAY));
    }

    function getMintTTL(address registrar_) internal view returns (uint256 timeToLive_) {
        return uint256(_get(registrar_, MINT_TTL));
    }

    function getMinterFreezeTime(address registrar_) internal view returns (uint256 freezeTime_) {
        return uint256(_get(registrar_, MINTER_FREEZE_TIME));
    }

    function getMRateModel(address registrar_) internal view returns (address rateModel_) {
        return _toAddress(_get(registrar_, M_RATE_MODEL));
    }

    function getInterestRateModel(address registrar_) internal view returns (address rateModel_) {
        return toAddress(_get(registrar_, INTEREST_RATE_MODEL));
    }

    function getMintRatio(address registrar_) internal view returns (uint256 ratio_) {
        return uint256(_get(registrar_, MINT_RATIO));
    }

    function toAddress(bytes32 input_) internal pure returns (address output_) {
        return address(uint160(uint256(input_)));
    }

    function toBytes32(address input_) internal pure returns (bytes32 output_) {
        return bytes32(uint256(uint160(input_)));
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
