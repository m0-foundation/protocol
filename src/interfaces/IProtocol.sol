// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

interface IProtocol {
    error NotMinter();

    function updateCollateral(bytes calldata data) external;
}
