// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

interface IERC20 {
    error ZeroDecreaseAllowance();

    error ZeroIncreaseAllowance();

    event Approval(address indexed account, address indexed spender, uint256 amount);

    event Transfer(address indexed account, address indexed recipient, uint256 amount);

    /******************************************************************************************************************\
    |                                             Interactive Functions                                                |
    \******************************************************************************************************************/

    function approve(address spender, uint256 amount) external returns (bool success);

    function decreaseAllowance(address spender, uint256 subtractedAmount) external returns (bool success);

    function increaseAllowance(address spender, uint256 addedAmount) external returns (bool success);

    function transfer(address recipient, uint256 amount) external returns (bool success);

    function transferFrom(address account, address recipient, uint256 amount) external returns (bool success);

    /******************************************************************************************************************\
    |                                              View/Pure Functions                                                 |
    \******************************************************************************************************************/

    function allowance(address account, address spender) external view returns (uint256 allowance);

    function balanceOf(address account) external view returns (uint256 balance);

    function decimals() external view returns (uint8 decimals);

    function name() external view returns (string memory name);

    function symbol() external view returns (string memory symbol);

    function totalSupply() external view returns (uint256 totalSupply);
}
