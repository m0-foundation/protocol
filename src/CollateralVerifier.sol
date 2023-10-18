// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import { ISPOG } from "./interfaces/ISPOG.sol";
import { ICollateralVerifier } from "./interfaces/ICollateralVerifier.sol";

import { SignatureVerifier } from "./SignatureVerifier.sol";
import { StatelessERC712 } from "./StatelessERC712.sol";

contract CollateralVerifier is ICollateralVerifier, StatelessERC712 {
    bytes32 public constant VALIDATION_TYPEHASH =
        keccak256("Validation(address validator,address minter,uint256 collateral,uint256 timestamp)");

    bytes32 public constant MINTERS_LIST_NAME = "minters";
    bytes32 public constant VALIDATORS_LIST_NAME = "validators";

    constructor() StatelessERC712("ValidatedCollateralDecoder") {}

    function decode(
        address spog,
        bytes calldata data
    ) external view returns (address minter, uint256 collateral, uint256 timestamp) {
        return _decode(spog, data);
    }

    function _decode(
        address spog,
        bytes calldata data
    ) internal view returns (address minter, uint256 collateral, uint256 timestamp) {
        address validator;
        bytes memory signature;
        string memory metadata;
        (validator, minter, collateral, metadata, timestamp, signature) = abi.decode(
            data,
            (address, address, uint256, string, uint256, bytes)
        );

        if (!_isApprovedValidator(spog, validator)) revert InvalidValidator();
        if (!_isApprovedMinter(spog, minter)) revert InvalidMinter();

        bytes32 digest = _getValidationDigest(minter, collateral, metadata, timestamp);

        if (!SignatureVerifier.isValidSignature(validator, digest, signature)) revert InvalidSignature();
    }

    function getValidationDigest(
        address minter,
        uint256 collateral,
        string memory metadata,
        uint256 timestamp
    ) external view returns (bytes32) {
        return _getValidationDigest(minter, collateral, metadata, timestamp);
    }

    function _getValidationDigest(
        address minter,
        uint256 collateral,
        string memory metadata,
        uint256 timestamp
    ) internal view returns (bytes32) {
        return _getDigest(keccak256(abi.encode(VALIDATION_TYPEHASH, minter, collateral, metadata, timestamp)));
    }

    function _isApprovedMinter(address spog, address minter) internal view returns (bool) {
        return ISPOG(spog).listContains(MINTERS_LIST_NAME, minter);
    }

    function _isApprovedValidator(address spog, address validator) internal view returns (bool) {
        return ISPOG(spog).listContains(VALIDATORS_LIST_NAME, validator);
    }
}
