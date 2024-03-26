// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { console2 } from "../../../lib/forge-std/src/Test.sol";
import { CommonBase } from "../../../lib/forge-std/src/Base.sol";
import { StdCheats } from "../../../lib/forge-std/src/StdCheats.sol";
import { StdUtils } from "../../../lib/forge-std/src/StdUtils.sol";

import { IMToken } from "../../../src/interfaces/IMToken.sol";
import { IMinterGateway } from "../../../src/interfaces/IMinterGateway.sol";
import { IStableEarnerRateModel } from "../../../src/rateModels/interfaces/IStableEarnerRateModel.sol";

import { TTGRegistrarReader } from "../../../src/libs/TTGRegistrarReader.sol";

import { AddressSet, LibAddressSet } from "../../utils/AddressSet.sol";
import { MockTTGRegistrar } from "../../utils/Mocks.sol";
import { TestUtils } from "../../utils/TestUtils.sol";

import { IndexStore } from "../stores/IndexStore.sol";
import { TimestampStore } from "../stores/TimestampStore.sol";

contract ProtocolHandler is CommonBase, StdCheats, StdUtils, TestUtils {
    using LibAddressSet for AddressSet;

    uint256 internal constant _MINTERS_NUM = 10;
    uint256 internal constant _EARNERS_NUM = 10;
    uint256 internal constant _NON_EARNERS_NUM = 10;

    IMToken internal _mToken;
    IMinterGateway internal _minterGateway;
    MockTTGRegistrar internal _registrar;

    AddressSet internal _minters;
    AddressSet internal _earners;
    AddressSet internal _nonEarners;

    address internal _currentActor;

    IndexStore internal _indexStore;
    TimestampStore internal _timestampStore;

    uint256 internal _randomAmountSeed;

    modifier adjustTimestamp(uint256 timeJump_) {
        uint32 rateConfidenceInterval_ = IStableEarnerRateModel(_mToken.rateModel()).RATE_CONFIDENCE_INTERVAL();
        uint32 rateConfidenceExpires_ = uint32(_minterGateway.latestUpdateTimestamp()) + rateConfidenceInterval_;
        uint32 timeUntilRateConfidenceExpires_ = rateConfidenceExpires_ - _timestampStore.currentTimestamp();

        console2.log(
            "--> rate confidence expires at %s, in %s seconds",
            rateConfidenceExpires_,
            timeUntilRateConfidenceExpires_
        );

        if (timeUntilRateConfidenceExpires_ == 0) return;

        // Warping past the confidence interval knowingly can lead to overprinting (i.e. broken invariants).
        timeJump_ = _bound(timeJump_, 1, timeUntilRateConfidenceExpires_);
        vm.warp(_timestampStore.increaseCurrentTimestamp(uint32(timeJump_)));

        console2.log("--> time jump by %s to %s", timeJump_, _timestampStore.currentTimestamp());
        console2.log("--> totalOwedM %s, totalSupply %s", _minterGateway.totalOwedM(), _mToken.totalSupply());

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

    function _min(uint32 a_, uint32 b_) internal pure returns (uint32) {
        return a_ < b_ ? a_ : b_;
    }

    constructor(
        IMinterGateway minterGateway_,
        IMToken mToken_,
        MockTTGRegistrar registrar_,
        IndexStore indexStore_,
        TimestampStore timestampStore_
    ) {
        _minterGateway = minterGateway_;
        _mToken = mToken_;
        _registrar = registrar_;
        _indexStore = indexStore_;
        _timestampStore = timestampStore_;

        _initActors();
    }

    function updateBaseMinterRate(uint256 timeJumpSeed_, uint256 rate_) external adjustTimestamp(timeJumpSeed_) {
        rate_ = _bound(rate_, 10, 40_000); // [0.1%, 400%] in basis points

        console2.log("Updating minter rate = %s at %s", rate_, vm.getBlockTimestamp());
        _registrar.updateConfig(BASE_MINTER_RATE, rate_);
    }

    function updateBaseEarnerRate(uint256 timeJumpSeed_, uint256 rate_) external adjustTimestamp(timeJumpSeed_) {
        rate_ = _bound(rate_, 10, 40_000); // [0.1%, 400%] in basis points

        console2.log("Updating earner rate = %s at %s", rate_, vm.getBlockTimestamp());
        _registrar.updateConfig(MAX_EARNER_RATE, rate_);
    }

    function updateMinterGatewayIndex(uint256 timeJumpSeed_) external adjustTimestamp(timeJumpSeed_) {
        console2.log("Updating Minter Gateway index at %s", vm.getBlockTimestamp());
        _indexStore.setMinterIndex(_minterGateway.updateIndex());
    }

    function updateMTokenIndex(uint256 timeJumpSeed_) external adjustTimestamp(timeJumpSeed_) {
        console2.log("Updating M Token index at %s", vm.getBlockTimestamp());
        _indexStore.setEarnerIndex(_mToken.updateIndex());
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

        // If balance of earner is null, return early
        if (_mToken.balanceOf(earner_) == 0) return;
        amount_ = _bound(amount_, 1, _mToken.balanceOf(earner_));

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

        // If balance of non earner is null, return early
        if (_mToken.balanceOf(nonEarner_) == 0) return;
        amount_ = _bound(amount_, 1, _mToken.balanceOf(nonEarner_));

        _burnMForMinterFromMHolder(minter_, nonEarner_, amount_);
    }

    function deactivateMinter(uint256 timeJumpSeed_, uint256 minterIndexSeed_) external adjustTimestamp(timeJumpSeed_) {
        address minter_ = _getMinter(minterIndexSeed_);

        // We return early if the minter being deactivated is not active
        if (_minterGateway.isActiveMinter(minter_)) return;

        console2.log("Deactivating minter %s at %s", minter_, vm.getBlockTimestamp());

        _registrar.removeFromList(TTGRegistrarReader.MINTERS_LIST, minter_);
        _minterGateway.deactivateMinter(minter_);
    }

    function _generateRandomAmount(address minter_, uint256 modulus_) internal returns (uint256) {
        _randomAmountSeed++;
        return uint256(keccak256(abi.encodePacked(vm.getBlockTimestamp(), minter_, _randomAmountSeed))) % modulus_;
    }

    function _initActors() internal {
        for (uint256 i; i < _MINTERS_NUM; ++i) {
            console2.log("Init minter %s", i);
            _minters.add(makeAddr(string(abi.encodePacked("minter", i))));

            address minter_ = _minters.get(i);

            _registrar.addToList(TTGRegistrarReader.MINTERS_LIST, minter_);
            _minterGateway.activateMinter(minter_);
        }

        for (uint256 i = 0; i < _EARNERS_NUM; ++i) {
            console2.log("Init earner %s", i);

            vm.warp(_timestampStore.increaseCurrentTimestamp(uint32(1)));
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
            console2.log("Init non earner %s", i);

            vm.warp(_timestampStore.increaseCurrentTimestamp(uint32(1)));
            _nonEarners.add(makeAddr(string(abi.encodePacked("nonEarner", i))));

            address minter_ = _minters.get(i);
            _mintMToMHolder(
                minter_,
                _nonEarners.get(i),
                _generateRandomAmount(minter_, type(uint104).max / _NON_EARNERS_NUM)
            );
        }
    }

    function _updateCollateral(address minter_, uint256 amount_) internal {
        uint240 collateralOfMinter_ = _minterGateway.collateralOf(minter_);
        uint256 collateralAmount_ = collateralOfMinter_;

        uint256[] memory retrievalIds = new uint256[](0);
        address[] memory validators = new address[](0);
        uint256[] memory timestamps = new uint256[](0);
        bytes[] memory signatures = new bytes[](0);

        // Get penalty if missed collateral updates and increase collateral to avoid undercollateralization
        collateralAmount_ += _minterGateway.getPenaltyForMissedCollateralUpdates(minter_);

        uint256 activeOwedMOfMinter_ = _minterGateway.activeOwedMOf(minter_);

        // Active owed M accrues interest, so we need to increase the collateral above the max allowed active owed M
        // to avoid undercollateralization. We take a 20% buffer.
        if (activeOwedMOfMinter_ >= _minterGateway.maxAllowedActiveOwedMOf(minter_)) {
            collateralAmount_ += ((100e18 * activeOwedMOfMinter_) / 20e18) - collateralOfMinter_;
        }

        // Collateral amount must be at least 10% higher than the amount of M minted by minter. We take a 20% buffer.
        collateralAmount_ += ((amount_ * 120) / 1e2);

        vm.prank(minter_);
        _minterGateway.updateCollateral(
            collateralAmount_,
            retrievalIds,
            bytes32(0),
            validators,
            timestamps,
            signatures
        );
    }

    function _mintMToMHolder(address minter_, address mHolder_, uint256 amount_) internal {
        amount_ = bound(amount_, 100, 100e12);

        if (!_minterGateway.isActiveMinter(minter_)) return;

        _updateCollateral(minter_, amount_);

        if (amount_ == 0) return;

        vm.prank(minter_);
        uint256 mintId_ = _minterGateway.proposeMint(amount_, mHolder_);

        vm.prank(minter_);
        _minterGateway.mintM(mintId_);
    }

    function _burnMForMinterFromMHolder(address minter_, address mHolder_, uint256 amount_) internal {
        // If amount to burn will be 0, return early
        bool isActiveMinter_ = _minterGateway.isActiveMinter(minter_);

        if (isActiveMinter_ && _minterGateway.principalOfActiveOwedMOf(minter_) == 0) return;
        if (!isActiveMinter_ && _minterGateway.inactiveOwedMOf(minter_) == 0) return;

        if (amount_ == 0 || _getPrincipalAmountRoundedDown(uint240(amount_), _minterGateway.currentIndex()) == 0)
            return;

        vm.prank(mHolder_);
        _minterGateway.burnM(minter_, amount_);
    }

    function _transferM(address sender_, address recipient_, uint256 amount_) internal {
        // Don't send more than the balance of sender
        amount_ = _bound(amount_, 0, amount_ > _mToken.balanceOf(sender_) ? _mToken.balanceOf(sender_) : amount_);

        // Don't send more than the max balance of recipient
        amount_ = _mToken.balanceOf(recipient_) + amount_ > type(uint112).max
            ? _bound(amount_, 0, type(uint112).max - _mToken.balanceOf(recipient_))
            : amount_;

        console2.log("Transferring %s M from %s to %s", amount_, sender_, recipient_);
        console2.log("Transfer occurred at %s", vm.getBlockTimestamp());

        vm.prank(sender_);
        _mToken.transfer(recipient_, amount_);
    }
}
