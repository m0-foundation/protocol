// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

library ContractHelper {
    function getContractFrom(address account_, uint256 nonce_) internal pure returns (address contract_) {
        contract_ = address(
            uint160(
                uint256(
                    keccak256(
                        nonce_ == 0x00
                            ? abi.encodePacked(bytes1(0xd6), bytes1(0x94), account_, bytes1(0x80))
                            : nonce_ <= 0x7f
                            ? abi.encodePacked(bytes1(0xd6), bytes1(0x94), account_, uint8(nonce_))
                            : nonce_ <= 0xff
                            ? abi.encodePacked(bytes1(0xd7), bytes1(0x94), account_, bytes1(0x81), uint8(nonce_))
                            : nonce_ <= 0xffff
                            ? abi.encodePacked(bytes1(0xd8), bytes1(0x94), account_, bytes1(0x82), uint16(nonce_))
                            : nonce_ <= 0xffffff
                            ? abi.encodePacked(bytes1(0xd9), bytes1(0x94), account_, bytes1(0x83), uint24(nonce_))
                            : abi.encodePacked(bytes1(0xda), bytes1(0x94), account_, bytes1(0x84), uint32(nonce_))
                    )
                )
            )
        );
    }
}
