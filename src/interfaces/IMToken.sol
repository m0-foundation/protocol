// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

interface IMToken {
    error NotProtocol();

    function decimals() external view returns (uint8);

    function protocol() external view returns (address protocol);

    function mint(address account, uint256 amount) external;

    function burn(address account, uint256 amount) external;
}
