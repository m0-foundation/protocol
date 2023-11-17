// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.21;

import { IProtocol } from "../../src/interfaces/IProtocol.sol";
import { IStatelessERC712 } from "../../src/interfaces/IStatelessERC712.sol";

library DigestHelper {
    function getUpdateCollateralDigest(
        address protocol,
        address minter,
        uint256 collateral,
        uint256[] calldata retrieveIds,
        bytes32 metadata,
        uint256 timestamp
    ) public view returns (bytes32) {
        return
            getUpdateCollateralDigest(
                protocol,
                getUpdateCollateralInternalDigest(protocol, minter, collateral, retrieveIds, metadata, timestamp)
            );
    }

    function getUpdateCollateralDigest(address protocol, bytes32 internalDigest) public view returns (bytes32 digest_) {
        return keccak256(abi.encodePacked("\x19\x01", IStatelessERC712(protocol).DOMAIN_SEPARATOR(), internalDigest));
    }

    function getUpdateCollateralInternalDigest(
        address protocol,
        address minter,
        uint256 collateral,
        uint256[] calldata retrieveIds,
        bytes32 metadata,
        uint256 timestamp
    ) public pure returns (bytes32 digest_) {
        return
            keccak256(
                abi.encode(
                    IProtocol(protocol).UPDATE_COLLATERAL_TYPEHASH(),
                    minter,
                    collateral,
                    retrieveIds,
                    metadata,
                    timestamp
                )
            );
    }
}
