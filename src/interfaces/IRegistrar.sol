// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.26;

/**
 * @title  Registrar interface.
 * @author M^0 Labs
 */
interface IRegistrar {
    /**
     * @notice Key value pair getter.
     * @param  key The key to get the value of.
     * @return value The value of the key.
     */
    function get(bytes32 key) external view returns (bytes32 value);

    /**
     * @notice Checks if the list contains the account.
     * @param  list     The list to check.
     * @param  account  The account to check.
     * @return contains True if the list contains the account, false otherwise.
     */
    function listContains(bytes32 list, address account) external view returns (bool contains);

    /// @notice Returns the Portal contract address.
    function portal() external view returns (address portal);
}
