// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IERC20Permit } from "../../lib/common/src/interfaces/IERC20Permit.sol";

import { IContinuousIndexing } from "./IContinuousIndexing.sol";

interface IMToken is IContinuousIndexing, IERC20Permit {
    /******************************************************************************************************************\
    |                                                     Errors                                                       |
    \******************************************************************************************************************/

    /// @notice Emitted when calling `startEarning` by an already earning account.
    error AlreadyEarning();

    /// @notice Emitted when calling `stopEarning` by a non-earning account.
    error AlreadyNotEarning();

    /// @notice Emitted when calling `startEarning` for an account that has opted out of earning.
    error HasOptedOut();

    /// @notice Emitted when calling `stopEarning` for an account approved as earner by SPOG.
    error IsApprovedEarner();

    /// @notice Emitted when calling `startEarning` for an account if account is not approved by SPOG earner.
    error NotApprovedEarner();

    /// @notice Emitted when calling `mint`, `burn` not by Protocol.
    error NotProtocol();

    /******************************************************************************************************************\
    |                                                     Events                                                       |
    \******************************************************************************************************************/

    /// @notice Emitted when account starts to be an M earner.
    event StartedEarning(address indexed account);

    /// @notice Emitted when account stops to be an M earner.
    event StoppedEarning(address indexed account);

    /// @notice Emitted when account opts out of earning and caller attempt to start earning for them.
    event OptedOutOfEarning(address indexed account);

    /******************************************************************************************************************\
    |                                         External Interactive Functions                                           |
    \******************************************************************************************************************/

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

    /**
     * @notice Starts earning for caller if allowed by SPOG.
     */
    function startEarning() external;

    /**
     * @notice Starts earning for account if allowed by SPOG.
     * @param account The address of account to start earning for.
     */
    function startEarning(address account) external;

    /**
     * @notice Stops earning for caller.
     */
    function stopEarning() external;

    /**
     * @notice Stops earning for account.
     * @param account The address of account to stop earning for.
     */
    function stopEarning(address account) external;

    /**
     * @notice Opt out of earning so nobody except caller can trigger the start earning for the caller.
     */
    function optOutOfEarning() external;

    /******************************************************************************************************************\
    |                                          External View/Pure Functions                                            |
    \******************************************************************************************************************/

    /// @notice The address of the Protocol contract.
    function protocol() external view returns (address);

    /// @notice The address of the SPOG Registrar contract.
    function spogRegistrar() external view returns (address);

    /// @notice The address of SPOG approved earner rate model.
    function rateModel() external view returns (address);

    /// @notice The current value of earner rate in bps.
    function earnerRate() external view returns (uint256);

    /// @notice The total earning supply of M Token.
    function totalEarningSupply() external view returns (uint256);

    /// @notice The total non-earning supply of M Token.
    function totalNonEarningSupply() external view returns (uint256);

    /// @notice Checks if account is an earner.
    function isEarning(address account) external view returns (bool);

    /// @notice Checks if account has opted out of earning.
    function hasOptedOutOfEarning(address account) external view returns (bool);
}
