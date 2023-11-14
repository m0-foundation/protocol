// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { IContinuousInterestIndexing } from "./IContinuousInterestIndexing.sol";

interface IMToken is IContinuousInterestIndexing {
    /******************************************************************************************************************\
    |                                                     Errors                                                       |
    \******************************************************************************************************************/

    error AlreadyEarning();

    error AlreadyNotEarning();

    error HasOptedOut();

    error IsApprovedEarner();

    error NotApprovedEarner();

    error NotProtocol();

    /******************************************************************************************************************\
    |                                                     Events                                                       |
    \******************************************************************************************************************/

    event StartedEarning(address indexed account);

    event StoppedEarning(address indexed account);

    event OptedOutOfEarning(address indexed account);

    /******************************************************************************************************************\
    |                                         External Interactive Functions                                           |
    \******************************************************************************************************************/

    function earningRate() external view returns (uint256 rate_);

    function hasOptedOutOfEarning(address account) external view returns (bool hasOpted);

    function isEarning(address account) external view returns (bool isEarning);

    /**
     * @notice The address of the Protocol contract.
     */
    function protocol() external view returns (address protocol);

    /**
     * @notice The address of the SPOG Registrar contract.
     */
    function spogRegistrar() external view returns (address spogRegistrar);

    function totalEarningSupply() external view returns (uint256 totalEarningSupply);

    /******************************************************************************************************************\
    |                                          External View/Pure Functions                                            |
    \******************************************************************************************************************/

    /**
     * @notice Burns M Token by protocol.
     * @param account The address of account to burn from.
     * @param amount The amount of M Token to burn.
     */
    function burn(address account, uint256 amount) external;

    /**
     * @notice Mints M Token by protocol.
     * @param account The address of account to mint to.
     * @param amount The amount of M Token to mint.
     */
    function mint(address account, uint256 amount) external;

    function startEarning() external;

    function startEarning(address account) external;

    function stopEarning() external;

    function stopEarning(address account) external;
}
