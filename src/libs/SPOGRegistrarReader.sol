// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { ISPOGRegistrar } from "../interfaces/ISPOGRegistrar.sol";

library SPOGRegistrarReader {
    /// @notice The name of parameter in SPOG that defines the base earner rate.
    bytes32 internal constant BASE_EARNER_RATE = "base_earner_rate";

    /// @notice The name of parameter in SPOG that defines the base minter rate.
    bytes32 internal constant BASE_MINTER_RATE = "base_minter_rate";

    /// @notice The name of parameter in SPOG that defines the earner rate model contract.
    bytes32 internal constant EARNER_RATE_MODEL = "earner_rate_model";

    /// @notice The earners list name in SPOG.
    bytes32 internal constant EARNERS_LIST = "earners";

    /// @notice The earners list name in SPOG.
    bytes32 internal constant EARNERS_LIST_IGNORED = "earners_list_ignored";

    /// @notice The name of parameter in SPOG that defines the time to wait for mint request to be processed
    bytes32 internal constant MINT_DELAY = "mint_delay";

    /// @notice The name of parameter in SPOG that defines the mint ratio.
    bytes32 internal constant MINT_RATIO = "mint_ratio"; // bps

    /// @notice The name of parameter in SPOG that defines the time while mint request can still be processed
    bytes32 internal constant MINT_TTL = "mint_ttl";

    /// @notice The name of parameter in SPOG that defines the time to freeze minter
    bytes32 internal constant MINTER_FREEZE_TIME = "minter_freeze_time";

    /// @notice The name of parameter in SPOG that defines the minter rate model contract.
    bytes32 internal constant MINTER_RATE_MODEL = "minter_rate_model";

    /// @notice The minters list name in SPOG.
    bytes32 internal constant MINTERS_LIST = "minters";

    /// @notice The name of parameter in SPOG that defines the minter rate.
    bytes32 internal constant MINTER_RATE = "minter_rate";

    /// @notice The name of parameter in SPOG that defines the penalty rate.
    bytes32 internal constant PENALTY_RATE = "penalty_rate";

    /// @notice The name of parameter in SPOG that required interval to update collateral.
    bytes32 internal constant UPDATE_COLLATERAL_INTERVAL = "updateCollateral_interval";

    /// @notice The name of parameter that defines number of signatures required for successful collateral update
    bytes32 internal constant UPDATE_COLLATERAL_VALIDATOR_THRESHOLD = "updateCollateral_threshold";

    /// @notice The validators list name in SPOG.
    bytes32 internal constant VALIDATORS_LIST = "validators";

    function getBaseEarnerRate(address registrar_) internal view returns (uint256 rate_) {
        return uint256(_get(registrar_, BASE_EARNER_RATE));
    }

    function getBaseMinterRate(address registrar_) internal view returns (uint256 rate_) {
        return uint256(_get(registrar_, BASE_MINTER_RATE));
    }

    function getEarnerRateModel(address registrar_) internal view returns (address rateModel_) {
        return toAddress(_get(registrar_, EARNER_RATE_MODEL));
    }

    function getMintDelay(address registrar_) internal view returns (uint256 queueTime_) {
        return uint256(_get(registrar_, MINT_DELAY));
    }

    function getMinterFreezeTime(address registrar_) internal view returns (uint256 freezeTime_) {
        return uint256(_get(registrar_, MINTER_FREEZE_TIME));
    }

    function getMinterRate(address registrar_) internal view returns (uint256 rate_) {
        return uint256(_get(registrar_, MINTER_RATE));
    }

    function getMinterRateModel(address registrar_) internal view returns (address rateModel_) {
        return toAddress(_get(registrar_, MINTER_RATE_MODEL));
    }

    function getMintTTL(address registrar_) internal view returns (uint256 timeToLive_) {
        return uint256(_get(registrar_, MINT_TTL));
    }

    function getMintRatio(address registrar_) internal view returns (uint256 ratio_) {
        return uint256(_get(registrar_, MINT_RATIO));
    }

    function getUpdateCollateralInterval(address registrar_) internal view returns (uint256 interval_) {
        return uint256(_get(registrar_, UPDATE_COLLATERAL_INTERVAL));
    }

    function getUpdateCollateralValidatorThreshold(address registrar_) internal view returns (uint256 quorum_) {
        return uint256(_get(registrar_, UPDATE_COLLATERAL_VALIDATOR_THRESHOLD));
    }

    function isApprovedEarner(address registrar_, address earner_) internal view returns (bool isApproved_) {
        return _contains(registrar_, EARNERS_LIST, earner_);
    }

    function isEarnersListIgnored(address registrar_) internal view returns (bool isIgnored_) {
        return _get(registrar_, EARNERS_LIST_IGNORED) != bytes32(0);
    }

    function isApprovedMinter(address registrar_, address minter_) internal view returns (bool isApproved_) {
        return _contains(registrar_, MINTERS_LIST, minter_);
    }

    function isApprovedValidator(address registrar_, address validator_) internal view returns (bool isApproved_) {
        return _contains(registrar_, VALIDATORS_LIST, validator_);
    }

    function getPenaltyRate(address registrar_) internal view returns (uint256 penalty_) {
        return uint256(_get(registrar_, PENALTY_RATE));
    }

    function getVault(address registrar_) internal view returns (address vault_) {
        return ISPOGRegistrar(registrar_).vault();
    }

    function toAddress(bytes32 input_) internal pure returns (address output_) {
        return address(uint160(uint256(input_)));
    }

    function toBytes32(address input_) internal pure returns (bytes32 output_) {
        return bytes32(uint256(uint160(input_)));
    }

    function _contains(address registrar_, bytes32 listName_, address account_) private view returns (bool contains_) {
        return ISPOGRegistrar(registrar_).listContains(listName_, account_);
    }

    function _get(address registrar_, bytes32 key_) private view returns (bytes32 value_) {
        return ISPOGRegistrar(registrar_).get(key_);
    }

    function _toAddress(bytes32 input_) private pure returns (address output_) {
        return address(uint160(uint256(input_)));
    }
}
