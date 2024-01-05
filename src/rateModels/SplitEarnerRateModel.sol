// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { UIntMath } from "../lib/common/src/libs/UIntMath.sol";

import { TTGRegistrarReader } from "./libs/TTGRegistrarReader.sol";

import { IEarnerRateModel } from "../interfaces/IEarnerRateModel.sol";
import { IMToken } from "../interfaces/IMToken.sol";
import { IMinterGateway } from "../interfaces/IMinterGateway.sol";
import { IRateModel } from "../interfaces/IRateModel.sol";

/**
 * @title Earner Rate Model contract set in TTG (Two Token Governance) Registrar and accessed by MToken.
 * @author M^0 Labs
 */
contract SplitEarnerRateModel is IEarnerRateModel {
    uint256 internal constant _EARNER_SPLIT_MULTIPLIER = 9_000; // 90 % in basis points
    uint256 internal constant _ONE = 10_000; // 100 % in basis points

    /// @inheritdoc IEarnerRateModel
    address public immutable mToken;

    /// @inheritdoc IEarnerRateModel
    address public immutable minterGateway;

    /// @inheritdoc IEarnerRateModel
    address public immutable ttgRegistrar;

    /**
     * @notice Constructs the EarnerRateModel contract.
     * @param minterGateway_ The address of the Minter Gateway contract.
     */
    constructor(address minterGateway_) {
        if ((minterGateway = minterGateway_) == address(0)) revert ZeroMinterGateway();
        if ((ttgRegistrar = IMinterGateway(minterGateway_).ttgRegistrar()) == address(0)) revert ZeroTTGRegistrar();
        if ((mToken = IMinterGateway(minterGateway_).mToken()) == address(0)) revert ZeroMToken();
    }

    /// @inheritdoc IRateModel
    function rate() external view returns (uint256) {
        uint240 totalActiveOwedM_ = IMinterGateway(minterGateway).totalActiveOwedM();

        if (totalActiveOwedM_ == 0) return 0;

        uint256 totalEarningSupply_ = IMToken(mToken).totalEarningSupply();

        if (totalEarningSupply_ == 0) return baseRate();

        // NOTE: Calculate safety guard rate that prevents overprinting of M,
        //       and allows to provide % split between Earners and Distribution Vault.
        return
            UIntMath.min256(
                baseRate(),
                (_EARNER_SPLIT_MULTIPLIER * (IMinterGateway(minterGateway).minterRate() * totalActiveOwedM_)) /
                    totalEarningSupply_ /
                    _ONE
            );
    }

    /// @inheritdoc IEarnerRateModel
    function baseRate() public view returns (uint256 baseRate_) {
        return TTGRegistrarReader.getBaseEarnerRate(ttgRegistrar);
    }
}
