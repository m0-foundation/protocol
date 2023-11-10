// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { IMToken } from "./interfaces/IMToken.sol";

import { ERC20Permit } from "./ERC20Permit.sol";

contract MToken is IMToken, ERC20Permit {
    address public immutable protocol;

    modifier onlyProtocol() {
        if (msg.sender != protocol) revert NotProtocol();

        _;
    }

    /**
     * @notice Constructor.
     * @param protocol_ The address of Protocol
     */
    constructor(address protocol_) ERC20Permit("M Token", "M", 18) {
        protocol = protocol_;
    }

    function mint(address account_, uint256 amount_) external onlyProtocol {
        _mint(account_, amount_);
    }

    function burn(address account_, uint amount_) external onlyProtocol {
        _burn(account_, amount_);
    }
}
