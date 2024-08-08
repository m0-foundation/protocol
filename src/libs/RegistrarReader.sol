// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.26;

import { IRegistrar } from "../interfaces/IRegistrar.sol";

/**
 * @title  Library to read Registrar contract parameters.
 * @author M^0 Labs
 */
library RegistrarReader {
    /* ============ Variables ============ */

    /// @notice The parameter name in the Registrar that defines the earners list.
    bytes32 internal constant EARNERS_LIST = "earners";

    /// @notice The parameter name in the Registrar that defines whether to ignore the earners list.
    bytes32 internal constant EARNERS_LIST_IGNORED = "earners_list_ignored";

    /* ============ Internal View/Pure Functions ============ */

    /// @notice Checks if the given earner is approved.
    function isApprovedEarner(address registrar_, address earner_) internal view returns (bool) {
        return _contains(registrar_, EARNERS_LIST, earner_);
    }

    /// @notice Checks if the `earners_list_ignored` exists.
    function isEarnersListIgnored(address registrar_) internal view returns (bool) {
        return _get(registrar_, EARNERS_LIST_IGNORED) != bytes32(0);
    }

    /// @notice Gets the Portal contract address.
    function getPortal(address registrar_) internal view returns (address) {
        return IRegistrar(registrar_).portal();
    }

    /// @notice Converts given bytes32 to address.
    function toAddress(bytes32 input_) internal pure returns (address) {
        return address(uint160(uint256(input_)));
    }

    /// @notice Checks if the given list contains the given account.
    function _contains(address registrar_, bytes32 listName_, address account_) private view returns (bool) {
        return IRegistrar(registrar_).listContains(listName_, account_);
    }

    /// @notice Gets the value of the given key.
    function _get(address registrar_, bytes32 key_) private view returns (bytes32) {
        return IRegistrar(registrar_).get(key_);
    }
}
