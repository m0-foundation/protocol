// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

interface IERC712 {
    error InvalidSignature();

    error MalleableSignature();

    error ReusedNonce(uint256 nonce, uint256 currentNonce);

    error SignatureExpired(uint256 deadline, uint256 timestamp);

    error SignerMismatch(address account, address signer);

    function DOMAIN_SEPARATOR() external view returns (bytes32 domainSeparator);

    function nonces(address account) external view returns (uint256 nonce);
}
