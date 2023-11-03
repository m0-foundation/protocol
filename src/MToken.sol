// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { IMToken } from "./interfaces/IMToken.sol";

import { ERC20 } from "solmate/tokens/ERC20.sol";

contract MToken is IMToken, ERC20 {
    /// @notice Protocol contract address
    address public immutable protocol;

    modifier onlyProtocol() {
        if (msg.sender != protocol) revert NotProtocol();

        _;
    }

    /**
     * @notice Constructor.
     * @param protocol_ The address of Protocol
     */
    constructor(address protocol_) ERC20("M Token", "M", 18) {
        protocol = protocol_;
    }

    /**
     * @notice Mints M Token by protocol.
     * @param account_ The address of account to mint
     * @param amount_ The amount of M Token to mint
     */
    function mint(address account_, uint256 amount_) external onlyProtocol {
        _mint(account_, amount_);
    }

    /**
     * @notice Burns M Token by protocol.
     * @param account_ The address of account to burn
     * @param amount_ The amount of M Token to burn
     */
    function burn(address account_, uint amount_) external onlyProtocol {
        _burn(account_, amount_);
    }
}
