// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import { IERC712 } from "./IERC712.sol";

interface IUpdateCollateralSigVerifier is IERC712 {
    function UPDATE_COLLATERAL_TYPEHASH() external view returns (bytes32 delegationTypehash);

    function recoverValidator(
        address minter,
        uint256 amount,
        string memory metadata,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (address);
}
