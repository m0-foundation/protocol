// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import { IUpdateCollateralSigVerifier } from "./interfaces/IUpdateCollateralSigVerifier.sol";

import { ERC712 } from "./ERC712.sol";

contract CollateralVerifier is IUpdateCollateralSigVerifier, ERC712 {
    bytes32 public constant UPDATE_COLLATERAL_TYPEHASH =
        keccak256(
            "UpdateCollateral(address minter,uint256 amount,string memory metadata,uint256 nonce,uint256 expiry)"
        );

    constructor() ERC712("Protocol") {}

    /******************************************************************************************************************\
    |                                      External/Public Interactive Functions                                       |
    \******************************************************************************************************************/

    // NOTE: we keep nonces per minter, not per signer to avoid replay attacks.
    function recoverValidator(
        address minter_,
        uint256 amount_,
        string memory metadata_,
        uint256 nonce_,
        uint256 expiry_,
        uint8 v_,
        bytes32 r_,
        bytes32 s_
    ) external returns (address) {
        bytes32 digest_ = _getUpdateCollateralDigest(minter_, amount_, metadata_, nonce_, expiry_);
        address signer_ = _getSigner(digest_, expiry_, v_, r_, s_);
        uint256 currentNonce_ = _nonces[signer_];

        // Nonce must equal the current unused nonce, before it is incremented.
        if (nonce_ == currentNonce_) revert ReusedNonce(nonce_, currentNonce_);

        // Nonce realistically cannot overflow.
        unchecked {
            _nonces[minter_] = currentNonce_ + 1;
        }

        return signer_;
    }

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
