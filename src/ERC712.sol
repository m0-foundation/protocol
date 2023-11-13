// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { IERC712 } from "./interfaces/IERC712.sol";

abstract contract ERC712 is IERC712 {
    // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
    bytes32 internal constant _EIP712_DOMAIN_HASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    // keccak256("1");
    bytes32 internal constant _EIP712_VERSION_HASH = 0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6;

    bytes32 internal immutable _domainSeparator;

    string internal _name;

    mapping(address account => uint256 nonce) internal _nonces; // Nonces for all signatures.

    constructor(string memory name_) {
        _domainSeparator = keccak256(
            abi.encode(
                _EIP712_DOMAIN_HASH,
                keccak256(bytes(_name = name_)),
                _EIP712_VERSION_HASH,
                block.chainid,
                address(this)
            )
        );
    }

    /******************************************************************************************************************\
    |                                       External/Public View/Pure Functions                                        |
    \******************************************************************************************************************/

    function nonces(address account_) external view returns (uint256 nonce_) {
        nonce_ = _nonces[account_];
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32 domainSeparator_) {
        domainSeparator_ = _domainSeparator;
    }

    /******************************************************************************************************************\
    |                                           Internal View/Pure Functions                                           |
    \******************************************************************************************************************/

    function _getDigest(bytes32 internalDigest_) internal view returns (bytes32 digest_) {
        digest_ = keccak256(abi.encodePacked("\x19\x01", _domainSeparator, internalDigest_));
    }

    function _getSigner(
        bytes32 digest_,
        uint256 expiry_,
        uint8 v_,
        bytes32 r_,
        bytes32 s_
    ) internal view returns (address signer_) {
        if (block.timestamp > expiry_) revert SignatureExpired(expiry_, block.timestamp);

        // Appendix F in the Ethereum Yellow paper (https://ethereum.github.io/yellowpaper/paper.pdf), defines
        // the valid range for s in (301): 0 < s < secp256k1n ÷ 2 + 1, and for v in (302): v ∈ {27, 28}.
        if (
            (uint256(s_) > uint256(0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0)) ||
            (v_ != 27 && v_ != 28)
        ) revert MalleableSignature();

        signer_ = ecrecover(digest_, v_, r_, s_);

        if (signer_ == address(0)) revert InvalidSignature();
    }
}
