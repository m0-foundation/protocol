// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { console2 } from "../../../lib/forge-std/src/Test.sol";
import { CommonBase } from "../../../lib/forge-std/src/Base.sol";
import { StdCheats } from "../../../lib/forge-std/src/StdCheats.sol";
import { StdUtils } from "../../../lib/forge-std/src/StdUtils.sol";

import { IMToken } from "../../../src/interfaces/IMToken.sol";
import { IMinterGateway } from "../../../src/interfaces/IMinterGateway.sol";

import { TTGRegistrarReader } from "../../../src/libs/TTGRegistrarReader.sol";

import { AddressSet, LibAddressSet } from "../../utils/AddressSet.sol";
import { MockTTGRegistrar } from "../../utils/Mocks.sol";
import { TestUtils } from "../../utils/TestUtils.sol";

contract ProtocolHandler is CommonBase, StdCheats, StdUtils, TestUtils {
    using LibAddressSet for AddressSet;

    enum ActorType {
        Minter,
        Earner,
        NonEarner
    }

    uint256 internal constant _MINTERS_NUM = 10;
    uint256 internal constant _EARNERS_NUM = 10;
    uint256 internal constant _NON_EARNERS_NUM = 10;

    IMToken internal _mToken;
    IMinterGateway internal _minterGateway;
    MockTTGRegistrar internal _registrar;

    AddressSet internal _minters;
    AddressSet internal _earners;
    AddressSet internal _nonEarners;

    address _currentActor;

    uint256 internal _currentTimestamp;
    uint256 internal _randomAmountSeed;

    modifier adjustTimestamp(uint256 timeJumpSeed_) {
        _increaseCurrentTimestamp(_bound(timeJumpSeed_, 2 minutes, 10 days));

        vm.warp(_currentTimestamp);
        _;
    }

    function _getMinter(uint256 minterIndexSeed_) internal view returns (address) {
        return _minters.rand(minterIndexSeed_);
    }

    function _getEarner(uint256 earnerIndexSeed_) internal view returns (address) {
        return _earners.rand(earnerIndexSeed_);
    }

    function _getNonEarner(uint256 nonEarnerIndexSeed_) internal view returns (address) {
        return _nonEarners.rand(nonEarnerIndexSeed_);
    }

    constructor(IMinterGateway minterGateway_, IMToken mToken_, MockTTGRegistrar registrar_) {
        _minterGateway = minterGateway_;
        _mToken = mToken_;
        _registrar = registrar_;

        _currentTimestamp = block.timestamp;

        _initActors();
    }

    function updateBaseMinterRate(uint256 timeJumpSeed_, uint256 rate_) external adjustTimestamp(timeJumpSeed_) {
        rate_ = _bound(rate_, 100, 40000); // [0.1%, 400%] in basis points
        console2.log("Updating minter rate = %s at %s", rate_, block.timestamp);
        _registrar.updateConfig(TTGRegistrarReader.BASE_MINTER_RATE, rate_);
    }

    function updateBaseEarnerRate(uint256 timeJumpSeed_, uint256 rate_) external adjustTimestamp(timeJumpSeed_) {
        rate_ = _bound(rate_, 100, 40000); // [0.1%, 400%] in basis points
        console2.log("Updating earner rate = %s at %s", rate_, block.timestamp);
        _registrar.updateConfig(TTGRegistrarReader.BASE_EARNER_RATE, rate_);
    }

    function updateMinterGatewayIndex(uint256 timeJumpSeed_) external adjustTimestamp(timeJumpSeed_) {
        console2.log("Updating Minter Gateway index at %s", block.timestamp);
        _minterGateway.updateIndex();
    }

    function updateMTokenIndex(uint256 timeJumpSeed_) external adjustTimestamp(timeJumpSeed_) {
        console2.log("Updating M Token index at %s", block.timestamp);
        _mToken.updateIndex();
    }

    function mintMToEarner(
        uint256 timeJumpSeed_,
        uint256 minterIndexSeed_,
        uint256 earnerIndexSeed_,
        uint256 amount_
    ) external adjustTimestamp(timeJumpSeed_) {
        _mintMToMHolder(
            _getMinter(minterIndexSeed_),
            _getEarner(earnerIndexSeed_),
            _bound(amount_, 1e6, type(uint112).max - _mToken.principalOfTotalEarningSupply())
        );
    }

    function mintMToNonEarner(
        uint256 timeJumpSeed_,
        uint256 minterIndexSeed_,
        uint256 nonEarnerIndexSeed_,
        uint256 amount_
    ) external adjustTimestamp(timeJumpSeed_) {
        _mintMToMHolder(
            _getMinter(minterIndexSeed_),
            _getNonEarner(nonEarnerIndexSeed_),
            _bound(amount_, 1e6, type(uint240).max - _mToken.totalNonEarningSupply())
        );
    }

    function transferMFromNonEarnerToNonEarner(
        uint256 timeJumpSeed_,
        uint256 senderIndexSeed_,
        uint256 recipientIndexSeed_,
        uint256 amount_
    ) external adjustTimestamp(timeJumpSeed_) {
        address sender_ = _getNonEarner(senderIndexSeed_);
        address recipient_ = _getNonEarner(recipientIndexSeed_);

        _transferM(sender_, recipient_, amount_);
    }

    function transferMFromEarnerToNonEarner(
        uint256 timeJumpSeed_,
        uint256 senderIndexSeed_,
        uint256 recipientIndexSeed_,
        uint256 amount_
    ) external adjustTimestamp(timeJumpSeed_) {
        address sender_ = _getNonEarner(senderIndexSeed_);
        address recipient_ = _getNonEarner(recipientIndexSeed_);

        _transferM(sender_, recipient_, amount_);
    }

    function transferMFromNonEarnerToEarner(
        uint256 timeJumpSeed_,
        uint256 senderIndexSeed_,
        uint256 recipientIndexSeed_,
        uint256 amount_
    ) external adjustTimestamp(timeJumpSeed_) {
        address sender_ = _getNonEarner(senderIndexSeed_);
        address recipient_ = _getNonEarner(recipientIndexSeed_);

        _transferM(sender_, recipient_, amount_);
    }

    function transferMFromEarnerToEarner(
        uint256 timeJumpSeed_,
        uint256 senderIndexSeed_,
        uint256 recipientIndexSeed_,
        uint256 amount_
    ) external adjustTimestamp(timeJumpSeed_) {
        address sender_ = _getNonEarner(senderIndexSeed_);
        address recipient_ = _getNonEarner(recipientIndexSeed_);

        _transferM(sender_, recipient_, amount_);
    }

    function burnMForMinterFromEarner(
        uint256 timeJumpSeed_,
        uint256 minterIndexSeed_,
        uint256 earnerIndexSeed_,
        uint256 amount_
    ) external adjustTimestamp(timeJumpSeed_) {
        address minter_ = _getMinter(minterIndexSeed_);
        address earner_ = _getEarner(earnerIndexSeed_);
        amount_ = _bound(amount_, 1e6, _mToken.balanceOf(earner_));

        _burnMForMinterFromMHolder(minter_, earner_, amount_);
    }

    function burnMForMinterFromNonEarner(
        uint256 timeJumpSeed_,
        uint256 minterIndexSeed_,
        uint256 nonEarnerIndexSeed_,
        uint256 amount_
    ) external adjustTimestamp(timeJumpSeed_) {
        address minter_ = _getMinter(minterIndexSeed_);
        address nonEarner_ = _getNonEarner(nonEarnerIndexSeed_);
        amount_ = _bound(amount_, 1e6, _mToken.balanceOf(nonEarner_));

        _burnMForMinterFromMHolder(minter_, nonEarner_, amount_);
    }

    function deactivateMinter(uint256 timeJumpSeed_, uint256 minterIndexSeed_) external adjustTimestamp(timeJumpSeed_) {
        address minter_ = _getMinter(minterIndexSeed_);

        vm.assume(_minterGateway.isActiveMinter(minter_) == true);

        console2.log(
            "Deactivating minter %s with active owed M %s at %s",
            minter_,
            _minterGateway.activeOwedMOf(minter_),
            block.timestamp
        );

        _registrar.removeFromList(TTGRegistrarReader.MINTERS_LIST, minter_);
        _minterGateway.deactivateMinter(minter_);
    }

    function _generateRandomAmount(address minter_, uint256 modulus_) internal returns (uint256) {
        _randomAmountSeed++;
        return uint256(keccak256(abi.encodePacked(block.timestamp, minter_, _randomAmountSeed))) % modulus_;
    }

    function _initActors() internal {
        for (uint256 i; i < _MINTERS_NUM; ++i) {
            _minters.add(makeAddr(string(abi.encodePacked("minter", i))));

            address minter_ = _minters.get(i);

            _registrar.addToList(TTGRegistrarReader.MINTERS_LIST, minter_);
            _minterGateway.activateMinter(minter_);
        }

        for (uint256 i = 0; i < _EARNERS_NUM; ++i) {
            _earners.add(makeAddr(string(abi.encodePacked("earner", i))));

            address earner_ = _earners.get(i);
            _registrar.addToList(TTGRegistrarReader.EARNERS_LIST, earner_);

            address minter_ = _minters.get(i);
            _mintMToMHolder(minter_, earner_, _generateRandomAmount(minter_, type(uint104).max / _EARNERS_NUM));

            // Start earning
            vm.prank(earner_);
            _mToken.startEarning();
        }

        for (uint256 i; i < _NON_EARNERS_NUM; ++i) {
            _nonEarners.add(makeAddr(string(abi.encodePacked("nonEarner", i))));

            address minter_ = _minters.get(i);
            _mintMToMHolder(
                minter_,
                _nonEarners.get(i),
                _generateRandomAmount(minter_, type(uint104).max / _NON_EARNERS_NUM)
            );
        }
    }

    function _increaseCurrentTimestamp(uint256 timeJump_) internal {
        _currentTimestamp += timeJump_;
    }

    function _mintMToMHolder(address minter_, address mHolder_, uint256 amount_) internal {
        if (!_minterGateway.isActiveMinter(minter_)) return;

        uint256[] memory retrievalIds = new uint256[](0);
        address[] memory validators = new address[](0);
        uint256[] memory timestamps = new uint256[](0);
        bytes[] memory signatures = new bytes[](0);

        // We don't update the collateral by more than the max allowed amount
        // We use uint232 instead of uint240 to have a little buffer
        amount_ = _minterGateway.collateralOf(minter_) + amount_ >= type(uint240).max
            ? type(uint240).max - _minterGateway.collateralOf(minter_)
            : amount_;

        // Get penalty if missed collateral updates and increase collateral to avoid undercollateralization
        amount_ += _minterGateway.getPenaltyForMissedCollateralUpdates(minter_);

        uint256 activeOwedMOfMinter_ = _minterGateway.activeOwedMOf(minter_);
        uint256 collateralOfMinter_ = _minterGateway.collateralOf(minter_);

        // Active owed M accrues interest, so we need to increase the collateral above the max allowed active owed M to avoid undercollateralization
        // We take a 20% buffer.
        if (activeOwedMOfMinter_ >= _minterGateway.maxAllowedActiveOwedMOf(minter_)) {
            amount_ += ((100e18 * activeOwedMOfMinter_) / 20e18) - collateralOfMinter_;
        }

        uint256 collateralAmount_ = collateralOfMinter_;

        // Collateral amount must be at least 10% higher than the amount of M minted by minter. We take a 20% buffer.
        collateralAmount_ += ((amount_ * 120) / 1e2);

        // If the collateral amount is above the max allowed collateral, we set it to the max allowed collateral
        if (collateralAmount_ > type(uint240).max) {
            collateralAmount_ = type(uint240).max;
            amount_ = type(uint240).max - collateralOfMinter_;
        }

        vm.prank(minter_);
        _minterGateway.updateCollateral(
            collateralAmount_,
            retrievalIds,
            bytes32(0),
            validators,
            timestamps,
            signatures
        );

        if (_mToken.isEarning(mHolder_)) {
            // It should not overflow principalOfTotalEarningSupply
            uint256 principalOfTotalEarningSupply_ = _mToken.principalOfTotalEarningSupply();

            // We use uint104 instead of uint112 to have a little buffer
            if (principalOfTotalEarningSupply_ + amount_ >= type(uint104).max) {
                amount_ = type(uint104).max - principalOfTotalEarningSupply_;
            }
        } else {
            // It should not overflow totalNonEarningSupply
            // We use uint232 instead of uint240 to have a little buffer
            if (_mToken.totalNonEarningSupply() + amount_ >= type(uint232).max) {
                amount_ = type(uint232).max - _mToken.totalNonEarningSupply();
            }

            // It should also not overflow uint112 if we want to convert it to principal
            // We use uint104 instead of uint112 to have a little buffer
            if (amount_ > type(uint104).max) {
                amount_ = type(uint104).max;
            }
        }

        vm.prank(minter_);
        uint256 mintId_ = _minterGateway.proposeMint(amount_, mHolder_);

        console2.log("Minting %s M to %s at %s", amount_, minter_, block.timestamp);

        vm.prank(minter_);
        _minterGateway.mintM(mintId_);
    }

    function _burnMForMinterFromMHolder(address minter_, address mHolder_, uint256 amount_) internal {
        console2.log("Burning %s M for minter %s by %s", amount_, minter_, mHolder_);

        vm.prank(mHolder_);
        _minterGateway.burnM(minter_, amount_);
    }

    function _transferM(address sender_, address recipient_, uint256 amount_) internal {
        // Don't send more than the balance of sender
        amount_ = _bound(amount_, 1e6, amount_ > _mToken.balanceOf(sender_) ? _mToken.balanceOf(sender_) : amount_);

        // Don't send more than the max balance of recipient
        amount_ = _mToken.balanceOf(recipient_) + amount_ > type(uint104).max
            ? _bound(amount_, 1e6, type(uint104).max - _mToken.balanceOf(recipient_))
            : amount_;

        console2.log("Transferring %s M from %s to %s", amount_, sender_, recipient_);

        vm.prank(sender_);
        _mToken.transfer(recipient_, amount_);
    }
}
