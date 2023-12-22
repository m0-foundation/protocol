// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { IERC712Domain } from "../../lib/common/src/interfaces/IERC712Domain.sol";

import { IProtocol } from "../../src/interfaces/IProtocol.sol";

library DigestHelper {
    function getUpdateCollateralDigest(
        address protocol,
        address minter,
        uint256 collateral,
        uint256[] calldata retrievalIds,
        bytes32 metadataHash,
        uint256 timestamp
    ) public view returns (bytes32) {
        return
            getUpdateCollateralDigest(
                protocol,
                getUpdateCollateralInternalDigest(protocol, minter, collateral, retrievalIds, metadataHash, timestamp)
            );
    }

    function getUpdateCollateralDigest(address protocol, bytes32 internalDigest) public view returns (bytes32 digest_) {
        return keccak256(abi.encodePacked("\x19\x01", IERC712Domain(protocol).DOMAIN_SEPARATOR(), internalDigest));
    }

    function getUpdateCollateralInternalDigest(
        address protocol,
        address minter,
        uint256 collateral,
        uint256[] calldata retrievalIds,
        bytes32 metadataHash,
        uint256 timestamp
    ) public pure returns (bytes32 digest_) {
        return
            keccak256(
                abi.encode(
                    IProtocol(protocol).UPDATE_COLLATERAL_TYPEHASH(),
                    minter,
                    collateral,
                    retrievalIds,
                    metadataHash,
                    timestamp
                )
            );
    }
}
