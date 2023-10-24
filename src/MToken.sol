// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { IMToken } from "./interfaces/IMToken.sol";

import { ERC20 } from "solmate/tokens/ERC20.sol";

contract MToken is IMToken, ERC20 {
    address public immutable protocol;

    modifier onlyProtocol() {
        if (msg.sender != protocol) revert NotProtocol();

        _;
    }

    constructor(address protocol_) ERC20("M Token", "M", 18) {
        protocol = protocol_;
    }

    function mint(address account, uint256 amount) external onlyProtocol {
        _mint(account, amount);
    }

    function burn(address account, uint amount) external onlyProtocol {
        _burn(account, amount);
    }
}
