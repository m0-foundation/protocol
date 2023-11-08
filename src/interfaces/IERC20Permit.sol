// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { IERC712 } from "./IERC712.sol";

interface IERC20Permit is IERC20, IERC712 {
    function permit(
        address account,
        address spender,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function PERMIT_TYPEHASH() external view returns (bytes32 typehash);
}
