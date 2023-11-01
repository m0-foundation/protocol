// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

abstract contract StatelessERC712 {
    // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
    bytes32 internal constant _EIP712_DOMAIN_HASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    // keccak256("1");
    bytes32 internal constant _EIP712_VERSION_HASH = 0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6;

    bytes32 internal immutable _domainSeparator;

    string internal _name;

    constructor(string memory name_) {
        _domainSeparator = keccak256(
            abi.encode(
                _EIP712_DOMAIN_HASH,
                keccak256(bytes(_name = name_)),
                _EIP712_VERSION_HASH,
                block.chainid,
                address(this) // TODO: Confirm that this exists in the constructor.
            )
        );
    }

    /******************************************************************************************************************\
    |                                       External/Public View/Pure Functions                                        |
    \******************************************************************************************************************/

    function DOMAIN_SEPARATOR() public view returns (bytes32 domainSeparator_) {
        domainSeparator_ = _domainSeparator;
    }

    /******************************************************************************************************************\
    |                                           Internal View/Pure Functions                                           |
    \******************************************************************************************************************/

    function _getDigest(bytes32 internalDigest_) internal view returns (bytes32 digest_) {
        digest_ = keccak256(abi.encodePacked("\x19\x01", _domainSeparator, internalDigest_));
    }
}
