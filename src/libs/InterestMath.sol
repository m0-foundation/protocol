// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

// Modified from Compound (https://github.com/compound-finance/gateway/blob/develop/ethereum/contracts/CashToken.sol)
library InterestMath {
    uint256 public constant SECONDS_PER_YEAR = 31_536_000;

    /// @notice The denomination of M rate APY BPS
    uint256 public constant BPS_BASE_SCALE = 1e4;

    /// @notice The denomination of `exponent` result
    uint256 public constant EXP_BASE_SCALE = 1e18;

    /// @notice Returns the latest value of M global rate index
    /// @dev index = previousIndex * e^(rate * time)
    function calculateIndex(uint256 previousIndex, uint256 rate, uint256 time) public pure returns (uint256) {
        return (previousIndex * exponent(rate, time)) / EXP_BASE_SCALE;
    }

    /// @notice Helper function to calculate e^rt part from countinous compounding interest formula
    /// Note: We use the third degree approximation of Taylor Series
    ///       e(x) = 1 + x/1! + x^2/2! + x^3/3!
    function exponent(uint256 rate, uint256 time) public pure returns (uint256) {
        uint256 scale = EXP_BASE_SCALE / BPS_BASE_SCALE;
        uint256 epower = (rate * time * scale) / SECONDS_PER_YEAR;
        uint256 first = epower * EXP_BASE_SCALE ** 2;
        uint256 second = (epower * epower * EXP_BASE_SCALE) / 2;
        uint256 third = (epower * epower * epower) / 6;
        return (EXP_BASE_SCALE ** 3 + first + second + third) / EXP_BASE_SCALE ** 2;
    }
}
