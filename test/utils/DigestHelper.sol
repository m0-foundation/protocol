// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { IERC712 } from "../../lib/common/src/interfaces/IERC712.sol";

import { IMinterGateway } from "../../src/interfaces/IMinterGateway.sol";

library DigestHelper {
    function getUpdateCollateralDigest(
        address minterGateway,
        address minter,
        uint256 collateral,
        uint256[] calldata retrievalIds,
        bytes32 metadataHash,
        uint256 timestamp
    ) public view returns (bytes32) {
        return
            getUpdateCollateralDigest(
                minterGateway,
                getUpdateCollateralInternalDigest(
                    minterGateway,
                    minter,
                    collateral,
                    retrievalIds,
                    metadataHash,
                    timestamp
                )
            );
    }

    function getUpdateCollateralDigest(
        address minterGateway,
        bytes32 internalDigest
    ) public view returns (bytes32 digest_) {
        return keccak256(abi.encodePacked("\x19\x01", IERC712(minterGateway).DOMAIN_SEPARATOR(), internalDigest));
    }

    function getUpdateCollateralInternalDigest(
        address minterGateway,
        address minter,
        uint256 collateral,
        uint256[] calldata retrievalIds,
        bytes32 metadataHash,
        uint256 timestamp
    ) public pure returns (bytes32 digest_) {
        return
            keccak256(
                abi.encode(
                    IMinterGateway(minterGateway).UPDATE_COLLATERAL_TYPEHASH(),
                    minter,
                    collateral,
                    retrievalIds,
                    metadataHash,
                    timestamp
                )
            );
    }
}
