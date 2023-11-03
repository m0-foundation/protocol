// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { IERC1271 } from "../interfaces/IERC1271.sol";

library SignatureChecker {
    enum RecoverError {
        NoError,
        InvalidSignature,
        InvalidSignatureLength,
        ExpiredSignature,
        InvalidSignatureS,
        InvalidSignatureV
    }

    function isValidSignature(address signer, bytes32 digest, bytes memory signature) internal view returns (bool) {
        return isValidECDSASignature(signer, digest, signature) || isValidERC1271Signature(signer, digest, signature);
    }

    function isValidECDSASignature(
        address signer,
        bytes32 digest,
        bytes memory signature
    ) internal view returns (bool) {
        (RecoverError error, address recovered) = recoverSigner(digest, type(uint256).max, signature);
        return error == RecoverError.NoError && recovered == signer;
    }

    function isValidERC1271Signature(
        address signer,
        bytes32 digest,
        bytes memory signature
    ) internal view returns (bool) {
        (bool success, bytes memory result) = signer.staticcall(
            abi.encodeCall(IERC1271.isValidSignature, (digest, signature))
        );
        return (success &&
            result.length >= 32 &&
            abi.decode(result, (bytes32)) == bytes32(IERC1271.isValidSignature.selector));
    }

    function recoverSigner(
        bytes32 digest,
        uint256 expiry,
        bytes memory signature
    ) internal view returns (RecoverError error, address signer) {
        if (block.timestamp > expiry) return (RecoverError.ExpiredSignature, address(0));
        if (signature.length != 65) return (RecoverError.InvalidSignatureLength, address(0));

        bytes32 r;
        bytes32 s;
        uint8 v;
        // ecrecover takes the signature parameters, and the only way to get them
        // currently is to use assembly.
        /// @solidity memory-safe-assembly
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        // Appendix F in the Ethereum Yellow paper (https://ethereum.github.io/yellowpaper/paper.pdf), defines
        // the valid range for s in (301): 0 < s < secp256k1n ÷ 2 + 1, and for v in (302): v ∈ {27, 28}.
        if (uint256(s) > uint256(0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0))
            return (RecoverError.InvalidSignatureS, address(0));
        if (v != 27 && v != 28) return (RecoverError.InvalidSignatureV, address(0));

        signer = ecrecover(digest, v, r, s);

        if (signer == address(0)) return (RecoverError.InvalidSignature, address(0));

        return (RecoverError.NoError, signer);
    }
}
