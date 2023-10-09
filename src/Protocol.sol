// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import { IProtocol } from "./interfaces/IProtocol.sol";
import { ISPOG } from "./interfaces/ISPOG.sol";

contract Protocol is IProtocol {
    /******************************************************************************************************************\
    |                                                Protocol Registry Constants                                       |
    \******************************************************************************************************************/
    bytes32 public constant MINTERS_LIST_NAME = "minters";
    bytes32 public constant VALIDATORS_LIST_NAME = "validators";

    address public immutable spog;

    // string internal _name;
    // string internal _version;

    // /// @dev The EIP-712 typehash for the contract's domain
    // bytes32 internal constant DOMAIN_TYPEHASH =
    //     keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    // /// @dev The EIP-712 typehash for updateCollateral action
    // bytes32 internal constant UPDATE_COLLATERAL_TYPEHASH =
    //     keccak256("UpdateCollateral(address minter,uint256 amount,uint256 nonce,uint256 expiry)");

    // /// @dev The highest valid value for s in an ECDSA signature pair (0 < s < secp256k1n ÷ 2 + 1)
    // ///  See https://ethereum.github.io/yellowpaper/paper.pdf #307)
    // uint internal constant MAX_VALID_ECDSA_S = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    // /// @notice The next expected nonce for a minter, for validating update collateral via signature
    // mapping(address => uint) public minterNonce;

    constructor(address spog_) {
        spog = spog_;

        // name = "M Protocol";
        // version = 1;
    }

    /******************************************************************************************************************\
    |                                                Minter Functions                                                  |
    \******************************************************************************************************************/
    //
    //
    // updateCollateral
    // function updateCollateral(
    //     address minter,
    //     uint256 amount,
    //     uint256 nonce,
    //     uint256 expiry,
    //     uint8 v,
    //     bytes32 r,
    //     bytes32 s
    // ) external {
    //     if (uint256(s) > MAX_VALID_ECDSA_S) revert InvalidValueS();
    //     // v ∈ {27, 28} (source: https://ethereum.github.io/yellowpaper/paper.pdf #308)
    //     if (v != 27 && v != 28) revert InvalidValueV();
    //     bytes32 domainSeparator = keccak256(
    //         abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), keccak256(bytes(version)), block.chainid, address(this))
    //     );
    //     bytes32 structHash = keccak256(abi.encode(UPDATE_COLLATERAL_TYPEHASH, minter, amount, nonce, expiry));
    //     bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    //     address signatory = ecrecover(digest, v, r, s);
    //     if (signatory == address(0)) revert BadSignatory();
    //     if (ISPOG(spog).listContains(MINTERS_LIST_NAME, signatory)) revert BadSignatory();
    //     if (nonce != minterNonce[signatory]++) revert BadNonce();
    //     if (block.timestamp >= expiry) revert SignatureExpired();
    //     _updateCollateral(minter, amount);
    // }

    // function _updateCollateral(address minter, uint256 amount) internal {}

    // proposeMint, mint, cancel, freeze
    // burn
    // proposeRedeem, redeem
    // quit, leave / remove
    //
    //
    /******************************************************************************************************************\
    |                                                Primary Functions                                                 |
    \******************************************************************************************************************/
    //
    //
    // stake
    // withdraw
    //
    //
    /******************************************************************************************************************\
    |                                                Brains Functions                                                  |
    \******************************************************************************************************************/
    //
    //
    // updateIndices, updateBorrowIndex, updateStakingIndex
    // accruePenalties
    // mintRewardsToZeroHolders
    //
    //
}
