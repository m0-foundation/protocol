// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import { ICollateralVerifier } from "./interfaces/ICollateralVerifier.sol";
import { ERC712 } from "./ERC712.sol";

abstract contract CollateralVerifier is ICollateralVerifier, ERC712 {
    // UPDATE_COLLATERAL_TYPEHASH =
    //     keccak256("UpdateCollateral(address minter,uint256 amount,string memory metadata,uint256 nonce,uint256 expiry)");
    bytes32 public constant UPDATE_COLLATERAL_TYPEHASH =
        keccak256(
            "UpdateCollateral(address minter,uint256 amount,string memory metadata,uint256 nonce,uint256 expiry)"
        );

    /******************************************************************************************************************\
    |                                      External/Public Interactive Functions                                       |
    \******************************************************************************************************************/

    function updateCollateral(address minter_, uint256 amount_) external {
        _updateCollateral(msg.sender, minter_, amount_);
    }

    function updateCollateralBySig(
        address minter_,
        uint256 amount_,
        string memory metadata_,
        uint256 nonce_,
        uint256 expiry_,
        uint8 v_,
        bytes32 r_,
        bytes32 s_
    ) external {
        bytes32 digest_ = _getUpdateCollateralDigest(minter_, amount_, metadata_, nonce_, expiry_);
        address signer_ = _getSigner(digest_, expiry_, v_, r_, s_);
        uint256 currentNonce_ = _nonces[signer_];

        // Nonce must equal the current unused nonce, before it is incremented.
        if (nonce_ == currentNonce_) revert ReusedNonce(nonce_, currentNonce_);

        // Nonce realistically cannot overflow.
        unchecked {
            _nonces[signer_] = currentNonce_ + 1;
        }

        _updateCollateral(signer_, minter_, amount_);
    }

    /******************************************************************************************************************\
    |                                          Internal Interactive Functions                                          |
    \******************************************************************************************************************/

    function _updateCollateral(address validator_, address minter_, uint256 amount) internal virtual;

    /******************************************************************************************************************\
    |                                           Internal View/Pure Functions                                           |
    \******************************************************************************************************************/

    function _getUpdateCollateralDigest(
        address minter_,
        uint256 amount_,
        string memory metadata_,
        uint256 nonce_,
        uint256 expiry_
    ) internal view returns (bytes32 digest_) {
        digest_ = _getDigest(
            keccak256(abi.encode(UPDATE_COLLATERAL_TYPEHASH, minter_, amount_, metadata_, nonce_, expiry_))
        );
    }
}
