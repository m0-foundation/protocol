// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.21;

import { IProtocol } from "../../src/interfaces/IProtocol.sol";
import { IStatelessERC712 } from "../../src/interfaces/IStatelessERC712.sol";

library DigestHelper {
    function getUpdateCollateralDigest(
        address protocol_,
        address minter_,
        uint256 amount_,
        string memory metadata_,
        uint256[] calldata retrieveIds,
        uint256 timestamp_
    ) external view returns (bytes32) {
        return
            _getDigest(
                protocol_,
                keccak256(
                    abi.encode(
                        IProtocol(protocol_).UPDATE_COLLATERAL_TYPEHASH(),
                        minter_,
                        amount_,
                        metadata_,
                        retrieveIds,
                        timestamp_
                    )
                )
            );
    }

    function _getDigest(address protocol_, bytes32 internalDigest_) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", IStatelessERC712(protocol_).DOMAIN_SEPARATOR(), internalDigest_));
    }
}
