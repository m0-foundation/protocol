// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IMinterGateway } from "../../src/interfaces/IMinterGateway.sol";

import { ContinuousIndexingMath } from "../../src/libs/ContinuousIndexingMath.sol";

contract TestUtils is Test {
    uint16 internal constant ONE = 10_000;

    /* ============ index ============ */
    function _getContinuousIndexAt(
        uint32 minterRate_,
        uint128 initialIndex_,
        uint32 elapsedTime_
    ) internal pure returns (uint128) {
        return
            ContinuousIndexingMath.multiplyIndices(
                initialIndex_,
                ContinuousIndexingMath.getContinuousIndex(
                    ContinuousIndexingMath.convertFromBasisPoints(minterRate_),
                    elapsedTime_
                )
            );
    }

    /* ============ penalty ============ */
    function _getPenaltyPrincipal(
        uint240 penaltyBase_,
        uint32 penaltyRate_,
        uint128 index_
    ) internal pure returns (uint112) {
        return ContinuousIndexingMath.divideUp((penaltyBase_ * penaltyRate_) / ONE, index_);
    }

    /* ============ signatures ============ */
    function _makeKey(string memory name_) internal returns (uint256 privateKey_) {
        (, privateKey_) = makeAddrAndKey(name_);
    }

    function _getCollateralUpdateSignature(
        address minterGateway_,
        address minter_,
        uint256 collateral_,
        uint256[] memory retrievalIds_,
        bytes32 metadataHash_,
        uint256 timestamp_,
        uint256 privateKey_
    ) internal view returns (bytes memory) {
        return
            _getSignature(
                IMinterGateway(minterGateway_).getUpdateCollateralDigest(
                    minter_,
                    collateral_,
                    retrievalIds_,
                    metadataHash_,
                    timestamp_
                ),
                privateKey_
            );
    }

    function _getCollateralUpdateShortSignature(
        address minterGateway_,
        address minter_,
        uint256 collateral_,
        uint256[] memory retrievalIds_,
        bytes32 metadataHash_,
        uint256 timestamp_,
        uint256 privateKey_
    ) internal view returns (bytes memory) {
        return
            _getShortSignature(
                IMinterGateway(minterGateway_).getUpdateCollateralDigest(
                    minter_,
                    collateral_,
                    retrievalIds_,
                    metadataHash_,
                    timestamp_
                ),
                privateKey_
            );
    }

    function _getSignature(bytes32 digest_, uint256 privateKey_) internal pure returns (bytes memory) {
        (uint8 v_, bytes32 r_, bytes32 s_) = vm.sign(privateKey_, digest_);

        return abi.encodePacked(r_, s_, v_);
    }

    function _getShortSignature(bytes32 digest_, uint256 privateKey_) internal pure returns (bytes memory) {
        (uint8 v_, bytes32 r_, bytes32 s_) = vm.sign(privateKey_, digest_);

        bytes32 vs_ = s_;

        if (v_ == 28) {
            // then left-most bit of s has to be flipped to 1 to get vs
            vs_ = s_ | bytes32(uint256(1) << 255);
        }

        return abi.encodePacked(r_, vs_);
    }
}
