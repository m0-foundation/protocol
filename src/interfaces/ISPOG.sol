// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

interface ISPOG {
    function listContains(bytes32 list, address account) external view returns (bool contains);
}
