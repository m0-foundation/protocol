// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { ContractHelper } from "../lib/common/src/ContractHelper.sol";

import { ContinuousIndexingMath } from "../src/libs/ContinuousIndexingMath.sol";
import { TTGRegistrarReader } from "../src/libs/TTGRegistrarReader.sol";

import { IMinterGateway } from "../src/interfaces/IMinterGateway.sol";
import { ITTGRegistrar } from "../src/interfaces/ITTGRegistrar.sol";

import { StableEarnerRateModel } from "../src/rateModels/StableEarnerRateModel.sol";

import { MockMToken, MockRateModel, MockTTGRegistrar } from "./utils/Mocks.sol";
import { MinterGatewayHarness } from "./utils/MinterGatewayHarness.sol";
import { MTokenHarness } from "./utils/MTokenHarness.sol";
import { TestUtils } from "./utils/TestUtils.sol";

// TODO: add tests for `updateIndex` being called.
// TODO: more end state tests of `deactivateMinter`.

contract MinterGatewayTests is TestUtils {
    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _ttgVault = makeAddr("ttgVault");

    address internal _minter1 = makeAddr("minter1");

    address internal _validator1;
    uint256 internal _validator1Pk;
    address internal _validator2;
    uint256 internal _validator2Pk;

    uint256 internal _updateCollateralThreshold = 1;
    uint32 internal _updateCollateralInterval = 2000;
    uint32 internal _minterFreezeTime = 1000;
    uint32 internal _mintDelay = 1000;
    uint32 internal _mintTTL = 500;
    uint32 internal _mintRatio = 9000; // 90%, bps
    uint32 internal _penaltyRate = 100; // 1%, bps

    uint32 internal _earnerRate = 1_000; // 10%, bps
    uint32 internal _minterRate = 400; // 4%, bps

    MockMToken internal _mToken;
    MockRateModel internal _minterRateModel;
    MockTTGRegistrar internal _ttgRegistrar;
    MinterGatewayHarness internal _minterGateway;

    // Helper for a fuzzing test
    struct ValidatorAndKey {
        address validator;
        uint256 pk;
    }

    function setUp() external {
        (_validator1, _validator1Pk) = makeAddrAndKey("validator1");
        (_validator2, _validator2Pk) = makeAddrAndKey("validator2");

        _minterRateModel = new MockRateModel();

        _minterRateModel.setRate(_minterRate);

        _mToken = new MockMToken();

        _ttgRegistrar = new MockTTGRegistrar();

        _ttgRegistrar.setVault(_ttgVault);

        _ttgRegistrar.addToList(TTGRegistrarReader.MINTERS_LIST, _minter1);
        _ttgRegistrar.addToList(TTGRegistrarReader.VALIDATORS_LIST, _validator1);
        _ttgRegistrar.addToList(TTGRegistrarReader.VALIDATORS_LIST, _validator2);

        _ttgRegistrar.updateConfig(
            TTGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD,
            _updateCollateralThreshold
        );
        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, _updateCollateralInterval);

        _ttgRegistrar.updateConfig(TTGRegistrarReader.MINTER_FREEZE_TIME, _minterFreezeTime);
        _ttgRegistrar.updateConfig(TTGRegistrarReader.MINT_DELAY, _mintDelay);
        _ttgRegistrar.updateConfig(TTGRegistrarReader.MINT_TTL, _mintTTL);
        _ttgRegistrar.updateConfig(TTGRegistrarReader.MINT_RATIO, _mintRatio);
        _ttgRegistrar.updateConfig(TTGRegistrarReader.MINTER_RATE_MODEL, address(_minterRateModel));
        _ttgRegistrar.updateConfig(TTGRegistrarReader.PENALTY_RATE, _penaltyRate);

        _minterGateway = new MinterGatewayHarness(address(_ttgRegistrar), address(_mToken));

        _minterGateway.setIsActive(_minter1, true);
        _minterGateway.setLatestRate(_minterRate); // This can be `minterGateway.updateIndex()`, but is not necessary.
    }

    /* ============ constructor ============ */
    function test_constructor() external {
        assertEq(_minterGateway.ttgRegistrar(), address(_ttgRegistrar));
        assertEq(_minterGateway.ttgVault(), _ttgVault);
        assertEq(_minterGateway.mToken(), address(_mToken));
    }

    function test_constructor_zeroTTGRegistrar() external {
        vm.expectRevert(IMinterGateway.ZeroTTGRegistrar.selector);
        _minterGateway = new MinterGatewayHarness(address(0), address(_mToken));
    }

    function test_constructor_zeroTTGVault() external {
        vm.mockCall(
            address(_ttgRegistrar),
            abi.encodeWithSelector(ITTGRegistrar.vault.selector),
            abi.encode(address(0))
        );

        vm.expectRevert(IMinterGateway.ZeroTTGVault.selector);
        _minterGateway = new MinterGatewayHarness(address(_ttgRegistrar), address(_mToken));
    }

    function test_constructor_zeroMToken() external {
        vm.expectRevert(IMinterGateway.ZeroMToken.selector);
        _minterGateway = new MinterGatewayHarness(address(_ttgRegistrar), address(0));
    }

    /* ============ updateCollateral ============ */
    function test_updateCollateral() external {
        uint240 collateral = 100;
        uint256[] memory retrievalIds = new uint256[](0);
        uint40 signatureTimestamp = uint40(vm.getBlockTimestamp());

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = signatureTimestamp;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp,
            _validator1Pk
        );

        vm.expectEmit();
        emit IMinterGateway.CollateralUpdated(_minter1, collateral, 0, bytes32(0), signatureTimestamp);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        assertEq(_minterGateway.collateralOf(_minter1), collateral);
        assertEq(_minterGateway.collateralUpdateTimestampOf(_minter1), signatureTimestamp);
        assertEq(_minterGateway.collateralExpiryTimestampOf(_minter1), signatureTimestamp + _updateCollateralInterval);
        assertEq(_minterGateway.collateralPenaltyDeadlineOf(_minter1), signatureTimestamp + _updateCollateralInterval);
        assertEq(_minterGateway.maxAllowedActiveOwedMOf(_minter1), (collateral * _mintRatio) / ONE);
    }

    function testFuzz_updateCollateral(uint256 collateral_, uint256 threshold_, uint256 numberOfSignatures_) external {
        uint256 max_threshold = 5;
        threshold_ = bound(threshold_, 1, max_threshold);
        numberOfSignatures_ = bound(numberOfSignatures_, threshold_, max_threshold);
        collateral_ = bound(collateral_, 0, type(uint240).max / _mintRatio);
        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD, threshold_);

        uint256[] memory retrievalIds_ = new uint256[](0);
        uint40 signatureTimestamp_ = uint40(vm.getBlockTimestamp());
        uint256[] memory timestamps_ = new uint256[](numberOfSignatures_);

        ValidatorAndKey[] memory validatorsAndKeys_ = new ValidatorAndKey[](numberOfSignatures_);
        address[] memory validators_ = new address[](numberOfSignatures_);
        bytes[] memory signatures_ = new bytes[](numberOfSignatures_);

        for (uint256 i = 0; i < numberOfSignatures_; i++) {
            address newValidator_;
            uint256 newValidatorPk_;

            if (i == 0) {
                (newValidator_, newValidatorPk_) = makeAddrAndKey(string(abi.encode("validator", i)));
            } else {
                // @dev Next validator's address must be bigger to preserve right order of signers
                uint256 extraSalt_;

                while (newValidator_ <= validatorsAndKeys_[i - 1].validator) {
                    (newValidator_, newValidatorPk_) = makeAddrAndKey(string(abi.encode("validator", i, extraSalt_)));
                    extraSalt_++;
                }
            }

            validatorsAndKeys_[i] = ValidatorAndKey(newValidator_, newValidatorPk_);
            validators_[i] = validatorsAndKeys_[i].validator;
            _ttgRegistrar.addToList(TTGRegistrarReader.VALIDATORS_LIST, validators_[i]);
            timestamps_[i] = signatureTimestamp_;
            signatures_[i] = _getCollateralUpdateSignature(
                address(_minterGateway),
                _minter1,
                collateral_,
                retrievalIds_,
                bytes32(0),
                signatureTimestamp_,
                validatorsAndKeys_[i].pk
            );
        }

        vm.expectEmit();
        emit IMinterGateway.CollateralUpdated(_minter1, uint240(collateral_), 0, bytes32(0), signatureTimestamp_);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(
            uint240(collateral_),
            retrievalIds_,
            bytes32(0),
            validators_,
            timestamps_,
            signatures_
        );

        assertEq(_minterGateway.collateralOf(_minter1), uint240(collateral_));
        assertEq(_minterGateway.collateralUpdateTimestampOf(_minter1), signatureTimestamp_);
        assertEq(_minterGateway.collateralExpiryTimestampOf(_minter1), signatureTimestamp_ + _updateCollateralInterval);
        assertEq(_minterGateway.collateralPenaltyDeadlineOf(_minter1), signatureTimestamp_ + _updateCollateralInterval);
        assertEq(_minterGateway.maxAllowedActiveOwedMOf(_minter1), (collateral_ * _mintRatio) / ONE);
    }

    function test_updateCollateral_shortSignature() external {
        uint240 collateral = 100;
        uint256[] memory retrievalIds = new uint256[](0);
        uint40 signatureTimestamp = uint40(vm.getBlockTimestamp());

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = signatureTimestamp;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getCollateralUpdateShortSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp,
            _validator1Pk
        );

        vm.expectEmit();
        emit IMinterGateway.CollateralUpdated(_minter1, collateral, 0, bytes32(0), signatureTimestamp);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        assertEq(_minterGateway.collateralOf(_minter1), collateral);
        assertEq(_minterGateway.collateralUpdateTimestampOf(_minter1), signatureTimestamp);
        assertEq(_minterGateway.collateralExpiryTimestampOf(_minter1), signatureTimestamp + _updateCollateralInterval);
        assertEq(_minterGateway.collateralPenaltyDeadlineOf(_minter1), signatureTimestamp + _updateCollateralInterval);
        assertEq(_minterGateway.maxAllowedActiveOwedMOf(_minter1), (collateral * _mintRatio) / ONE);
    }

    function test_updateCollateral_inactiveMinter() external {
        uint256[] memory retrievalIds = new uint256[](0);
        address[] memory validators = new address[](0);
        uint256[] memory timestamps = new uint256[](0);
        bytes[] memory signatures = new bytes[](0);

        _minterGateway.setIsActive(_minter1, false);

        vm.prank(_validator1);
        vm.expectRevert(IMinterGateway.InactiveMinter.selector);
        _minterGateway.updateCollateral(100e18, retrievalIds, bytes32(0), validators, timestamps, signatures);
    }

    function test_updateCollateral_signatureArrayLengthsMismatch() external {
        vm.expectRevert(IMinterGateway.SignatureArrayLengthsMismatch.selector);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(
            100,
            new uint256[](0),
            bytes32(0),
            new address[](2),
            new uint256[](1),
            new bytes[](1)
        );

        vm.expectRevert(IMinterGateway.SignatureArrayLengthsMismatch.selector);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(
            100,
            new uint256[](0),
            bytes32(0),
            new address[](1),
            new uint256[](2),
            new bytes[](1)
        );

        vm.expectRevert(IMinterGateway.SignatureArrayLengthsMismatch.selector);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(
            100,
            new uint256[](0),
            bytes32(0),
            new address[](1),
            new uint256[](1),
            new bytes[](2)
        );
    }

    function test_updateCollateral_staleCollateralUpdate() external {
        uint256[] memory retrievalIds = new uint256[](0);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = vm.getBlockTimestamp();

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            100,
            retrievalIds,
            bytes32(0),
            vm.getBlockTimestamp(),
            _validator1Pk
        );

        vm.prank(_minter1);
        _minterGateway.updateCollateral(100, retrievalIds, bytes32(0), validators, timestamps, signatures);

        uint256 lastUpdateTimestamp = _minterGateway.collateralUpdateTimestampOf(_minter1);
        uint256 newTimestamp = lastUpdateTimestamp - 1;

        timestamps[0] = newTimestamp;
        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            100,
            retrievalIds,
            bytes32(0),
            newTimestamp,
            _validator1Pk
        );

        vm.expectRevert(
            abi.encodeWithSelector(IMinterGateway.StaleCollateralUpdate.selector, newTimestamp, lastUpdateTimestamp)
        );

        vm.prank(_minter1);
        _minterGateway.updateCollateral(100, retrievalIds, bytes32(0), validators, timestamps, signatures);
    }

    function test_updateCollateral_staleCollateralUpdate_sameTimestamp() external {
        uint256[] memory retrievalIds = new uint256[](0);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = vm.getBlockTimestamp();

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            100,
            retrievalIds,
            bytes32(0),
            vm.getBlockTimestamp(),
            _validator1Pk
        );

        vm.prank(_minter1);
        _minterGateway.updateCollateral(100, retrievalIds, bytes32(0), validators, timestamps, signatures);

        uint256 lastUpdateTimestamp = _minterGateway.collateralUpdateTimestampOf(_minter1);
        uint256 newTimestamp = lastUpdateTimestamp; // same timestamp

        timestamps[0] = newTimestamp;
        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            100,
            retrievalIds,
            bytes32(0),
            newTimestamp,
            _validator1Pk
        );

        vm.expectRevert(
            abi.encodeWithSelector(IMinterGateway.StaleCollateralUpdate.selector, newTimestamp, lastUpdateTimestamp)
        );

        vm.prank(_minter1);
        _minterGateway.updateCollateral(100, retrievalIds, bytes32(0), validators, timestamps, signatures);
    }

    function test_updateCollateral_invalidSignatureOrder() external {
        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD, 3);

        uint256 collateral = 100;
        uint256[] memory retrievalIds = new uint256[](0);
        uint256 timestamp = vm.getBlockTimestamp();

        bytes memory signature1_ = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            timestamp,
            _validator1Pk
        );

        bytes memory signature2_ = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            timestamp,
            _validator2Pk
        );

        address[] memory validators = new address[](3);
        validators[0] = _validator2;
        validators[1] = _validator2;
        validators[2] = _validator1;

        bytes[] memory signatures = new bytes[](3);
        signatures[0] = signature2_;
        signatures[1] = signature2_;
        signatures[2] = signature1_;

        uint256[] memory timestamps = new uint256[](3);
        timestamps[0] = timestamp;
        timestamps[1] = timestamp;
        timestamps[2] = timestamp;

        vm.expectRevert(IMinterGateway.InvalidSignatureOrder.selector);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);
    }

    function test_updateCollateral_signatureDoubleCount() external {
        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD, 2);

        uint256 collateral = 100;
        uint256[] memory retrievalIds = new uint256[](0);
        uint256 timestamp = vm.getBlockTimestamp();

        bytes memory signature1_ = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            timestamp,
            _validator1Pk
        );

        address[] memory validators = new address[](3);
        validators[0] = _validator1;
        validators[1] = address(0xdead);
        validators[2] = _validator1;

        bytes[] memory signatures = new bytes[](3);
        signatures[0] = signature1_;
        signatures[1] = new bytes(0);
        signatures[2] = signature1_;

        uint256[] memory timestamps = new uint256[](3);
        timestamps[0] = timestamp;
        timestamps[1] = timestamp;
        timestamps[2] = timestamp;

        vm.expectRevert(IMinterGateway.InvalidSignatureOrder.selector);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);
    }

    function test_updateCollateral_notEnoughValidSignatures() external {
        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD, 3);

        uint256 collateral = 100;
        uint256[] memory retrievalIds = new uint256[](0);
        uint256 timestamp = vm.getBlockTimestamp();

        bytes memory signature1_ = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            timestamp,
            _validator1Pk
        );

        bytes memory signature2_ = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            timestamp,
            _validator2Pk
        );

        (address validator3_, uint256 validator3Pk_) = makeAddrAndKey("validator3");
        bytes memory signature3_ = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            timestamp,
            validator3Pk_
        );

        (address validator4_, uint256 validator4Pk_) = makeAddrAndKey("validator4");
        _ttgRegistrar.addToList(TTGRegistrarReader.VALIDATORS_LIST, validator4_);
        bytes memory signature4_ = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            timestamp,
            validator4Pk_
        );

        address[] memory validators = new address[](4);
        validators[0] = _validator2;
        validators[1] = _validator1;
        validators[2] = validator4_;
        validators[3] = validator3_;

        bytes[] memory signatures = new bytes[](4);
        signatures[0] = signature2_;
        signatures[1] = signature1_;
        signatures[2] = signature4_;
        signatures[3] = signature3_;

        uint256[] memory timestamps = new uint256[](4);
        timestamps[0] = timestamp;
        timestamps[1] = timestamp;
        timestamps[2] = timestamp - 1;
        timestamps[3] = timestamp;

        vm.expectRevert(abi.encodeWithSelector(IMinterGateway.NotEnoughValidSignatures.selector, 2, 3));

        vm.prank(_minter1);
        _minterGateway.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);
    }

    /* ============ proposeMint ============ */
    function test_proposeMint() external {
        uint240 amount = 60e18;

        _minterGateway.setCollateralOf(_minter1, 100e18);
        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp());

        uint48 expectedMintId = _minterGateway.mintNonce() + 1;

        vm.expectEmit();
        emit IMinterGateway.MintProposed(expectedMintId, _minter1, amount, _alice);

        vm.prank(_minter1);
        uint256 mintId = _minterGateway.proposeMint(amount, _alice);

        assertEq(mintId, expectedMintId);

        (uint256 mintId_, uint256 timestamp_, address recipient_, uint256 amount_) = _minterGateway.mintProposalOf(
            _minter1
        );

        assertEq(mintId_, mintId);
        assertEq(amount_, amount);
        assertEq(recipient_, _alice);
        assertEq(timestamp_, vm.getBlockTimestamp());
    }

    function testFuzz_proposeMint(uint256 amount_, uint256 minterCollateral_, address recipient_) external {
        vm.assume(recipient_ != address(0));

        amount_ = bound(amount_, 1, type(uint240).max);
        minterCollateral_ = bound(minterCollateral_, amount_, type(uint240).max);

        _minterGateway.setCollateralOf(_minter1, minterCollateral_);
        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp());

        if (_minterGateway.maxAllowedActiveOwedMOf(_minter1) == 0) return;

        amount_ = bound(amount_, 1, _minterGateway.maxAllowedActiveOwedMOf(_minter1));

        uint48 expectedMintId_ = 1;

        vm.expectEmit();
        emit IMinterGateway.MintProposed(expectedMintId_, _minter1, uint240(amount_), recipient_);

        vm.prank(_minter1);
        uint256 mintId_ = _minterGateway.proposeMint(amount_, recipient_);

        assertEq(mintId_, expectedMintId_);

        (
            uint256 proposalMintId_,
            uint256 proposalTimestamp_,
            address proposalrecipient_,
            uint256 proposalAmount_
        ) = _minterGateway.mintProposalOf(_minter1);

        assertEq(proposalMintId_, mintId_);
        assertEq(proposalAmount_, amount_);
        assertEq(proposalrecipient_, recipient_);
        assertEq(proposalTimestamp_, vm.getBlockTimestamp());
    }

    function test_proposeMint_zeroMintAmount() external {
        vm.expectRevert(IMinterGateway.ZeroMintAmount.selector);

        vm.prank(_minter1);
        _minterGateway.proposeMint(0, _alice);
    }

    function test_proposeMint_zeroMintDestination() external {
        vm.expectRevert(IMinterGateway.ZeroMintDestination.selector);

        vm.prank(_minter1);
        _minterGateway.proposeMint(100e18, address(0));
    }

    function test_proposeMint_frozenMinter() external {
        vm.prank(_validator1);
        _minterGateway.freezeMinter(_minter1);

        vm.expectRevert(IMinterGateway.FrozenMinter.selector);

        vm.prank(_minter1);
        _minterGateway.proposeMint(100e18, makeAddr("to"));
    }

    function test_proposeMint_inactiveMinter() external {
        _minterGateway.setIsActive(_minter1, false);

        vm.expectRevert(IMinterGateway.InactiveMinter.selector);
        vm.prank(_alice);
        _minterGateway.proposeMint(100e18, _alice);
    }

    function test_proposeMint_undercollateralizedMint() external {
        _minterGateway.setCollateralOf(_minter1, 100e18);
        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp());

        vm.warp(vm.getBlockTimestamp() + _mintDelay);

        vm.expectRevert(abi.encodeWithSelector(IMinterGateway.Undercollateralized.selector, 100e18, 90e18));

        vm.prank(_minter1);
        _minterGateway.proposeMint(100e18, _alice);
    }

    /* ============ mintM ============ */
    function test_mintM() external {
        uint256 amount = 80e18;
        uint48 mintId = 1;

        _minterGateway.setCollateralOf(_minter1, 100e18);
        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp());

        _minterGateway.setMintProposalOf(_minter1, mintId, amount, vm.getBlockTimestamp(), _alice);

        vm.warp(vm.getBlockTimestamp() + _mintDelay);

        vm.expectEmit();
        emit IMinterGateway.MintExecuted(mintId, _minterGateway.getPrincipalAmountRoundedUp(80e18), 80e18);

        vm.prank(_minter1);
        _minterGateway.mintM(mintId);

        // check that mint request has been deleted
        (uint256 mintId_, uint256 timestamp_, address recipient_, uint256 amount_) = _minterGateway.mintProposalOf(
            _minter1
        );

        assertEq(mintId_, 0);
        assertEq(recipient_, address(0));
        assertEq(amount_, 0);
        assertEq(timestamp_, 0);

        // check that normalizedPrincipal has been updated
        assertTrue(_minterGateway.principalOfActiveOwedMOf(_minter1) > 0);
    }

    function test_mintM_smallAmount() external {
        uint256 amount = 1;
        uint48 mintId = 1;

        _minterGateway.setCollateralOf(_minter1, 100e6);
        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp());

        _minterGateway.setMintProposalOf(_minter1, mintId, amount, vm.getBlockTimestamp(), _alice);

        vm.warp(vm.getBlockTimestamp() + _mintDelay);

        vm.expectEmit();
        emit IMinterGateway.MintExecuted(mintId, 1, 1);

        vm.prank(_minter1);
        _minterGateway.mintM(mintId);

        assertEq(_minterGateway.activeOwedMOf(_minter1), 2); // rounding up leads to owedM == 2 for minted M == 1
    }

    function testFuzz_mintM(uint256 amount_, uint256 minterCollateral_, address recipient_) external {
        uint48 mintId_ = 1;

        amount_ = bound(amount_, 1, type(uint112).max);

        // Minter's collateral must be at least 10% higher than the amount of M minted by minter. We take a 20% buffer.
        minterCollateral_ = bound(minterCollateral_, amount_, type(uint112).max);
        minterCollateral_ += (minterCollateral_ * 20e18) / 1e18;

        _minterGateway.setCollateralOf(_minter1, minterCollateral_);
        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp());

        _minterGateway.setMintProposalOf(_minter1, mintId_, amount_, vm.getBlockTimestamp(), recipient_);

        vm.warp(vm.getBlockTimestamp() + _mintDelay);

        vm.expectEmit();
        emit IMinterGateway.MintExecuted(
            mintId_,
            _minterGateway.getPrincipalAmountRoundedUp(uint240(amount_)),
            uint240(amount_)
        );

        vm.prank(_minter1);
        _minterGateway.mintM(mintId_);

        // check that mint request has been deleted
        (
            uint256 proposalMintId_,
            uint256 proposalTimestamp_,
            address proposalrecipient_,
            uint256 proposalAmount_
        ) = _minterGateway.mintProposalOf(_minter1);

        assertEq(proposalMintId_, 0);
        assertEq(proposalAmount_, 0);
        assertEq(proposalrecipient_, address(0));
        assertEq(proposalTimestamp_, 0);

        // check that normalizedPrincipal has been updated
        assertGe(_minterGateway.principalOfActiveOwedMOf(_minter1), 0);
    }

    function test_mintM_inactiveMinter() external {
        vm.expectRevert(IMinterGateway.InactiveMinter.selector);

        vm.prank(makeAddr("someInactiveMinter"));
        _minterGateway.mintM(1);
    }

    function test_mintM_frozenMinter() external {
        vm.prank(_validator1);
        _minterGateway.freezeMinter(_minter1);

        vm.expectRevert(IMinterGateway.FrozenMinter.selector);

        vm.prank(_minter1);
        _minterGateway.mintM(1);
    }

    function test_mintM_pendingMintRequest() external {
        uint256 timestamp = vm.getBlockTimestamp();
        uint256 activeTimestamp_ = timestamp + _mintDelay;
        uint48 mintId = 1;

        _minterGateway.setMintProposalOf(_minter1, mintId, 100, timestamp, _alice);

        vm.warp(activeTimestamp_ - 10);

        vm.expectRevert(abi.encodeWithSelector(IMinterGateway.PendingMintProposal.selector, activeTimestamp_));

        vm.prank(_minter1);
        _minterGateway.mintM(mintId);
    }

    function test_mintM_expiredMintRequest() external {
        uint256 timestamp = vm.getBlockTimestamp();
        uint256 deadline_ = timestamp + _mintDelay + _mintTTL;
        uint48 mintId = 1;

        _minterGateway.setMintProposalOf(_minter1, mintId, 100, timestamp, _alice);

        vm.warp(deadline_ + 1);

        vm.expectRevert(abi.encodeWithSelector(IMinterGateway.ExpiredMintProposal.selector, deadline_));

        vm.prank(_minter1);
        _minterGateway.mintM(mintId);
    }

    function test_mintM_undercollateralizedMint() external {
        uint48 mintId = 1;

        _minterGateway.setCollateralOf(_minter1, 100e18);
        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp());

        _minterGateway.setMintProposalOf(_minter1, mintId, 95e18, vm.getBlockTimestamp(), _alice);

        vm.warp(vm.getBlockTimestamp() + _mintDelay + 1);

        vm.expectRevert(abi.encodeWithSelector(IMinterGateway.Undercollateralized.selector, 95e18, 90e18));

        vm.prank(_minter1);
        _minterGateway.mintM(mintId);
    }

    function test_mintM_undercollateralizedMint_outdatedCollateral() external {
        uint48 mintId = 1;

        _minterGateway.setCollateralOf(_minter1, 100e18);
        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp() - _updateCollateralInterval);

        _minterGateway.setMintProposalOf(_minter1, mintId, 95e18, vm.getBlockTimestamp(), _alice);

        vm.warp(vm.getBlockTimestamp() + _mintDelay + 1);

        vm.expectRevert(abi.encodeWithSelector(IMinterGateway.Undercollateralized.selector, 95e18, 0));

        vm.prank(_minter1);
        _minterGateway.mintM(mintId);
    }

    function test_mintM_invalidMintRequest() external {
        vm.expectRevert(IMinterGateway.InvalidMintProposal.selector);
        vm.prank(_minter1);
        _minterGateway.mintM(1);
    }

    function test_mintM_invalidMintRequest_mismatchOfIds() external {
        uint256 amount = 95e18;
        uint256 timestamp = vm.getBlockTimestamp();
        uint48 mintId = 1;

        _minterGateway.setMintProposalOf(_minter1, mintId, amount, timestamp, _alice);

        vm.expectRevert(IMinterGateway.InvalidMintProposal.selector);

        vm.prank(_minter1);
        _minterGateway.mintM(mintId - 1);
    }

    function test_mintM_overflowsPrincipalOfTotalOwedM() external {
        uint256 amount = 80e18;
        uint48 mintId = 1;

        _minterGateway.setPrincipalOfTotalActiveOwedM(type(uint112).max);
        _minterGateway.setCollateralOf(_minter1, 100e18);
        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp());

        _minterGateway.setMintProposalOf(_minter1, mintId, amount, vm.getBlockTimestamp(), _alice);

        vm.warp(vm.getBlockTimestamp() + _mintDelay);

        vm.expectRevert(IMinterGateway.OverflowsPrincipalOfTotalOwedM.selector);

        vm.prank(_minter1);
        _minterGateway.mintM(mintId);
    }

    /* ============ cancelMint ============ */
    function test_cancelMint_byValidator() external {
        uint48 mintId = 1;

        _minterGateway.setMintProposalOf(_minter1, mintId, 100, vm.getBlockTimestamp(), _alice);

        vm.expectEmit();
        emit IMinterGateway.MintCanceled(mintId, _validator1);

        vm.prank(_validator1);
        _minterGateway.cancelMint(_minter1, mintId);

        (uint256 mintId_, uint256 timestamp, address recipient_, uint256 amount_) = _minterGateway.mintProposalOf(
            _minter1
        );

        assertEq(mintId_, 0);
        assertEq(recipient_, address(0));
        assertEq(amount_, 0);
        assertEq(timestamp, 0);
    }

    function testFuzz_cancelMint_byValidator(uint256 mintId_, address recipient_) external {
        mintId_ = bound(mintId_, 1, type(uint48).max);
        _minterGateway.setMintProposalOf(_minter1, uint48(mintId_), 100, vm.getBlockTimestamp(), recipient_);

        vm.expectEmit();
        emit IMinterGateway.MintCanceled(uint48(mintId_), _validator1);

        vm.prank(_validator1);
        _minterGateway.cancelMint(_minter1, mintId_);

        (
            uint256 proposalMintId_,
            uint256 proposalTimestamp_,
            address proposalrecipient_,
            uint256 proposalAmount_
        ) = _minterGateway.mintProposalOf(_minter1);

        assertEq(proposalMintId_, 0);
        assertEq(proposalAmount_, 0);
        assertEq(proposalrecipient_, address(0));
        assertEq(proposalTimestamp_, 0);
    }

    function test_cancelMint_notApprovedValidator() external {
        vm.expectRevert(IMinterGateway.NotApprovedValidator.selector);
        vm.prank(makeAddr("someNonApprovedValidator"));
        _minterGateway.cancelMint(_minter1, 1);
    }

    function test_cancelMint_invalidMintProposal() external {
        vm.expectRevert(IMinterGateway.InvalidMintProposal.selector);
        vm.prank(_validator1);
        _minterGateway.cancelMint(_minter1, 1);

        vm.expectRevert(IMinterGateway.InvalidMintProposal.selector);
        vm.prank(_validator1);
        _minterGateway.cancelMint(_alice, 1);
    }

    function test_cancelMint_invalidMintProposal_idZero() external {
        vm.expectRevert(IMinterGateway.InvalidMintProposal.selector);
        vm.prank(_validator1);
        _minterGateway.cancelMint(_minter1, 0);
    }

    /* ============ freezeMinter ============ */

    // TODO: This test should just use test the effects of freezeMinter, another test should check that a frozen minter
    //       cannot proposeMint/mint.
    function test_freezeMinter() external {
        uint240 amount = 60e18;

        _minterGateway.setCollateralOf(_minter1, 100e18);
        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp());

        uint40 frozenUntil = uint40(vm.getBlockTimestamp()) + _minterFreezeTime;

        vm.expectEmit();
        emit IMinterGateway.MinterFrozen(_minter1, frozenUntil);

        assertEq(_minterGateway.isFrozenMinter(_minter1), false);

        vm.prank(_validator1);
        _minterGateway.freezeMinter(_minter1);

        assertEq(_minterGateway.isFrozenMinter(_minter1), true);
        assertEq(_minterGateway.frozenUntilOf(_minter1), frozenUntil);

        vm.expectRevert(IMinterGateway.FrozenMinter.selector);

        vm.prank(_minter1);
        _minterGateway.proposeMint(amount, _alice);

        // fast-forward to the time when minter is unfrozen
        vm.warp(frozenUntil);

        uint48 expectedMintId = _minterGateway.mintNonce() + 1;

        vm.expectEmit();
        emit IMinterGateway.MintProposed(expectedMintId, _minter1, amount, _alice);

        vm.prank(_minter1);
        uint mintId = _minterGateway.proposeMint(amount, _alice);

        assertEq(mintId, expectedMintId);
    }

    function test_freezeMinter_sequence() external {
        uint40 timestamp = uint40(vm.getBlockTimestamp());
        uint40 frozenUntil = timestamp + _minterFreezeTime;

        vm.expectEmit();
        emit IMinterGateway.MinterFrozen(_minter1, frozenUntil);

        // first freezeMinter
        vm.prank(_validator1);
        _minterGateway.freezeMinter(_minter1);

        vm.warp(timestamp + _minterFreezeTime / 2);

        vm.expectEmit();
        emit IMinterGateway.MinterFrozen(_minter1, frozenUntil + _minterFreezeTime / 2);

        vm.prank(_validator1);
        _minterGateway.freezeMinter(_minter1);
    }

    function test_freezeMinter_notApprovedValidator() external {
        vm.expectRevert(IMinterGateway.NotApprovedValidator.selector);
        vm.prank(_alice);
        _minterGateway.freezeMinter(_minter1);
    }

    /* ============ burnM ============ */
    function test_burnM() external {
        uint256 mintAmount_ = 1000000e18;
        uint48 mintId_ = 1;

        // initiate harness functions
        _minterGateway.setCollateralOf(_minter1, 10000000e18);
        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp());

        uint112 principalOfActiveOwedM_ = _mintM(_minterGateway, _minter1, _alice, mintId_, mintAmount_, _mintDelay);
        uint240 activeOwedM_ = _minterGateway.activeOwedMOf(_minter1);

        vm.expectEmit();
        emit IMinterGateway.BurnExecuted(_minter1, principalOfActiveOwedM_, activeOwedM_, _alice);

        vm.prank(_alice);
        _minterGateway.burnM(_minter1, activeOwedM_);

        assertEq(_minterGateway.principalOfActiveOwedMOf(_minter1), 0);

        assertEq(_minterGateway.activeOwedMOf(_minter1), 0);
        assertEq(_minterGateway.principalOfActiveOwedMOf(_minter1), 0);
    }

    function testFuzz_burnM(uint256 mintAmount_, uint256 minterCollateral_, address recipient_) external {
        uint48 mintId_ = 1;

        mintAmount_ = bound(mintAmount_, 1, type(uint112).max);
        minterCollateral_ = bound(minterCollateral_, mintAmount_, type(uint112).max);
        minterCollateral_ += (minterCollateral_ * 20e18) / 1e18;

        _minterGateway.setCollateralOf(_minter1, minterCollateral_);
        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp());

        uint112 principalOfActiveOwedM_ = _mintM(
            _minterGateway,
            _minter1,
            recipient_,
            mintId_,
            mintAmount_,
            _mintDelay
        );

        uint240 activeOwedM_ = _minterGateway.activeOwedMOf(_minter1);

        vm.expectEmit();
        emit IMinterGateway.BurnExecuted(_minter1, principalOfActiveOwedM_, activeOwedM_, recipient_);

        vm.prank(recipient_);
        _minterGateway.burnM(_minter1, activeOwedM_);

        assertEq(_minterGateway.activeOwedMOf(_minter1), 0);
        assertEq(_minterGateway.principalOfActiveOwedMOf(_minter1), 0);
    }

    function test_burnM_zeroBurnAmount() external {
        vm.expectRevert(IMinterGateway.ZeroBurnAmount.selector);
        vm.prank(_minter1);
        _minterGateway.burnM(_minter1, 0);
    }

    function test_burnM_repayHalfOfOutstandingValue() external {
        _minterGateway.setCollateralOf(_minter1, 1000e18);
        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp());

        uint112 principalOfActiveOwedM = 100e18;

        _minterGateway.setRawOwedMOf(_minter1, principalOfActiveOwedM);
        _minterGateway.setPrincipalOfTotalActiveOwedM(principalOfActiveOwedM);

        uint240 activeOwedM = _minterGateway.activeOwedMOf(_minter1);

        vm.expectEmit();
        emit IMinterGateway.BurnExecuted(_minter1, principalOfActiveOwedM / 2, activeOwedM / 2, _alice);

        vm.prank(_alice);
        _minterGateway.burnM(_minter1, activeOwedM / 2);

        assertEq(_minterGateway.principalOfActiveOwedMOf(_minter1), principalOfActiveOwedM / 2);

        vm.expectEmit();
        emit IMinterGateway.BurnExecuted(_minter1, principalOfActiveOwedM / 2, activeOwedM / 2, _bob);

        vm.prank(_bob);
        _minterGateway.burnM(_minter1, activeOwedM / 2);

        assertEq(_minterGateway.principalOfActiveOwedMOf(_minter1), 0);

        assertEq(_minterGateway.activeOwedMOf(_minter1), 0);
    }

    function testFuzz_burnM_repayHalfOfOutstandingValue(
        uint256 principalOfActiveOwedM_,
        uint256 minterCollateral_
    ) external {
        principalOfActiveOwedM_ = bound(principalOfActiveOwedM_, 1, type(uint112).max);
        minterCollateral_ = bound(minterCollateral_, principalOfActiveOwedM_, type(uint112).max);

        _minterGateway.setCollateralOf(_minter1, minterCollateral_);
        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp());

        vm.assume(principalOfActiveOwedM_ < _minterGateway.maxAllowedActiveOwedMOf(_minter1));

        if (principalOfActiveOwedM_ % 2 != 0) {
            // @dev make sure assertion with divison by 2 calculates accurately
            principalOfActiveOwedM_ -= 1;
        }

        _minterGateway.setRawOwedMOf(_minter1, principalOfActiveOwedM_);
        _minterGateway.setPrincipalOfTotalActiveOwedM(principalOfActiveOwedM_);

        uint240 activeOwedM = _minterGateway.activeOwedMOf(_minter1);

        if (activeOwedM / 2 == 0) return;

        vm.expectEmit();
        emit IMinterGateway.BurnExecuted(_minter1, uint112(principalOfActiveOwedM_ / 2), activeOwedM / 2, _alice);

        vm.prank(_alice);
        _minterGateway.burnM(_minter1, activeOwedM / 2);

        assertEq(_minterGateway.principalOfActiveOwedMOf(_minter1), principalOfActiveOwedM_ / 2);

        vm.expectEmit();
        emit IMinterGateway.BurnExecuted(_minter1, uint112(principalOfActiveOwedM_ / 2), activeOwedM / 2, _bob);

        vm.prank(_bob);
        _minterGateway.burnM(_minter1, activeOwedM / 2);

        assertEq(_minterGateway.principalOfActiveOwedMOf(_minter1), 0);
        assertEq(_minterGateway.activeOwedMOf(_minter1), 0);
    }

    function test_burnM_notEnoughBalanceToRepay() external {
        uint256 principalOfActiveOwedM = 100e18;

        _minterGateway.setRawOwedMOf(_minter1, principalOfActiveOwedM);

        uint256 activeOwedM = _minterGateway.activeOwedMOf(_minter1);

        _mToken.setBurnFail(true);

        vm.expectRevert();

        vm.prank(_alice);
        _minterGateway.burnM(_minter1, activeOwedM);
    }

    /* ============ penalties ============ */
    function test_updateCollateral_imposePenaltyForExpiredCollateralValue() external {
        uint256 collateral = 100e18;

        _minterGateway.setCollateralOf(_minter1, collateral);
        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp());
        _minterGateway.setRawOwedMOf(_minter1, 60e18);
        _minterGateway.setPrincipalOfTotalActiveOwedM(60e18);

        vm.warp(vm.getBlockTimestamp() + 3 * _updateCollateralInterval);

        uint240 penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        uint240 activeOwedM = _minterGateway.activeOwedMOf(_minter1);

        assertEq(penalty, (activeOwedM * 3 * _penaltyRate) / ONE);

        uint256[] memory retrievalIds = new uint256[](0);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256 signatureTimestamp = vm.getBlockTimestamp();

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = signatureTimestamp;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp,
            _validator1Pk
        );

        vm.expectEmit();
        emit IMinterGateway.PenaltyImposed(_minter1, _minterGateway.getPrincipalAmountRoundedUp(penalty), penalty);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        assertEq(
            _minterGateway.principalOfActiveOwedMOf(_minter1),
            60e18 + _minterGateway.getPrincipalAmountRoundedUp(penalty)
        );
    }

    function testFuzz_updateCollateral_imposePenaltyForExpiredCollateralValue(
        uint256 principalOfActiveOwedM_,
        uint256 minterCollateral_
    ) external {
        principalOfActiveOwedM_ = bound(principalOfActiveOwedM_, ONE, type(uint112).max / 2);
        minterCollateral_ = bound(minterCollateral_, principalOfActiveOwedM_ * 2, type(uint112).max);

        _minterGateway.setCollateralOf(_minter1, minterCollateral_);
        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp());

        _minterGateway.setRawOwedMOf(_minter1, principalOfActiveOwedM_);
        _minterGateway.setPrincipalOfTotalActiveOwedM(principalOfActiveOwedM_);

        uint40 missedIntervals_ = 3;
        vm.warp(vm.getBlockTimestamp() + missedIntervals_ * _updateCollateralInterval);

        uint240 penalty_ = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        uint240 expectedPenalty_ = _getPresentAmountRoundedUp(
            uint112((principalOfActiveOwedM_ * missedIntervals_ * _penaltyRate) / ONE),
            _minterGateway.currentIndex()
        );

        assertEq(penalty_, expectedPenalty_);

        uint256[] memory retrievalIds_ = new uint256[](0);

        address[] memory validators_ = new address[](1);
        validators_[0] = _validator1;

        uint256 signatureTimestamp_ = vm.getBlockTimestamp();

        uint256[] memory timestamps_ = new uint256[](1);
        timestamps_[0] = signatureTimestamp_;

        bytes[] memory signatures_ = new bytes[](1);
        signatures_[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            minterCollateral_,
            retrievalIds_,
            bytes32(0),
            signatureTimestamp_,
            _validator1Pk
        );

        vm.prank(_minter1);
        _minterGateway.updateCollateral(
            minterCollateral_,
            retrievalIds_,
            bytes32(0),
            validators_,
            timestamps_,
            signatures_
        );

        uint256 expectedPrincipalOfActiveOwedM_ = principalOfActiveOwedM_ +
            _minterGateway.getPrincipalAmountRoundedDown(penalty_);

        assertEq(_minterGateway.principalOfActiveOwedMOf(_minter1), expectedPrincipalOfActiveOwedM_);
    }

    function test_updateCollateral_imposePenaltyForMissedCollateralUpdates() external {
        uint256 collateral = 100e18;
        uint256 amount = 180e18;

        uint256[] memory retrievalIds = new uint256[](0);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256 signatureTimestamp = vm.getBlockTimestamp();

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = signatureTimestamp;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp,
            _validator1Pk
        );

        vm.prank(_minter1);
        _minterGateway.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        _minterGateway.setRawOwedMOf(_minter1, amount);
        _minterGateway.setPrincipalOfTotalActiveOwedM(amount);

        vm.warp(vm.getBlockTimestamp() + _updateCollateralInterval - 1);

        uint256 penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, 0);

        // Step 2 - Update Collateral with excessive outstanding value
        signatureTimestamp = vm.getBlockTimestamp();
        timestamps[0] = signatureTimestamp;

        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp,
            _validator1Pk
        );

        uint240 activeOwedM = _minterGateway.activeOwedMOf(_minter1);
        uint256 maxAllowedOwedM = (collateral * _mintRatio) / ONE;
        uint240 expectedPenalty = uint240(((activeOwedM - maxAllowedOwedM) * _penaltyRate) / ONE);

        vm.expectEmit();
        emit IMinterGateway.PenaltyImposed(
            _minter1,
            _minterGateway.getPrincipalAmountRoundedDown(expectedPenalty),
            expectedPenalty
        );

        vm.prank(_minter1);
        _minterGateway.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        assertEq(_minterGateway.activeOwedMOf(_minter1), activeOwedM + expectedPenalty);
    }

    function testFuzz_updateCollateral_imposePenaltyForMissedCollateralUpdates(
        uint256 minterCollateral_,
        uint256 principalOfActiveOwedM_
    ) external {
        minterCollateral_ = bound(minterCollateral_, ONE, type(uint112).max / 6);
        principalOfActiveOwedM_ = bound(principalOfActiveOwedM_, minterCollateral_ * 2, type(uint112).max / 2);

        uint256[] memory retrievalIds_ = new uint256[](0);

        address[] memory validators_ = new address[](1);
        validators_[0] = _validator1;

        uint256 signatureTimestamp_ = vm.getBlockTimestamp();

        uint256[] memory timestamps_ = new uint256[](1);
        timestamps_[0] = signatureTimestamp_;

        bytes[] memory signatures_ = new bytes[](1);
        signatures_[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            minterCollateral_,
            retrievalIds_,
            bytes32(0),
            signatureTimestamp_,
            _validator1Pk
        );

        vm.prank(_minter1);
        _minterGateway.updateCollateral(
            minterCollateral_,
            retrievalIds_,
            bytes32(0),
            validators_,
            timestamps_,
            signatures_
        );

        _minterGateway.setRawOwedMOf(_minter1, principalOfActiveOwedM_);
        _minterGateway.setPrincipalOfTotalActiveOwedM(principalOfActiveOwedM_);

        vm.warp(vm.getBlockTimestamp() + _updateCollateralInterval - 1);

        assertEq(_minterGateway.getPenaltyForMissedCollateralUpdates(_minter1), 0);

        // Step 2 - Update Collateral with excessive outstanding value
        signatureTimestamp_ = vm.getBlockTimestamp();
        timestamps_[0] = signatureTimestamp_;

        signatures_[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            minterCollateral_,
            retrievalIds_,
            bytes32(0),
            signatureTimestamp_,
            _validator1Pk
        );

        uint240 activeOwedM_ = _minterGateway.activeOwedMOf(_minter1);
        uint128 currentIndex_ = _minterGateway.currentIndex();
        uint240 principalOfMaxAllowedActiveOwedM_ = _getPrincipalAmountRoundedDown(
            uint240(_minterGateway.maxAllowedActiveOwedMOf(_minter1)),
            currentIndex_
        );

        uint240 expectedPenalty_ = _getPresentAmountRoundedUp(
            uint112(((principalOfActiveOwedM_ - principalOfMaxAllowedActiveOwedM_) * _penaltyRate) / ONE),
            currentIndex_
        );

        vm.prank(_minter1);
        _minterGateway.updateCollateral(
            minterCollateral_,
            retrievalIds_,
            bytes32(0),
            validators_,
            timestamps_,
            signatures_
        );

        // 1 wei difference because of rounding
        assertApproxEqAbs(_minterGateway.activeOwedMOf(_minter1), activeOwedM_ + expectedPenalty_, 1);
    }

    function test_updateCollateral_accrueBothPenalties() external {
        _minterGateway.setCollateralOf(_minter1, 100e18);
        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp());
        _minterGateway.setRawOwedMOf(_minter1, 60e18);
        _minterGateway.setPrincipalOfTotalActiveOwedM(60e18);

        vm.warp(vm.getBlockTimestamp() + 2 * _updateCollateralInterval);

        uint240 penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        uint240 activeOwedM = _minterGateway.activeOwedMOf(_minter1);
        assertEq(penalty, (activeOwedM * 2 * _penaltyRate) / ONE);

        uint240 newCollateral = 10e18;

        uint256[] memory retrievalIds = new uint256[](0);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256 signatureTimestamp = vm.getBlockTimestamp();

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = signatureTimestamp;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            newCollateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp,
            _validator1Pk
        );

        vm.expectEmit();
        emit IMinterGateway.PenaltyImposed(_minter1, _minterGateway.getPrincipalAmountRoundedUp(penalty), penalty);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(newCollateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        uint240 expectedPenalty = (((activeOwedM + penalty) - (newCollateral * _mintRatio) / ONE) * _penaltyRate) / ONE;

        assertEq(_minterGateway.activeOwedMOf(_minter1), activeOwedM + penalty + expectedPenalty);

        assertEq(_minterGateway.collateralUpdateTimestampOf(_minter1), signatureTimestamp);
        assertEq(_minterGateway.penalizedUntilOf(_minter1), signatureTimestamp);
    }

    function testFuzz_updateCollateral_accrueBothPenalties(
        uint256 minterCollateral_,
        uint256 principalOfActiveOwedM_,
        uint256 newCollateral_
    ) external {
        principalOfActiveOwedM_ = bound(principalOfActiveOwedM_, ONE, type(uint112).max / 6);
        minterCollateral_ = bound(minterCollateral_, principalOfActiveOwedM_ * 2, type(uint112).max / 2);
        newCollateral_ = bound(newCollateral_, ONE, principalOfActiveOwedM_);

        _minterGateway.setCollateralOf(_minter1, minterCollateral_);
        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp());
        _minterGateway.setRawOwedMOf(_minter1, principalOfActiveOwedM_);
        _minterGateway.setPrincipalOfTotalActiveOwedM(principalOfActiveOwedM_);

        uint40 missedIntervals_ = 2;
        vm.warp(vm.getBlockTimestamp() + missedIntervals_ * _updateCollateralInterval);

        uint240 activeOwedM_ = _minterGateway.activeOwedMOf(_minter1);
        uint240 expectedMissedCollateralUpdatesPenalty_ = _getPresentAmountRoundedUp(
            uint112((principalOfActiveOwedM_ * missedIntervals_ * _penaltyRate) / ONE),
            _minterGateway.currentIndex()
        );

        assertEq(
            _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1),
            expectedMissedCollateralUpdatesPenalty_
        );

        uint256 signatureTimestamp_ = vm.getBlockTimestamp();

        uint256[] memory retrievalIds_ = new uint256[](0);

        address[] memory validators_ = new address[](1);
        validators_[0] = _validator1;

        uint256[] memory timestamps_ = new uint256[](1);
        timestamps_[0] = signatureTimestamp_;

        bytes[] memory signatures_ = new bytes[](1);
        signatures_[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            newCollateral_,
            retrievalIds_,
            bytes32(0),
            signatureTimestamp_,
            _validator1Pk
        );

        vm.prank(_minter1);
        _minterGateway.updateCollateral(
            newCollateral_,
            retrievalIds_,
            bytes32(0),
            validators_,
            timestamps_,
            signatures_
        );

        uint240 expectedUndercollateralizationPenalty_ = (((activeOwedM_ + expectedMissedCollateralUpdatesPenalty_) -
            (uint240(newCollateral_) * _mintRatio) /
            ONE) * _penaltyRate) / ONE;

        // 2 wei difference because of rounding
        assertApproxEqAbs(
            _minterGateway.activeOwedMOf(_minter1),
            activeOwedM_ + expectedMissedCollateralUpdatesPenalty_ + expectedUndercollateralizationPenalty_,
            2
        );

        assertEq(_minterGateway.collateralUpdateTimestampOf(_minter1), signatureTimestamp_);
        assertEq(_minterGateway.penalizedUntilOf(_minter1), signatureTimestamp_);
    }

    /* ============ burnM ============ */
    function test_burnM_imposePenaltyForExpiredCollateralValue() external {
        _minterGateway.setCollateralOf(_minter1, 100e18);
        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp());
        _minterGateway.setRawOwedMOf(_minter1, 60e18);
        _minterGateway.setPrincipalOfTotalActiveOwedM(60e18);

        vm.warp(vm.getBlockTimestamp() + 3 * _updateCollateralInterval);

        uint240 penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        uint240 activeOwedM = _minterGateway.activeOwedMOf(_minter1);

        assertEq(penalty, (activeOwedM * 3 * _penaltyRate) / ONE);

        vm.expectEmit();
        emit IMinterGateway.PenaltyImposed(_minter1, _minterGateway.getPrincipalAmountRoundedUp(penalty), penalty);

        vm.prank(_alice);
        _minterGateway.burnM(_minter1, activeOwedM);

        assertEq(
            _minterGateway.principalOfActiveOwedMOf(_minter1),
            _minterGateway.getPrincipalAmountRoundedUp(penalty)
        );
    }

    function testFuzz_burnM_imposePenaltyForExpiredCollateralValue(
        uint256 minterCollateral_,
        uint256 principalOfActiveOwedM_
    ) external {
        principalOfActiveOwedM_ = bound(principalOfActiveOwedM_, ONE, type(uint112).max / 6);
        minterCollateral_ = bound(minterCollateral_, principalOfActiveOwedM_, type(uint112).max / 2);

        _minterGateway.setCollateralOf(_minter1, minterCollateral_);
        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp());
        _minterGateway.setRawOwedMOf(_minter1, principalOfActiveOwedM_);
        _minterGateway.setPrincipalOfTotalActiveOwedM(principalOfActiveOwedM_);

        uint40 missedIntervals_ = 3;
        vm.warp(vm.getBlockTimestamp() + missedIntervals_ * _updateCollateralInterval);

        uint240 activeOwedM = _minterGateway.activeOwedMOf(_minter1);
        uint240 missedCollateralUpdatesPenalty_ = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        uint240 expectedMissedCollateralUpdatesPenalty_ = _getPresentAmountRoundedUp(
            uint112((principalOfActiveOwedM_ * missedIntervals_ * _penaltyRate) / ONE),
            _minterGateway.currentIndex()
        );

        assertEq(missedCollateralUpdatesPenalty_, expectedMissedCollateralUpdatesPenalty_);

        vm.prank(_alice);
        _minterGateway.burnM(_minter1, activeOwedM);

        assertEq(
            _minterGateway.principalOfActiveOwedMOf(_minter1),
            _getPrincipalAmountRoundedDown(expectedMissedCollateralUpdatesPenalty_, _minterGateway.currentIndex())
        );
    }

    function test_imposePenalty_penalizedUntil() external {
        uint256 collateral = 100e18;
        uint256 lastUpdateTimestamp = vm.getBlockTimestamp();

        _minterGateway.setCollateralOf(_minter1, collateral);
        _minterGateway.setUpdateTimestampOf(_minter1, lastUpdateTimestamp);
        _minterGateway.setRawOwedMOf(_minter1, 60e18);
        _minterGateway.setPrincipalOfTotalActiveOwedM(60e18);

        vm.warp(lastUpdateTimestamp + _updateCollateralInterval - 10);

        uint256 penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, 0);

        vm.warp(lastUpdateTimestamp + _updateCollateralInterval + 10);

        penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, (_minterGateway.activeOwedMOf(_minter1) * _penaltyRate) / ONE);

        uint256[] memory retrievalIds = new uint256[](0);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256 signatureTimestamp = vm.getBlockTimestamp();

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = signatureTimestamp;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp,
            _validator1Pk
        );

        vm.prank(_minter1);
        _minterGateway.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        uint256 penalizedUntil = _minterGateway.penalizedUntilOf(_minter1);

        assertEq(_minterGateway.collateralUpdateTimestampOf(_minter1), signatureTimestamp);
        assertEq(penalizedUntil, lastUpdateTimestamp + _updateCollateralInterval);

        vm.prank(_alice);
        _minterGateway.burnM(_minter1, 10e18);

        assertEq(_minterGateway.collateralUpdateTimestampOf(_minter1), signatureTimestamp);
        assertEq(_minterGateway.penalizedUntilOf(_minter1), penalizedUntil);
    }

    function test_imposePenalty_penalizedUntil_reducedInterval() external {
        uint256 collateral = 100e18;
        uint256 timestamp = vm.getBlockTimestamp();

        _minterGateway.setCollateralOf(_minter1, collateral);
        _minterGateway.setUpdateTimestampOf(_minter1, timestamp);
        _minterGateway.setRawOwedMOf(_minter1, 60e18);
        _minterGateway.setPrincipalOfTotalActiveOwedM(60e18);

        // Change update collateral interval, more frequent updates are required
        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, _updateCollateralInterval / 4);

        uint256 threeMissedIntervals = _updateCollateralInterval + (2 * _updateCollateralInterval) / 4;
        vm.warp(timestamp + threeMissedIntervals + 10);

        // Burn 2 units of M and impose penalty for 3 missed intervals
        vm.prank(_alice);
        _minterGateway.burnM(_minter1, 2);

        uint256 penalizedUntil = _minterGateway.penalizedUntilOf(_minter1);
        assertEq(penalizedUntil, timestamp + threeMissedIntervals);

        uint256 oneMoreMissedInterval = _updateCollateralInterval / 4;
        vm.warp(vm.getBlockTimestamp() + oneMoreMissedInterval);

        // Burn 2 units of M and impose penalty for 1 more missed interval
        vm.prank(_alice);
        _minterGateway.burnM(_minter1, 2);

        penalizedUntil = _minterGateway.penalizedUntilOf(_minter1);
        assertEq(penalizedUntil, timestamp + threeMissedIntervals + oneMoreMissedInterval);
    }

    function test_imposePenalty_principalOfTotalActiveOwedMOverflows() external {
        uint256 collateral = 100e18;
        uint256 lastUpdateTimestamp = vm.getBlockTimestamp();

        _minterGateway.setCollateralOf(_minter1, collateral);
        _minterGateway.setUpdateTimestampOf(_minter1, lastUpdateTimestamp);
        _minterGateway.setRawOwedMOf(_minter1, 60e18);

        vm.warp(lastUpdateTimestamp + _updateCollateralInterval - 10);

        uint256 penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, 0);

        vm.warp(lastUpdateTimestamp + _updateCollateralInterval + 10);

        penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, (_minterGateway.activeOwedMOf(_minter1) * _penaltyRate) / ONE);

        uint256 penaltyPrincipal_ = _minterGateway.getPrincipalAmountRoundedUp(uint240(penalty));

        // 1 is added to overflow `newPrincipalOfTotalActiveOwedM_`
        uint256 principalOfTotalActiveOwedM_ = type(uint112).max - penaltyPrincipal_ + 1;
        _minterGateway.setPrincipalOfTotalActiveOwedM(principalOfTotalActiveOwedM_);

        uint256[] memory retrievalIds = new uint256[](0);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256 signatureTimestamp = vm.getBlockTimestamp();

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = signatureTimestamp;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp,
            _validator1Pk
        );

        uint256 minterPrincipalOfActiveOwedMBefore_ = _minterGateway.principalOfActiveOwedMOf(_minter1);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        // Despite overflowing, `principalOfTotalActiveOwedM` is capped and equal to type(uint112).max
        assertEq(_minterGateway.principalOfTotalActiveOwedM(), type(uint112).max);
        assertEq(
            _minterGateway.principalOfActiveOwedMOf(_minter1),
            minterPrincipalOfActiveOwedMBefore_ + penaltyPrincipal_ - 1
        );
    }

    function testFuzz_imposePenalty_principalOfTotalActiveOwedMOverflows(
        uint256 principalOfActiveOwedM_,
        uint256 minterCollateral_
    ) external {
        principalOfActiveOwedM_ = bound(principalOfActiveOwedM_, ONE, type(uint112).max / 6);
        minterCollateral_ = bound(minterCollateral_, principalOfActiveOwedM_, type(uint112).max / 2);
        uint256 lastUpdateTimestamp = vm.getBlockTimestamp();

        _minterGateway.setCollateralOf(_minter1, minterCollateral_);
        _minterGateway.setUpdateTimestampOf(_minter1, lastUpdateTimestamp);
        _minterGateway.setRawOwedMOf(_minter1, principalOfActiveOwedM_);

        vm.warp(lastUpdateTimestamp + _updateCollateralInterval - 10);

        uint256 missedCollateralUpdatesPenalty_ = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(missedCollateralUpdatesPenalty_, 0);

        vm.warp(lastUpdateTimestamp + _updateCollateralInterval + 10);

        missedCollateralUpdatesPenalty_ = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);

        uint240 penaltyPrincipal_ = uint240((principalOfActiveOwedM_ * _penaltyRate) / ONE);
        uint240 expectedMissedCollateralUpdatesPenalty_ = _getPresentAmountRoundedUp(
            uint112(penaltyPrincipal_),
            _minterGateway.currentIndex()
        );

        assertEq(missedCollateralUpdatesPenalty_, expectedMissedCollateralUpdatesPenalty_);

        // 1 is added to overflow `newPrincipalOfTotalActiveOwedM_`
        uint256 principalOfTotalActiveOwedM_ = type(uint112).max - penaltyPrincipal_ + 1;
        _minterGateway.setPrincipalOfTotalActiveOwedM(principalOfTotalActiveOwedM_);

        uint256[] memory retrievalIds_ = new uint256[](0);

        address[] memory validators_ = new address[](1);
        validators_[0] = _validator1;

        uint256 signatureTimestamp_ = vm.getBlockTimestamp();

        uint256[] memory timestamps_ = new uint256[](1);
        timestamps_[0] = signatureTimestamp_;

        bytes[] memory signatures_ = new bytes[](1);
        signatures_[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            minterCollateral_,
            retrievalIds_,
            bytes32(0),
            signatureTimestamp_,
            _validator1Pk
        );

        uint256 minterPrincipalOfActiveOwedMBefore_ = _minterGateway.principalOfActiveOwedMOf(_minter1);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(
            minterCollateral_,
            retrievalIds_,
            bytes32(0),
            validators_,
            timestamps_,
            signatures_
        );

        // Despite overflowing, `principalOfTotalActiveOwedM` is capped and equal to type(uint112).max
        assertEq(_minterGateway.principalOfTotalActiveOwedM(), type(uint112).max);

        // 1 wei difference because of rounding
        assertApproxEqAbs(
            _minterGateway.principalOfActiveOwedMOf(_minter1),
            minterPrincipalOfActiveOwedMBefore_ + penaltyPrincipal_,
            1
        );
    }

    function test_getPenaltyForMissedCollateralUpdates_noMissedIntervals() external {
        uint256 collateral = 100e18;
        uint256 timestamp = vm.getBlockTimestamp();

        _minterGateway.setCollateralOf(_minter1, collateral);
        _minterGateway.setUpdateTimestampOf(_minter1, timestamp);
        _minterGateway.setRawOwedMOf(_minter1, 60e18);

        vm.warp(timestamp + _updateCollateralInterval - 10);

        uint256 penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, 0);
    }

    function test_getPenaltyForMissedCollateralUpdates_oneMissedInterval() external {
        uint256 collateral = 100e18;
        uint256 timestamp = vm.getBlockTimestamp();

        _minterGateway.setCollateralOf(_minter1, collateral);
        _minterGateway.setUpdateTimestampOf(_minter1, timestamp);
        _minterGateway.setRawOwedMOf(_minter1, 60e18);

        vm.warp(timestamp + _updateCollateralInterval + 10);

        uint256 penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, (_minterGateway.activeOwedMOf(_minter1) * _penaltyRate) / ONE);
    }

    function test_getPenaltyForMissedCollateralUpdates_threeMissedInterval() external {
        uint256 collateral = 100e18;
        uint256 timestamp = vm.getBlockTimestamp();

        _minterGateway.setCollateralOf(_minter1, collateral);
        _minterGateway.setUpdateTimestampOf(_minter1, timestamp);
        _minterGateway.setRawOwedMOf(_minter1, 60e18);

        vm.warp(timestamp + (3 * _updateCollateralInterval) + 10);

        uint256 penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, (3 * (_minterGateway.activeOwedMOf(_minter1) * _penaltyRate)) / ONE);
    }

    function test_getPenaltyForMissedCollateralUpdates_moreMissedIntervalsDueToReducedInterval() external {
        uint256 collateral = 100e18;
        uint256 timestamp = vm.getBlockTimestamp();

        _minterGateway.setCollateralOf(_minter1, collateral);
        _minterGateway.setUpdateTimestampOf(_minter1, timestamp);
        _minterGateway.setRawOwedMOf(_minter1, 60e18);

        // Change update collateral interval, more frequent updates are required
        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, _updateCollateralInterval / 4);

        vm.warp(timestamp + (3 * _updateCollateralInterval) + 10);

        uint256 penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);

        // Minter was expected to update within the previous interval. After that deadline, the new interval is imposed,
        // so instead of 2 more missed intervals, since the interval was divided by 4, each of those 2 missed intervals
        // is actually 4 missed intervals. Therefore, 9 missed intervals in total is expected.
        assertEq(penalty, (12 * (_minterGateway.activeOwedMOf(_minter1) * _penaltyRate)) / ONE);
    }

    function test_getPenaltyForMissedCollateralUpdates_updateCollateralIntervalHasChanged() external {
        uint256 collateral = 100e18;
        uint256 timestamp = vm.getBlockTimestamp();

        _minterGateway.setCollateralOf(_minter1, collateral);
        _minterGateway.setUpdateTimestampOf(_minter1, timestamp);
        _minterGateway.setRawOwedMOf(_minter1, 60e18);

        vm.warp(timestamp + _updateCollateralInterval - 10);

        uint256 penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, 0);

        // Change update collateral interval, more frequent updates are required
        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, _updateCollateralInterval / 2);

        vm.warp(timestamp + _updateCollateralInterval + 10);

        // Penalized for first `_updateCollateralInterval` interval
        penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, (2 * _minterGateway.activeOwedMOf(_minter1) * _penaltyRate) / ONE);

        vm.warp(vm.getBlockTimestamp() + _updateCollateralInterval + 10);

        // Penalized for 2 new `_updateCollateralInterval` interval = 3 penalty intervals
        penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, (4 * _minterGateway.activeOwedMOf(_minter1) * _penaltyRate) / ONE);
    }

    /* ============ activateMinter ============ */
    function test_activateMinter() external {
        _minterGateway.setIsActive(_minter1, false);
        assertEq(_minterGateway.isActiveMinter(_minter1), false);

        _ttgRegistrar.addToList(TTGRegistrarReader.MINTERS_LIST, _minter1);

        vm.expectEmit();
        emit IMinterGateway.MinterActivated(_minter1, _alice);

        vm.prank(_alice);
        _minterGateway.activateMinter(_minter1);

        assertEq(_minterGateway.isActiveMinter(_minter1), true);
    }

    function test_activateMinter_notApprovedMinter() external {
        vm.expectRevert(IMinterGateway.NotApprovedMinter.selector);
        vm.prank(_alice);
        _minterGateway.activateMinter(makeAddr("notApprovedMinter"));
    }

    function test_activateMinter_deactivatedMinter() external {
        _minterGateway.setIsDeactivated(_minter1, true);

        vm.expectRevert(IMinterGateway.DeactivatedMinter.selector);
        vm.prank(_alice);
        _minterGateway.activateMinter(_minter1);
    }

    /* ============ deactivateMinter ============ */
    function test_deactivateMinter() external {
        _ttgRegistrar.removeFromList(TTGRegistrarReader.MINTERS_LIST, _minter1);

        _minterGateway.setCollateralOf(_minter1, 2_000_000);
        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp() - 4 hours);
        _minterGateway.setUnfrozenTimeOf(_minter1, vm.getBlockTimestamp() + 4 days);
        _minterGateway.setRawOwedMOf(_minter1, 1_000_000);
        _minterGateway.setTotalPendingRetrievalsOf(_minter1, 500_000);
        _minterGateway.setPenalizedUntilOf(_minter1, vm.getBlockTimestamp() - 4 hours);
        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp() - _updateCollateralInterval + 10);

        _minterGateway.setPrincipalOfTotalActiveOwedM(1_000_000);
        _minterGateway.setLatestIndex(
            ContinuousIndexingMath.EXP_SCALED_ONE + ContinuousIndexingMath.EXP_SCALED_ONE / 10
        );

        vm.expectEmit();
        emit IMinterGateway.MinterDeactivated(_minter1, 1_100_000, _alice);

        vm.prank(_alice);
        uint240 inactiveOwedM = _minterGateway.deactivateMinter(_minter1);

        assertEq(inactiveOwedM, 1_100_000);

        assertEq(_minterGateway.internalCollateralOf(_minter1), 0);
        assertEq(_minterGateway.collateralUpdateTimestampOf(_minter1), 0);
        assertEq(_minterGateway.frozenUntilOf(_minter1), 0);
        assertEq(_minterGateway.isActiveMinter(_minter1), false);
        assertEq(_minterGateway.isDeactivatedMinter(_minter1), true);
        assertEq(_minterGateway.principalOfActiveOwedMOf(_minter1), 0);
        assertEq(_minterGateway.inactiveOwedMOf(_minter1), 1_100_000);
        assertEq(_minterGateway.totalPendingCollateralRetrievalOf(_minter1), 0);
        assertEq(_minterGateway.penalizedUntilOf(_minter1), 0);

        assertEq(_minterGateway.rawOwedMOf(_minter1), 1_100_000);
        assertEq(_minterGateway.totalInactiveOwedM(), 1_100_000);
    }

    function test_deactivateMinter_imposePenaltyForExpiredCollateralValue() external {
        uint256 mintAmount = 1000000e18;

        _minterGateway.setCollateralOf(_minter1, mintAmount * 2);
        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp() - _updateCollateralInterval);
        _minterGateway.setRawOwedMOf(_minter1, mintAmount);
        _minterGateway.setPrincipalOfTotalActiveOwedM(mintAmount);

        uint240 activeOwedM = _minterGateway.activeOwedMOf(_minter1);
        uint240 penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);

        _ttgRegistrar.removeFromList(TTGRegistrarReader.MINTERS_LIST, _minter1);

        vm.expectEmit();
        emit IMinterGateway.MinterDeactivated(_minter1, activeOwedM + penalty, _alice);

        vm.prank(_alice);
        _minterGateway.deactivateMinter(_minter1);
    }

    function test_deactivateMinter_stillApprovedMinter() external {
        vm.expectRevert(IMinterGateway.StillApprovedMinter.selector);
        vm.prank(_alice);
        _minterGateway.deactivateMinter(_minter1);
    }

    function test_deactivateMinter_alreadyInactiveMinter() external {
        vm.expectRevert(IMinterGateway.InactiveMinter.selector);
        vm.prank(_alice);
        _minterGateway.deactivateMinter(makeAddr("someInactiveMinter"));
    }

    /* ============ proposeRetrieval ============ */
    function test_proposeRetrieval() external {
        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD, bytes32(uint256(2)));

        uint240 collateral = 100;
        uint256[] memory retrievalIds = new uint256[](0);
        uint40 signatureTimestamp1 = uint40(vm.getBlockTimestamp());
        uint40 signatureTimestamp2 = signatureTimestamp1 - 10;

        address[] memory validators = new address[](2);
        validators[0] = _validator2;
        validators[1] = _validator1;

        uint256[] memory timestamps = new uint256[](2);
        timestamps[1] = signatureTimestamp1;
        timestamps[0] = signatureTimestamp2;

        bytes[] memory signatures = new bytes[](2);

        signatures[1] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp1,
            _validator1Pk
        );

        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp2,
            _validator2Pk
        );

        vm.expectEmit();
        emit IMinterGateway.CollateralUpdated(_minter1, collateral, 0, bytes32(0), signatureTimestamp2);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        uint48 expectedRetrievalId = _minterGateway.retrievalNonce() + 1;

        vm.expectEmit();
        emit IMinterGateway.RetrievalCreated(expectedRetrievalId, _minter1, collateral);

        vm.prank(_minter1);
        uint256 retrievalId = _minterGateway.proposeRetrieval(collateral);

        assertEq(retrievalId, expectedRetrievalId);
        assertEq(_minterGateway.totalPendingCollateralRetrievalOf(_minter1), collateral);
        assertEq(_minterGateway.pendingCollateralRetrievalOf(_minter1, retrievalId), collateral);
        assertEq(_minterGateway.maxAllowedActiveOwedMOf(_minter1), 0);

        vm.warp(vm.getBlockTimestamp() + 200);

        signatureTimestamp1 = uint40(vm.getBlockTimestamp()) - 100;
        signatureTimestamp2 = uint40(vm.getBlockTimestamp()) - 50;

        uint256[] memory newRetrievalIds = new uint256[](1);

        newRetrievalIds[0] = retrievalId;

        timestamps[0] = signatureTimestamp1;
        timestamps[1] = signatureTimestamp2;

        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral / 2,
            newRetrievalIds,
            bytes32(0),
            signatureTimestamp1,
            _validator2Pk
        );

        signatures[1] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral / 2,
            newRetrievalIds,
            bytes32(0),
            signatureTimestamp2,
            _validator1Pk
        );

        vm.expectEmit();
        emit IMinterGateway.CollateralUpdated(_minter1, collateral / 2, collateral, bytes32(0), signatureTimestamp1);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(
            collateral / 2,
            newRetrievalIds,
            bytes32(0),
            validators,
            timestamps,
            signatures
        );

        assertEq(_minterGateway.totalPendingCollateralRetrievalOf(_minter1), 0);
        assertEq(_minterGateway.pendingCollateralRetrievalOf(_minter1, retrievalId), 0);
        assertEq(_minterGateway.maxAllowedActiveOwedMOf(_minter1), ((collateral / 2) * _mintRatio) / ONE);
    }

    function testFuzz_proposeRetrieval(uint256 minterCollateral_) external {
        minterCollateral_ = bound(minterCollateral_, 1, type(uint112).max);

        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD, bytes32(uint256(2)));

        uint256[] memory retrievalIds_ = new uint256[](0);
        uint40 signatureTimestamp1_ = uint40(vm.getBlockTimestamp());
        uint40 signatureTimestamp2_ = signatureTimestamp1_ - 10;

        address[] memory validators_ = new address[](2);
        validators_[0] = _validator2;
        validators_[1] = _validator1;

        uint256[] memory timestamps_ = new uint256[](2);
        timestamps_[1] = signatureTimestamp1_;
        timestamps_[0] = signatureTimestamp2_;

        bytes[] memory signatures_ = new bytes[](2);

        signatures_[1] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            minterCollateral_,
            retrievalIds_,
            bytes32(0),
            signatureTimestamp1_,
            _validator1Pk
        );

        signatures_[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            minterCollateral_,
            retrievalIds_,
            bytes32(0),
            signatureTimestamp2_,
            _validator2Pk
        );

        vm.expectEmit();
        emit IMinterGateway.CollateralUpdated(
            _minter1,
            uint240(minterCollateral_),
            0,
            bytes32(0),
            signatureTimestamp2_
        );

        vm.prank(_minter1);
        _minterGateway.updateCollateral(
            minterCollateral_,
            retrievalIds_,
            bytes32(0),
            validators_,
            timestamps_,
            signatures_
        );

        uint48 expectedRetrievalId_ = 1;

        vm.expectEmit();
        emit IMinterGateway.RetrievalCreated(expectedRetrievalId_, _minter1, uint240(minterCollateral_));

        vm.prank(_minter1);
        uint256 retrievalId_ = _minterGateway.proposeRetrieval(minterCollateral_);

        assertEq(retrievalId_, expectedRetrievalId_);
        assertEq(_minterGateway.totalPendingCollateralRetrievalOf(_minter1), minterCollateral_);
        assertEq(_minterGateway.pendingCollateralRetrievalOf(_minter1, retrievalId_), minterCollateral_);
        assertEq(_minterGateway.maxAllowedActiveOwedMOf(_minter1), 0);

        vm.warp(vm.getBlockTimestamp() + 200);

        signatureTimestamp1_ = uint40(vm.getBlockTimestamp()) - 100;
        signatureTimestamp2_ = uint40(vm.getBlockTimestamp()) - 50;

        uint256[] memory newRetrievalIds_ = new uint256[](1);

        newRetrievalIds_[0] = retrievalId_;

        timestamps_[0] = signatureTimestamp1_;
        timestamps_[1] = signatureTimestamp2_;

        signatures_[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            minterCollateral_ / 2,
            newRetrievalIds_,
            bytes32(0),
            signatureTimestamp1_,
            _validator2Pk
        );

        signatures_[1] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            minterCollateral_ / 2,
            newRetrievalIds_,
            bytes32(0),
            signatureTimestamp2_,
            _validator1Pk
        );

        vm.expectEmit();
        emit IMinterGateway.CollateralUpdated(
            _minter1,
            uint240(minterCollateral_ / 2),
            uint240(minterCollateral_),
            bytes32(0),
            signatureTimestamp1_
        );

        vm.prank(_minter1);
        _minterGateway.updateCollateral(
            minterCollateral_ / 2,
            newRetrievalIds_,
            bytes32(0),
            validators_,
            timestamps_,
            signatures_
        );

        assertEq(_minterGateway.totalPendingCollateralRetrievalOf(_minter1), 0);
        assertEq(_minterGateway.pendingCollateralRetrievalOf(_minter1, retrievalId_), 0);
        assertEq(_minterGateway.maxAllowedActiveOwedMOf(_minter1), ((minterCollateral_ / 2) * _mintRatio) / ONE);
    }

    function test_proposeRetrieval_zeroRetrievalAmount() external {
        vm.expectRevert(IMinterGateway.ZeroRetrievalAmount.selector);
        vm.prank(_minter1);
        _minterGateway.proposeRetrieval(0);
    }

    function test_proposeRetrieval_inactiveMinter() external {
        _minterGateway.setIsActive(_minter1, false);

        vm.expectRevert(IMinterGateway.InactiveMinter.selector);

        vm.prank(_alice);
        _minterGateway.proposeRetrieval(100);
    }

    function test_proposeRetrieval_undercollateralized() external {
        uint256 collateral = 100e18;

        _minterGateway.setCollateralOf(_minter1, collateral);
        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp());
        _minterGateway.setRawOwedMOf(_minter1, (collateral * _mintRatio) / ONE);

        uint256 retrievalAmount = 10e18;
        uint256 expectedMaxAllowedOwedM = ((collateral - retrievalAmount) * _mintRatio) / ONE;

        vm.expectRevert(
            abi.encodeWithSelector(
                IMinterGateway.Undercollateralized.selector,
                _minterGateway.activeOwedMOf(_minter1),
                expectedMaxAllowedOwedM
            )
        );

        vm.prank(_minter1);
        _minterGateway.proposeRetrieval(retrievalAmount);
    }

    function test_proposeRetrieval_RetrievalsExceedCollateral() external {
        uint256 collateral = 100e18;

        _minterGateway.setCollateralOf(_minter1, collateral);
        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp());
        _minterGateway.setTotalPendingRetrievalsOf(_minter1, collateral);

        uint256 retrievalAmount = 10e18;
        vm.expectRevert(
            abi.encodeWithSelector(
                IMinterGateway.RetrievalsExceedCollateral.selector,
                collateral + retrievalAmount,
                collateral
            )
        );

        vm.prank(_minter1);
        _minterGateway.proposeRetrieval(retrievalAmount);
    }

    function test_proposeRetrieval_multipleProposals() external {
        uint256 collateral = 100e18;
        uint256 amount = 60e18;
        uint256 timestamp = vm.getBlockTimestamp();

        _minterGateway.setCollateralOf(_minter1, collateral);
        _minterGateway.setUpdateTimestampOf(_minter1, timestamp);
        _minterGateway.setRawOwedMOf(_minter1, amount);
        _minterGateway.setPrincipalOfTotalActiveOwedM(amount);

        uint240 retrievalAmount = 10e18;
        uint48 expectedRetrievalId = _minterGateway.retrievalNonce() + 1;

        // First retrieval proposal
        vm.expectEmit();
        emit IMinterGateway.RetrievalCreated(expectedRetrievalId, _minter1, retrievalAmount);

        vm.prank(_minter1);
        uint256 retrievalId = _minterGateway.proposeRetrieval(retrievalAmount);

        assertEq(retrievalId, expectedRetrievalId);
        assertEq(_minterGateway.totalPendingCollateralRetrievalOf(_minter1), retrievalAmount);
        assertEq(_minterGateway.pendingCollateralRetrievalOf(_minter1, retrievalId), retrievalAmount);

        // Second retrieval proposal
        vm.prank(_minter1);
        uint256 newRetrievalId = _minterGateway.proposeRetrieval(retrievalAmount);

        assertEq(_minterGateway.totalPendingCollateralRetrievalOf(_minter1), retrievalAmount * 2);
        assertEq(_minterGateway.pendingCollateralRetrievalOf(_minter1, newRetrievalId), retrievalAmount);

        uint256[] memory retrievalIds = new uint256[](1);
        retrievalIds[0] = newRetrievalId;

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = timestamp + 1;

        bytes[] memory signatures = new bytes[](1);

        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            timestamp + 1,
            _validator1Pk
        );

        vm.warp(timestamp + 1);

        // Close first retrieval proposal
        vm.prank(_minter1);
        _minterGateway.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        assertEq(_minterGateway.totalPendingCollateralRetrievalOf(_minter1), retrievalAmount);
        assertEq(_minterGateway.pendingCollateralRetrievalOf(_minter1, newRetrievalId), 0);

        retrievalIds[0] = retrievalId;
        validators[0] = _validator1;

        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            timestamp + 2,
            _validator1Pk
        );

        timestamps[0] = timestamp + 2;

        vm.warp(timestamp + 2);

        // Close second retrieval request
        vm.prank(_minter1);
        _minterGateway.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        assertEq(_minterGateway.totalPendingCollateralRetrievalOf(_minter1), 0);
        assertEq(_minterGateway.pendingCollateralRetrievalOf(_minter1, retrievalId), 0);
    }

    function test_proposeRetrieval_deactivateMinter() external {
        uint256 collateral = 100e18;
        uint256 amount = 60e18;
        uint256 timestamp = vm.getBlockTimestamp();

        _minterGateway.setCollateralOf(_minter1, collateral);
        _minterGateway.setUpdateTimestampOf(_minter1, timestamp);
        _minterGateway.setRawOwedMOf(_minter1, amount);
        _minterGateway.setPrincipalOfTotalActiveOwedM(amount);

        uint240 retrievalAmount = 10e18;

        vm.prank(_minter1);
        uint256 retrievalId = _minterGateway.proposeRetrieval(retrievalAmount);

        assertEq(_minterGateway.totalPendingCollateralRetrievalOf(_minter1), retrievalAmount);
        assertEq(_minterGateway.pendingCollateralRetrievalOf(_minter1, retrievalId), retrievalAmount);

        // deactivate minter
        _ttgRegistrar.removeFromList(TTGRegistrarReader.MINTERS_LIST, _minter1);

        vm.prank(_alice);
        _minterGateway.deactivateMinter(_minter1);

        assertEq(_minterGateway.totalPendingCollateralRetrievalOf(_minter1), 0);
        assertEq(_minterGateway.pendingCollateralRetrievalOf(_minter1, retrievalId), 0);
    }

    function testFuzz_proposeRetrieval_multipleProposals(
        uint256 minterCollateral_,
        uint256 principalOfActiveOwedM_,
        uint256 retrievalAmount_
    ) external {
        principalOfActiveOwedM_ = bound(principalOfActiveOwedM_, ONE, type(uint112).max / 6);

        // @dev prevents undercollateralization
        minterCollateral_ = bound(minterCollateral_, principalOfActiveOwedM_ * 3, type(uint112).max);
        retrievalAmount_ = bound(retrievalAmount_, 1, principalOfActiveOwedM_ / 2);
        uint256 timestamp_ = vm.getBlockTimestamp();

        _minterGateway.setCollateralOf(_minter1, minterCollateral_);
        _minterGateway.setUpdateTimestampOf(_minter1, timestamp_);
        _minterGateway.setRawOwedMOf(_minter1, principalOfActiveOwedM_);
        _minterGateway.setPrincipalOfTotalActiveOwedM(principalOfActiveOwedM_);

        uint48 expectedRetrievalId_ = 1;

        // First retrieval proposal
        vm.expectEmit();
        emit IMinterGateway.RetrievalCreated(expectedRetrievalId_, _minter1, uint240(retrievalAmount_));

        vm.prank(_minter1);
        uint256 retrievalId_ = _minterGateway.proposeRetrieval(retrievalAmount_);

        assertEq(retrievalId_, expectedRetrievalId_);
        assertEq(_minterGateway.totalPendingCollateralRetrievalOf(_minter1), retrievalAmount_);
        assertEq(_minterGateway.pendingCollateralRetrievalOf(_minter1, retrievalId_), retrievalAmount_);

        // Second retrieval proposal
        vm.prank(_minter1);
        uint256 newRetrievalId_ = _minterGateway.proposeRetrieval(retrievalAmount_);

        assertEq(_minterGateway.totalPendingCollateralRetrievalOf(_minter1), retrievalAmount_ * 2);
        assertEq(_minterGateway.pendingCollateralRetrievalOf(_minter1, newRetrievalId_), retrievalAmount_);

        uint256[] memory retrievalIds_ = new uint256[](1);
        retrievalIds_[0] = newRetrievalId_;

        address[] memory validators_ = new address[](1);
        validators_[0] = _validator1;

        uint256[] memory timestamps_ = new uint256[](1);
        timestamps_[0] = timestamp_ + 1;

        bytes[] memory signatures_ = new bytes[](1);

        signatures_[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            minterCollateral_,
            retrievalIds_,
            bytes32(0),
            timestamp_ + 1,
            _validator1Pk
        );

        vm.warp(timestamp_ + 1);

        // Close first retrieval proposal
        vm.prank(_minter1);
        _minterGateway.updateCollateral(
            minterCollateral_,
            retrievalIds_,
            bytes32(0),
            validators_,
            timestamps_,
            signatures_
        );

        assertEq(_minterGateway.totalPendingCollateralRetrievalOf(_minter1), retrievalAmount_);
        assertEq(_minterGateway.pendingCollateralRetrievalOf(_minter1, newRetrievalId_), 0);

        retrievalIds_[0] = retrievalId_;
        validators_[0] = _validator1;

        signatures_[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            minterCollateral_,
            retrievalIds_,
            bytes32(0),
            timestamp_ + 2,
            _validator1Pk
        );

        timestamps_[0] = timestamp_ + 2;

        vm.warp(timestamp_ + 2);

        // Close second retrieval request
        vm.prank(_minter1);
        _minterGateway.updateCollateral(
            minterCollateral_,
            retrievalIds_,
            bytes32(0),
            validators_,
            timestamps_,
            signatures_
        );

        assertEq(_minterGateway.totalPendingCollateralRetrievalOf(_minter1), 0);
        assertEq(_minterGateway.pendingCollateralRetrievalOf(_minter1, retrievalId_), 0);
    }

    function test_updateCollateral_zeroTimestamp() external {
        uint256[] memory retrievalIds = new uint256[](0);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = 0;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            100,
            retrievalIds,
            bytes32(0),
            0,
            _validator1Pk
        );

        vm.expectRevert(IMinterGateway.ZeroTimestamp.selector);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(100, retrievalIds, bytes32(0), validators, timestamps, signatures);
    }

    function test_updateCollateral_futureTimestamp() external {
        uint256[] memory retrievalIds = new uint256[](0);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = vm.getBlockTimestamp() + 100;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            100,
            retrievalIds,
            bytes32(0),
            vm.getBlockTimestamp() + 100,
            _validator1Pk
        );

        vm.expectRevert(IMinterGateway.FutureTimestamp.selector);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(100, retrievalIds, bytes32(0), validators, timestamps, signatures);
    }

    function test_updateCollateral_zeroThreshold() external {
        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD, bytes32(uint256(0)));

        uint256[] memory retrievalIds = new uint256[](0);
        address[] memory validators = new address[](0);
        uint256[] memory timestamps = new uint256[](0);
        bytes[] memory signatures = new bytes[](0);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(100, retrievalIds, bytes32(0), validators, timestamps, signatures);

        assertEq(_minterGateway.collateralOf(_minter1), 100);
        assertEq(_minterGateway.collateralUpdateTimestampOf(_minter1), vm.getBlockTimestamp());
    }

    function test_updateCollateral_someSignaturesAreInvalid() external {
        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD, bytes32(uint256(1)));

        uint256[] memory retrievalIds = new uint256[](0);

        (address validator3, uint256 validator3Pk) = makeAddrAndKey("validator3");
        address[] memory validators = new address[](3);
        validators[0] = _validator1;
        validators[1] = _validator2;
        validators[2] = validator3;

        uint256[] memory timestamps = new uint256[](3);
        timestamps[0] = vm.getBlockTimestamp();
        timestamps[1] = vm.getBlockTimestamp();
        timestamps[2] = vm.getBlockTimestamp();

        bytes[] memory signatures = new bytes[](3);
        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            100,
            retrievalIds,
            bytes32(0),
            vm.getBlockTimestamp(),
            _validator1Pk
        ); // valid signature

        signatures[1] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            200,
            retrievalIds,
            bytes32(0),
            vm.getBlockTimestamp(),
            _validator2Pk
        );

        signatures[2] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            100,
            retrievalIds,
            bytes32(0),
            vm.getBlockTimestamp(),
            validator3Pk
        );

        vm.prank(_minter1);
        _minterGateway.updateCollateral(100, retrievalIds, bytes32(0), validators, timestamps, signatures);

        assertEq(_minterGateway.collateralOf(_minter1), 100);
        assertEq(_minterGateway.collateralUpdateTimestampOf(_minter1), vm.getBlockTimestamp());
    }

    /* ============ Getters ============ */
    function test_emptyRateModel() external {
        _ttgRegistrar.updateConfig(TTGRegistrarReader.MINTER_RATE_MODEL, address(0));

        assertEq(_minterGateway.rate(), 0);
    }

    function test_principalOfTotalActiveOwedM() external {
        _minterGateway.setPrincipalOfTotalActiveOwedM(1_000_000);
        assertEq(_minterGateway.principalOfTotalActiveOwedM(), 1_000_000);
    }

    function test_totalActiveOwedM() external {
        _minterGateway.setPrincipalOfTotalActiveOwedM(1_000_000);
        assertEq(_minterGateway.totalActiveOwedM(), 1_000_000);

        _minterGateway.setLatestIndex(
            ContinuousIndexingMath.EXP_SCALED_ONE + ContinuousIndexingMath.EXP_SCALED_ONE / 10
        );

        assertEq(_minterGateway.totalActiveOwedM(), 1_100_000);
    }

    function test_totalInactiveOwedM() external {
        _minterGateway.setTotalInactiveOwedM(1_000_000);
        assertEq(_minterGateway.totalInactiveOwedM(), 1_000_000);
    }

    function test_totalOwedM() external {
        _minterGateway.setTotalInactiveOwedM(500_000);
        _minterGateway.setPrincipalOfTotalActiveOwedM(1_000_000);
        assertEq(_minterGateway.totalOwedM(), 1_500_000);

        _minterGateway.setLatestIndex(
            ContinuousIndexingMath.EXP_SCALED_ONE + ContinuousIndexingMath.EXP_SCALED_ONE / 10
        );

        assertEq(_minterGateway.totalOwedM(), 1_600_000);
    }

    function test_activeOwedMOf() external {
        _minterGateway.setRawOwedMOf(_minter1, 1_000_000);
        assertEq(_minterGateway.activeOwedMOf(_minter1), 1_000_000);

        _minterGateway.setLatestIndex(
            ContinuousIndexingMath.EXP_SCALED_ONE + ContinuousIndexingMath.EXP_SCALED_ONE / 10
        );

        assertEq(_minterGateway.activeOwedMOf(_minter1), 1_100_000);
    }

    function test_activeOwedM_indexing() external {
        uint256 timestamp = vm.getBlockTimestamp();
        uint128 initialIndex = _minterGateway.latestIndex();
        _minterGateway.setRawOwedMOf(_minter1, 1000000e6);

        vm.warp(timestamp + 1);

        uint128 indexAfter1Second = uint128(
            ContinuousIndexingMath.multiplyIndicesUp(
                initialIndex,
                ContinuousIndexingMath.getContinuousIndex(
                    ContinuousIndexingMath.convertFromBasisPoints(uint32(_minterRate)),
                    1
                )
            )
        );

        uint240 expectedResult = ContinuousIndexingMath.multiplyUp(1000000e6, indexAfter1Second);

        assertEq(_minterGateway.activeOwedMOf(_minter1), expectedResult);

        vm.warp(timestamp + 31_536_000);

        uint128 indexAfter1Year = uint128(
            ContinuousIndexingMath.multiplyIndicesUp(
                initialIndex,
                ContinuousIndexingMath.getContinuousIndex(
                    ContinuousIndexingMath.convertFromBasisPoints(uint32(_minterRate)),
                    31_536_000
                )
            )
        );

        expectedResult = ContinuousIndexingMath.multiplyUp(1000000e6, indexAfter1Year);

        assertEq(_minterGateway.activeOwedMOf(_minter1), expectedResult);
    }

    function test_inactiveOwedMOf() external {
        _minterGateway.setRawOwedMOf(_minter1, 1_000_000);
        _minterGateway.setIsActive(_minter1, false);

        assertEq(_minterGateway.inactiveOwedMOf(_minter1), 1_000_000);
    }

    function test_getMissedCollateralUpdateParameters_zeroNewUpdateInterval() external {
        (uint40 missedIntervals_, uint40 missedUntil_) = _minterGateway.getMissedCollateralUpdateParameters({
            lastUpdateTimestamp_: uint40(vm.getBlockTimestamp()) - 48 hours, // This does not matter
            lastPenalizedUntil_: uint40(vm.getBlockTimestamp()) - 24 hours, // This does not matter
            updateInterval_: 0
        });

        assertEq(missedIntervals_, 0);
        assertEq(missedUntil_, uint40(vm.getBlockTimestamp()) - 24 hours);
    }

    function test_getMissedCollateralUpdateParameters_newMinter() external {
        (uint40 missedIntervals_, uint40 missedUntil_) = _minterGateway.getMissedCollateralUpdateParameters({
            lastUpdateTimestamp_: 0,
            lastPenalizedUntil_: 0,
            updateInterval_: 24 hours
        });

        assertEq(missedIntervals_, 0);
        assertEq(missedUntil_, 0);
    }

    /* ============ TTG Parameters ============ */
    function test_readTTGParameters() external {
        address peter = makeAddr("peter");

        assertEq(_minterGateway.isMinterApproved(peter), false);
        _ttgRegistrar.addToList(TTGRegistrarReader.MINTERS_LIST, peter);
        assertEq(_minterGateway.isMinterApproved(peter), true);

        assertEq(_minterGateway.isValidatorApprovedByTTG(peter), false);
        _ttgRegistrar.addToList(TTGRegistrarReader.VALIDATORS_LIST, peter);
        assertEq(_minterGateway.isValidatorApprovedByTTG(peter), true);

        _ttgRegistrar.addToList(TTGRegistrarReader.VALIDATORS_LIST, _validator1);

        _ttgRegistrar.updateConfig(TTGRegistrarReader.MINT_RATIO, 8000);
        assertEq(_minterGateway.mintRatio(), 8000);

        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD, 3);
        assertEq(_minterGateway.updateCollateralValidatorThreshold(), 3);

        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 12 hours);
        assertEq(_minterGateway.updateCollateralInterval(), 12 hours);

        _ttgRegistrar.updateConfig(TTGRegistrarReader.MINTER_FREEZE_TIME, 2 hours);
        assertEq(_minterGateway.minterFreezeTime(), 2 hours);

        _ttgRegistrar.updateConfig(TTGRegistrarReader.MINT_DELAY, 3 hours);
        assertEq(_minterGateway.mintDelay(), 3 hours);

        _ttgRegistrar.updateConfig(TTGRegistrarReader.MINT_TTL, 4 hours);
        assertEq(_minterGateway.mintTTL(), 4 hours);

        MockRateModel minterRateModel = new MockRateModel();
        _ttgRegistrar.updateConfig(TTGRegistrarReader.MINTER_RATE_MODEL, address(minterRateModel));
        assertEq(_minterGateway.rateModel(), address(minterRateModel));

        _ttgRegistrar.updateConfig(TTGRegistrarReader.PENALTY_RATE, 100);
        assertEq(_minterGateway.penaltyRate(), 100);
    }

    function test_collateralExpiryTimestampOf() external {
        // collateralExpiryTimestampOf should always be equal to updateTimestampOf + updateCollateralInterval
        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp());
        assertEq(
            _minterGateway.collateralExpiryTimestampOf(_minter1),
            vm.getBlockTimestamp() + _updateCollateralInterval
        );

        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 1_234);
        assertEq(_minterGateway.collateralExpiryTimestampOf(_minter1), vm.getBlockTimestamp() + 1234);

        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp() - 10_000);
        assertEq(_minterGateway.collateralExpiryTimestampOf(_minter1), vm.getBlockTimestamp() - 10_000 + 1_234);
    }

    function test_collateralPenaltyDeadlineOf() external {
        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp());
        _minterGateway.setPenalizedUntilOf(_minter1, vm.getBlockTimestamp() - 10);
        assertEq(
            _minterGateway.collateralPenaltyDeadlineOf(_minter1),
            vm.getBlockTimestamp() + _updateCollateralInterval
        );

        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp() - 10);
        _minterGateway.setPenalizedUntilOf(_minter1, vm.getBlockTimestamp());
        assertEq(
            _minterGateway.collateralPenaltyDeadlineOf(_minter1),
            vm.getBlockTimestamp() + _updateCollateralInterval
        );

        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 1_234);

        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp());
        _minterGateway.setPenalizedUntilOf(_minter1, vm.getBlockTimestamp() - 10);
        assertEq(_minterGateway.collateralPenaltyDeadlineOf(_minter1), vm.getBlockTimestamp() + 1234);

        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp() - 10);
        _minterGateway.setPenalizedUntilOf(_minter1, vm.getBlockTimestamp());
        assertEq(_minterGateway.collateralPenaltyDeadlineOf(_minter1), vm.getBlockTimestamp() + 1234);

        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp() - 10_000);
        _minterGateway.setPenalizedUntilOf(_minter1, vm.getBlockTimestamp() - 10_010);
        assertEq(_minterGateway.collateralPenaltyDeadlineOf(_minter1), vm.getBlockTimestamp() - 10_000 + 9 * (1234));

        _minterGateway.setUpdateTimestampOf(_minter1, vm.getBlockTimestamp() - 10_010);
        _minterGateway.setPenalizedUntilOf(_minter1, vm.getBlockTimestamp() - 10_000);
        assertEq(_minterGateway.collateralPenaltyDeadlineOf(_minter1), vm.getBlockTimestamp() - 10_000 + 9 * (1234));
    }

    /* ============ M Token ============ */
    function test_mToken_addEarningAmount_overflow() external {
        address deployer_ = address(this);
        MTokenHarness mToken_ = new MTokenHarness(
            address(_ttgRegistrar),
            ContractHelper.getContractFrom(deployer_, vm.getNonce(deployer_) + 1)
        );

        MinterGatewayHarness minterGateway_ = new MinterGatewayHarness(address(_ttgRegistrar), address(mToken_));

        _ttgRegistrar.updateConfig(
            TTGRegistrarReader.EARNER_RATE_MODEL,
            address(new StableEarnerRateModel(address(minterGateway_)))
        );

        _ttgRegistrar.updateConfig(MAX_EARNER_RATE, _earnerRate);
        _ttgRegistrar.updateConfig(TTGRegistrarReader.EARNERS_LIST_IGNORED, 1);

        minterGateway_.setIsActive(_alice, true);
        minterGateway_.setIsActive(_bob, true);
        minterGateway_.setLatestRate(_minterRate);

        mToken_.setLatestRate(_earnerRate);
        mToken_.setIsEarning(_alice, true);
        mToken_.setIsEarning(_bob, true);
        mToken_.setIsEarning(_ttgVault, true);

        // Update Collateral
        uint240 collateral_ = type(uint240).max;
        uint256[] memory retrievalIds_ = new uint256[](0);

        address[] memory validators_ = new address[](1);
        validators_[0] = _validator1;

        uint40 signatureTimestamp = uint40(vm.getBlockTimestamp());
        uint256[] memory timestamps_ = new uint256[](1);
        timestamps_[0] = signatureTimestamp;

        bytes[] memory signatures_ = new bytes[](1);
        signatures_[0] = _getCollateralUpdateSignature(
            address(minterGateway_),
            _alice,
            collateral_,
            retrievalIds_,
            bytes32(0),
            signatureTimestamp,
            _validator1Pk
        );

        vm.prank(_alice);
        minterGateway_.updateCollateral(collateral_, retrievalIds_, bytes32(0), validators_, timestamps_, signatures_);

        signatures_[0] = _getCollateralUpdateSignature(
            address(minterGateway_),
            _bob,
            collateral_,
            retrievalIds_,
            bytes32(0),
            signatureTimestamp,
            _validator1Pk
        );

        vm.prank(_bob);
        minterGateway_.updateCollateral(collateral_, retrievalIds_, bytes32(0), validators_, timestamps_, signatures_);

        // Mint an amount of M slightly above half of the maximum allowed.
        uint256 mintAmount_ = (uint256(type(uint112).max) * 1e7) / (2e7 - 11);

        minterGateway_.setMintProposalOf(_alice, 1, mintAmount_, vm.getBlockTimestamp(), _alice);
        vm.warp(vm.getBlockTimestamp() + _mintDelay);
        vm.prank(_alice);
        minterGateway_.mintM(1);

        minterGateway_.setMintProposalOf(_bob, 2, mintAmount_, vm.getBlockTimestamp(), _bob);

        vm.warp(vm.getBlockTimestamp() + _mintDelay);
        vm.prank(_bob);

        // Overflows `principalOfTotalEarningSupply` when minting excess owed M to the Vault.
        vm.expectRevert();
        minterGateway_.mintM(3);
    }
}
