// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IERC20Extended } from "../../lib/common/src/interfaces/IERC20Extended.sol";

import { IContinuousIndexing } from "./IContinuousIndexing.sol";

/// @title M Token Interface.
interface IMToken is IContinuousIndexing, IERC20Extended {
    /******************************************************************************************************************\
    |                                                     Errors                                                       |
    \******************************************************************************************************************/

    /// @notice Emitted when principal of total supply (earning and non-earning) will overflow a `type(uint112).max`.
    error OverflowsPrincipalOfTotalSupply();

    /// @notice Emitted when calling `stopEarning` for an account approved as earner by TTG.
    error IsApprovedEarner();

    /// @notice Emitted when calling `startEarning` for an account not approved as earner by TTG.
    error NotApprovedEarner();

    /// @notice Emitted when calling `mint`, `burn` not by Minter Gateway.
    error NotMinterGateway();

    ///  @notice Emitted in constructor if Minter Gateway is 0x0.
    error ZeroMinterGateway();

    ///  @notice Emitted in constructor if TTG Registrar is 0x0.
    error ZeroTTGRegistrar();

    /******************************************************************************************************************\
    |                                                     Events                                                       |
    \******************************************************************************************************************/

    /// @notice Emitted when account starts being an M earner.
    event StartedEarning(address indexed account);

    /// @notice Emitted when account stops being an M earner.
    event StoppedEarning(address indexed account);

    /******************************************************************************************************************\
    |                                         External Interactive Functions                                           |
    \******************************************************************************************************************/

    /**
     * @notice Mints tokens.
     * @param  account The address of account to mint to.
     * @param  amount  The amount of M Token to mint.
     */
    function mint(address account, uint256 amount) external;

    /**
     * @notice Burns tokens.
     * @param  account The address of account to burn from.
     * @param  amount  The amount of M Token to burn.
     */
    function burn(address account, uint256 amount) external;

    /// @notice Starts earning for caller if allowed by TTG.
    function startEarning() external;

    /// @notice Stops earning for caller.
    function stopEarning() external;

    /******************************************************************************************************************\
    |                                          External View/Pure Functions                                            |
    \******************************************************************************************************************/

    /// @notice The address of the Minter Gateway contract.
    function minterGateway() external view returns (address);

    /// @notice The address of the TTG Registrar contract.
    function ttgRegistrar() external view returns (address);

    /// @notice The address of TTG approved earner rate model.
    function rateModel() external view returns (address);

    /// @notice The current value of earner rate in basis points.
    function earnerRate() external view returns (uint32);

    /// @notice The principal of an earner M token balance.
    function principalBalanceOf(address account) external view returns (uint240);

    /// @notice The principal of the total earning supply of M Token.
    function principalOfTotalEarningSupply() external view returns (uint112);

    /// @notice The total earning supply of M Token.
    function totalEarningSupply() external view returns (uint240);

    /// @notice The total non-earning supply of M Token.
    function totalNonEarningSupply() external view returns (uint240);

    /// @notice Checks if account is an earner.
    function isEarning(address account) external view returns (bool);
}
