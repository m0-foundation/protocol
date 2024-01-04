// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import "./pool/IUniswapV3PoolActions.sol";
import "./pool/IUniswapV3PoolState.sol";

/// @title The interface for a Uniswap V3 Pool
/// @notice A Uniswap pool facilitates swapping and automated market making between any two assets that strictly conform
/// to the ERC20 specification
/// @dev The pool interface is broken up into many smaller pieces
/// @dev Contract from Uniswap V3 core
///      https://github.com/Uniswap/v3-core/commit/4024732be626f4b4299a4314150d5c5471d59ed9
interface IUniswapV3Pool is IUniswapV3PoolState, IUniswapV3PoolActions {}
