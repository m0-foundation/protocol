// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.26;

import { IERC20Extended } from "../../lib/common/src/interfaces/IERC20Extended.sol";

import { IContinuousIndexing } from "./IContinuousIndexing.sol";

/**
 * @title  M Token Interface.
 * @author M^0 Labs
 */
interface IMToken is IContinuousIndexing, IERC20Extended {
    /* ============ Events ============ */

    /**
     * @notice Emitted when account starts being an M earner.
     * @param  account The account that started earning.
     */
    event StartedEarning(address indexed account);

    /**
     * @notice Emitted when account stops being an M earner.
     * @param  account The account that stopped earning.
     */
    event StoppedEarning(address indexed account);

    /* ============ Custom Errors ============ */

    /**
     * @notice Emitted when there is insufficient balance to decrement from `account`.
     * @param  account     The account with insufficient balance.
     * @param  rawBalance  The raw balance of the account.
     * @param  amount      The amount to decrement the `rawBalance` by.
     */
    error InsufficientBalance(address account, uint256 rawBalance, uint256 amount);

    /// @notice Emitted when calling `stopEarning` for an account approved as earner by the Registrar.
    error IsApprovedEarner();

    /// @notice Emitted when calling `startEarning` for an account not approved as earner by the Registrar.
    error NotApprovedEarner();

    /// @notice Emitted when the caller is not the Portal.
    error NotPortal();

    /// @notice Emitted when principal of total supply (earning and non-earning) will overflow a `type(uint112).max`.
    error OverflowsPrincipalOfTotalSupply();

    /// @notice Emitted in constructor if the Portal address in the Registrar is 0x0.
    error ZeroPortal();

    /// @notice Emitted in constructor if the Registrar address is 0x0.
    error ZeroRegistrar();

    /* ============ Interactive Functions ============ */

    /**
     * @notice Updates the index and mints tokens.
     * @dev    MUST only be callable by the Spoke Portal.
     * @param  account The address of account to mint to.
     * @param  amount  The amount of M Token to mint.
     * @param  index   The index to update to.
     */
    function mint(address account, uint256 amount, uint128 index) external;

    /**
     * @notice Burns `amount` of M tokens from `msg.sender`.
     * @dev    MUST only be callable by the Spoke Portal.
     * @param  amount  The amount of M Token to burn.
     */
    function burn(uint256 amount) external;

    /// @notice Starts earning for caller if allowed by TTG.
    function startEarning() external;

    /// @notice Stops earning for caller.
    function stopEarning() external;

    /**
     * @notice Stops earning for `account`.
     * @dev    MUST revert if `account` is an approved earner in the Registrar.
     * @param  account The account to stop earning for.
     */
    function stopEarning(address account) external;

    /* ============ View/Pure Functions ============ */

    /// @notice The address of the M Portal contract.
    function portal() external view returns (address);

    /// @notice The address of the Registrar contract.
    function registrar() external view returns (address);

    /**
     * @notice The principal of an earner M token balance.
     * @param  account The account to get the principal balance of.
     * @return The principal balance of the account.
     */
    function principalBalanceOf(address account) external view returns (uint240);

    /// @notice The principal of the total earning supply of M Token.
    function principalOfTotalEarningSupply() external view returns (uint112);

    /// @notice The total earning supply of M Token.
    function totalEarningSupply() external view returns (uint240);

    /// @notice The total non-earning supply of M Token.
    function totalNonEarningSupply() external view returns (uint240);

    /**
     * @notice Checks if account is an earner.
     * @param  account The account to check.
     * @return True if account is an earner, false otherwise.
     */
    function isEarning(address account) external view returns (bool);
}
