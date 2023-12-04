// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IERC20Permit } from "../../lib/common/src/interfaces/IERC20Permit.sol";

import { IContinuousIndexing } from "./IContinuousIndexing.sol";

interface IMToken is IContinuousIndexing, IERC20Permit {
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

    /******************************************************************************************************************\
    |                                          External View/Pure Functions                                            |
    \******************************************************************************************************************/

    function earnerRate() external view returns (uint256 rate);

    function hasOptedOutOfEarning(address account) external view returns (bool hasOpted);

    function isEarning(address account) external view returns (bool isEarning);

    /// @notice The address of the Protocol contract.
    function protocol() external view returns (address protocol);

    function rateModel() external view returns (address rateModel);

    /// @notice The address of the SPOG Registrar contract.
    function spogRegistrar() external view returns (address spogRegistrar);

    function totalEarningSupply() external view returns (uint256 totalEarningSupply);

    function totalNonEarningSupply() external view returns (uint256 totalNonEarningSupply);
}
