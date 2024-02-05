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

    address _currentActor;

    IndexStore public _indexStore;
    TimestampStore public _timestampStore;

    uint32 internal _currentTimestamp;
    uint256 internal _randomAmountSeed;

    modifier adjustTimestamp(uint256 timeJump_) {
        _timestampStore.increaseCurrentTimestamp(uint32(_bound(timeJump_, 2 minutes, 10 days)));
        vm.warp(_timestampStore.currentTimestamp());
        _;
    }

    modifier useCurrentTimestamp() {
        vm.warp(_timestampStore.currentTimestamp());
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

    constructor(
        IMinterGateway minterGateway_,
        IMToken mToken_,
        MockTTGRegistrar registrar_,
        IndexStore indexStore_,
        TimestampStore timestampStore_
    ) {
        _currentTimestamp = uint32(block.timestamp);

        _minterGateway = minterGateway_;
        _mToken = mToken_;
        _registrar = registrar_;
        _indexStore = indexStore_;
        _timestampStore = timestampStore_;

        _initActors();
    }

    function updateBaseMinterRate(uint256 timeJumpSeed_, uint256 rate_) external adjustTimestamp(timeJumpSeed_) {
        rate_ = _bound(rate_, 10, 40_000); // [0.1%, 400%] in basis points

        console2.log("Updating minter rate = %s at %s", rate_, block.timestamp);
        _registrar.updateConfig(TTGRegistrarReader.BASE_MINTER_RATE, rate_);
    }

    function updateBaseEarnerRate(uint256 timeJumpSeed_, uint256 rate_) external adjustTimestamp(timeJumpSeed_) {
        rate_ = _bound(rate_, 10, 40_000); // [0.1%, 400%] in basis points

        console2.log("Updating earner rate = %s at %s", rate_, block.timestamp);
        _registrar.updateConfig(TTGRegistrarReader.BASE_EARNER_RATE, rate_);
    }

    function updateMinterGatewayIndex(uint256 timeJumpSeed_) external adjustTimestamp(timeJumpSeed_) {
        console2.log("Updating Minter Gateway index at %s", block.timestamp);
        _indexStore.setMinterIndex(_minterGateway.updateIndex());
    }

    function updateMTokenIndex(uint256 timeJumpSeed_) external adjustTimestamp(timeJumpSeed_) {
        console2.log("Updating M Token index at %s", block.timestamp);
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

    function _updateCollateral(address minter_, uint256 amount_) internal returns (uint256) {
        uint240 collateralOfMinter_ = _minterGateway.collateralOf(minter_);

        // If the collateral of minter is already greater than the max allowed collateral, we return early.
        // Assuming an index starting at 1e12, to fit in a principal amount of type(uint112).max, the collateral amount must be at most type(uint144).max
        if (collateralOfMinter_ >= type(uint144).max) {
            return 0;
        }

        uint256[] memory retrievalIds = new uint256[](0);
        address[] memory validators = new address[](0);
        uint256[] memory timestamps = new uint256[](0);
        bytes[] memory signatures = new bytes[](0);

        uint128 currentEarnerIndex_ = _indexStore.setEarnerIndex(_mToken.updateIndex());
        _indexStore.setMinterIndex(_minterGateway.updateIndex());

        // Get penalty if missed collateral updates and increase collateral to avoid undercollateralization
        amount_ += _minterGateway.getPenaltyForMissedCollateralUpdates(minter_);

        uint256 activeOwedMOfMinter_ = _minterGateway.activeOwedMOf(minter_);

        // Active owed M accrues interest, so we need to increase the collateral above the max allowed active owed M to avoid undercollateralization
        // We take a 20% buffer.
        if (activeOwedMOfMinter_ >= _minterGateway.maxAllowedActiveOwedMOf(minter_)) {
            amount_ += ((100e18 * activeOwedMOfMinter_) / 20e18) - collateralOfMinter_;
        }

        uint256 collateralAmount_ = collateralOfMinter_;

        // Collateral amount must be at least 10% higher than the amount of M minted by minter. We take a 20% buffer.
        collateralAmount_ += ((amount_ * 120) / 1e2);

        // If the collateral amount is above the max allowed collateral, we set it to the max allowed collateral.
        if (collateralAmount_ >= type(uint144).max) {
            collateralAmount_ = type(uint144).max;
            amount_ = type(uint144).max - collateralOfMinter_;
        }

        // If principalOfTotalNonEarningSupply or principalOfexcessOwedM have overflowed, we return early.
        if (
            (_mToken.totalNonEarningSupply() * EXP_SCALED_ONE) / _mToken.currentIndex() >= type(uint112).max ||
            (_minterGateway.excessOwedM() * EXP_SCALED_ONE) / _minterGateway.currentIndex() >= type(uint112).max
        ) return 0;

        // If principalOfMaxAllowedActiveOwedM will overflow, we return early.
        if (
            ((collateralAmount_ - _minterGateway.totalPendingCollateralRetrievalOf(minter_)) * EXP_SCALED_ONE) /
                _minterGateway.currentIndex() >=
            type(uint112).max
        ) return 0;

        uint240 nextTotalMSupply_ = uint240(_mToken.totalSupply());
        uint240 nextTotalOwedM_ = _minterGateway.totalActiveOwedM() +
            _minterGateway.getPenaltyForMissedCollateralUpdates(minter_) +
            _minterGateway.totalInactiveOwedM();

        uint240 nextExcessOwedM_ = nextTotalOwedM_ > nextTotalMSupply_ ? nextTotalOwedM_ - nextTotalMSupply_ : 0;

        // If PrincipalOfTotalSupply will overflow during updateIndex() when minting excess owed M to the vault, we return early.
        if (
            uint256(_mToken.principalOfTotalEarningSupply()) +
                _getPrincipalAmountRoundedDown(_mToken.totalNonEarningSupply(), currentEarnerIndex_) +
                _getPrincipalAmountRoundedUp(nextExcessOwedM_, currentEarnerIndex_) >=
            type(uint112).max
        ) return 0;

        vm.prank(minter_);
        _minterGateway.updateCollateral(
            collateralAmount_,
            retrievalIds,
            bytes32(0),
            validators,
            timestamps,
            signatures
        );

        return amount_;
    }

    function _mintMToMHolder(address minter_, address mHolder_, uint256 amount_) internal {
        if (!_minterGateway.isActiveMinter(minter_)) return;

        amount_ = _updateCollateral(minter_, amount_);

        if (amount_ == 0) return;

        uint128 currentEarnerIndex_ = _indexStore.setEarnerIndex(_mToken.updateIndex());
        _indexStore.setMinterIndex(_minterGateway.updateIndex());

        uint112 principalOfTotalEarningSupply_ = _mToken.principalOfTotalEarningSupply();
        uint112 principalOfTotalNonEarningSupply_ = _getPrincipalAmountRoundedDown(
            _mToken.totalNonEarningSupply(),
            currentEarnerIndex_
        );

        if (_mToken.isEarning(mHolder_)) {
            // It should not overflow principalOfTotalEarningSupply
            if (principalOfTotalEarningSupply_ >= type(uint112).max) return;

            if (
                uint256(principalOfTotalEarningSupply_) +
                    _getPrincipalAmountRoundedDown(uint240(amount_), currentEarnerIndex_) >=
                type(uint112).max
            ) {
                amount_ = uint112(type(uint112).max - (principalOfTotalEarningSupply_ + 1));
            }
        } else {
            // It should not overflow principalOfTotalNonEarningSupply
            if (principalOfTotalNonEarningSupply_ >= type(uint112).max) return;

            if (
                uint256(principalOfTotalNonEarningSupply_) +
                    _getPrincipalAmountRoundedDown(uint240(amount_), currentEarnerIndex_) >=
                type(uint112).max
            ) {
                type(uint112).max - (principalOfTotalNonEarningSupply_);
            }
        }

        // It should not overflow PrincipalOfTotalSupply
        uint112 principalOfTotalSupply_ = principalOfTotalEarningSupply_ + principalOfTotalNonEarningSupply_;

        if (principalOfTotalSupply_ >= type(uint112).max) return;

        // currentPrincipalOfTotalEarningSupply_ + nextPrincipalOfTotalNonEarningSupply_
        if (
            uint256(principalOfTotalSupply_) + _getPrincipalAmountRoundedDown(uint240(amount_), currentEarnerIndex_) >=
            type(uint112).max
        ) {
            amount_ = type(uint112).max - (principalOfTotalSupply_ + 1);
        }

        // principalOfTotalOwedM = principalOfTotalActiveOwedM + principalOfTotalInactiveOwedM
        uint112 principalOfTotalOwedM_ = _minterGateway.principalOfTotalActiveOwedM() +
            _getPrincipalAmountRoundedUp(_minterGateway.totalInactiveOwedM(), currentEarnerIndex_);

        // It should not overflow PrincipalOfTotalOwedM
        if (principalOfTotalOwedM_ >= type(uint112).max) return;

        // nextPrincipalOfTotalOwedM = principalOfTotalOwedM + principalAmount
        if (
            uint256(principalOfTotalOwedM_) + _getPrincipalAmountRoundedDown(uint240(amount_), currentEarnerIndex_) >=
            type(uint112).max
        ) {
            amount_ = type(uint112).max - (principalOfTotalOwedM_ + 1);
        }

        uint240 nextTotalMSupply_ = uint240(_mToken.totalSupply() + amount_);
        uint240 nextTotalOwedM_ = _minterGateway.totalActiveOwedM() +
            _minterGateway.totalInactiveOwedM() +
            uint240(amount_);

        // If PrincipalOfTotalSupply will overflow when minting excess owed M to the vault, we return early.
        if (
            uint256(_mToken.principalOfTotalEarningSupply()) +
                _getPrincipalAmountRoundedDown(_mToken.totalNonEarningSupply(), currentEarnerIndex_) +
                _getPrincipalAmountRoundedUp(
                    nextTotalOwedM_ > nextTotalMSupply_ ? nextTotalOwedM_ - nextTotalMSupply_ : 0,
                    currentEarnerIndex_
                ) +
                amount_ >=
            type(uint112).max
        ) return;

        if (amount_ == 0) return;

        // Return early if the amount of M to mint will cause the minter to exceed their max allowed active owed M
        if (_minterGateway.activeOwedMOf(minter_) + amount_ > _minterGateway.maxAllowedActiveOwedMOf(minter_)) return;

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
        amount_ = _bound(amount_, 0, amount_ > _mToken.balanceOf(sender_) ? _mToken.balanceOf(sender_) : amount_);

        // Don't send more than the max balance of recipient
        amount_ = _mToken.balanceOf(recipient_) + amount_ > type(uint112).max
            ? _bound(amount_, 0, type(uint112).max - _mToken.balanceOf(recipient_))
            : amount_;

        console2.log("Transferring %s M from %s to %s", amount_, sender_, recipient_);

        vm.prank(sender_);
        _mToken.transfer(recipient_, amount_);
    }
}
