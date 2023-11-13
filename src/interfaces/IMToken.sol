// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

interface IMToken {
    error NotProtocol();

    /**
     * @notice The address of Protocol.
     */
    function protocol() external view returns (address protocol);

    /**
     * @notice Mints M Token by protocol.
     * @param account The address of account to mint to.
     * @param amount The amount of M Token to mint.
     */
    function mint(address account, uint256 amount) external;

    /**
     * @notice Burns M Token by protocol.
     * @param account The address of account to burn from.
     * @param amount The amount of M Token to burn.
     */
    function burn(address account, uint256 amount) external;
}
