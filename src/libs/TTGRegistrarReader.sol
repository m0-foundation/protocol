// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { ITTGRegistrar } from "../interfaces/ITTGRegistrar.sol";

/**
 * @title  Library to read TTG (Two Token Governance) Registrar contract parameters.
 * @author M^0 Labs
 */
library TTGRegistrarReader {
    /* ============ Variables ============ */

    /// @notice The name of parameter in TTG that defines the earner rate model contract.
    bytes32 internal constant EARNER_RATE_MODEL = "earner_rate_model";

    /// @notice The parameter name in TTG that defines the earners list.
    bytes32 internal constant EARNERS_LIST = "earners";

    /// @notice The parameter name in TTG that defines whether to ignore the earners list or not.
    bytes32 internal constant EARNERS_LIST_IGNORED = "earners_list_ignored";

    /// @notice The parameter name in TTG that defines the time to wait for mint request to be processed.
    bytes32 internal constant MINT_DELAY = "mint_delay";

    /// @notice The parameter name in TTG that defines the mint ratio.
    bytes32 internal constant MINT_RATIO = "mint_ratio"; // bps

    /// @notice The parameter name in TTG that defines the time while mint request can still be processed.
    bytes32 internal constant MINT_TTL = "mint_ttl";

    /// @notice The parameter name in TTG that defines the time to freeze minter.
    bytes32 internal constant MINTER_FREEZE_TIME = "minter_freeze_time";

    /// @notice The parameter name in TTG that defines the minter rate model contract.
    bytes32 internal constant MINTER_RATE_MODEL = "minter_rate_model";

    /// @notice The parameter name in TTG that defines the minters list.
    bytes32 internal constant MINTERS_LIST = "minters";

    /// @notice The parameter name in TTG that defines the penalty rate.
    bytes32 internal constant PENALTY_RATE = "penalty_rate"; // bps

    /// @notice The parameter name in TTG that defines the required interval to update collateral.
    bytes32 internal constant UPDATE_COLLATERAL_INTERVAL = "update_collateral_interval";

    /// @notice The parameter name that defines number of signatures required for successful collateral update.
    bytes32 internal constant UPDATE_COLLATERAL_VALIDATOR_THRESHOLD = "update_collateral_threshold";

    /// @notice The parameter name in TTG that defines the validators list.
    bytes32 internal constant VALIDATORS_LIST = "validators";

    /* ============ Internal View/Pure Functions ============ */

    /// @notice Gets the earner rate model contract address.
    function getEarnerRateModel(address registrar_) internal view returns (address) {
        return toAddress(_get(registrar_, EARNER_RATE_MODEL));
    }

    /// @notice Gets the mint delay.
    function getMintDelay(address registrar_) internal view returns (uint256) {
        return uint256(_get(registrar_, MINT_DELAY));
    }

    /// @notice Gets the minter freeze time.
    function getMinterFreezeTime(address registrar_) internal view returns (uint256) {
        return uint256(_get(registrar_, MINTER_FREEZE_TIME));
    }

    /// @notice Gets the minter rate model contract address.
    function getMinterRateModel(address registrar_) internal view returns (address) {
        return toAddress(_get(registrar_, MINTER_RATE_MODEL));
    }

    /// @notice Gets the mint TTL.
    function getMintTTL(address registrar_) internal view returns (uint256) {
        return uint256(_get(registrar_, MINT_TTL));
    }

    /// @notice Gets the mint ratio.
    function getMintRatio(address registrar_) internal view returns (uint256) {
        return uint256(_get(registrar_, MINT_RATIO));
    }

    /// @notice Gets the update collateral interval.
    function getUpdateCollateralInterval(address registrar_) internal view returns (uint256) {
        return uint256(_get(registrar_, UPDATE_COLLATERAL_INTERVAL));
    }

    /// @notice Gets the update collateral validator threshold.
    function getUpdateCollateralValidatorThreshold(address registrar_) internal view returns (uint256) {
        return uint256(_get(registrar_, UPDATE_COLLATERAL_VALIDATOR_THRESHOLD));
    }

    /// @notice Checks if the given earner is approved.
    function isApprovedEarner(address registrar_, address earner_) internal view returns (bool) {
        return _contains(registrar_, EARNERS_LIST, earner_);
    }

    /// @notice Checks if the `earners_list_ignored` exists.
    function isEarnersListIgnored(address registrar_) internal view returns (bool) {
        return _get(registrar_, EARNERS_LIST_IGNORED) != bytes32(0);
    }

    /// @notice Checks if the given minter is approved.
    function isApprovedMinter(address registrar_, address minter_) internal view returns (bool) {
        return _contains(registrar_, MINTERS_LIST, minter_);
    }

    /// @notice Checks if the given validator is approved.
    function isApprovedValidator(address registrar_, address validator_) internal view returns (bool) {
        return _contains(registrar_, VALIDATORS_LIST, validator_);
    }

    /// @notice Gets the penalty rate.
    function getPenaltyRate(address registrar_) internal view returns (uint256) {
        return uint256(_get(registrar_, PENALTY_RATE));
    }

    /// @notice Gets the vault contract address.
    function getVault(address registrar_) internal view returns (address) {
        return ITTGRegistrar(registrar_).vault();
    }

    /// @notice Converts given bytes32 to address.
    function toAddress(bytes32 input_) internal pure returns (address) {
        return address(uint160(uint256(input_)));
    }

    /// @notice Checks if the given list contains the given account.
    function _contains(address registrar_, bytes32 listName_, address account_) private view returns (bool) {
        return ITTGRegistrar(registrar_).listContains(listName_, account_);
    }

    /// @notice Gets the value of the given key.
    function _get(address registrar_, bytes32 key_) private view returns (bytes32) {
        return ITTGRegistrar(registrar_).get(key_);
    }
}
