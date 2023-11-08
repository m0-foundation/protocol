// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

interface IMStakingToken {

    event Stake(address indexed account, uint256 amount);

    event Withdrawn(address indexed account, uint256 amount);

    function stake(uint256 amount) external;

    function withdraw(uint256 amount, address destination) external;

}
