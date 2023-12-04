// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

interface ISPOGRegistrar {
    function get(bytes32 key) external view returns (bytes32 value);

    function listContains(bytes32 list, address account) external view returns (bool contains);

    function vault() external view returns (address vault);
}
