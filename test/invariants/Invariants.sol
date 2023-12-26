// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { console2 } from "../../lib/forge-std/src/Test.sol";
import { IProtocol } from "../../src/interfaces/IProtocol.sol";
import { IMToken } from "../../src/interfaces/IMToken.sol";

library Invariants {
    // Invariant 1: Protocol totalOwedM >= totalSupply of M Token.
    function checkInvariant1(address protocol_, address mToken_) internal view returns (bool success_) {
        success_ = IProtocol(protocol_).totalOwedM() >= IMToken(mToken_).totalSupply();
    }

    // Invariant 2: Protocol totalOwedM = totalSupply of M Token after updateIndex is called.
    function checkInvariant2(address protocol_, address mToken_) internal view returns (bool success_) {
        success_ = IProtocol(protocol_).totalOwedM() == IMToken(mToken_).totalSupply();
    }
}
