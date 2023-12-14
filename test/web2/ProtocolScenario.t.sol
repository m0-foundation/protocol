// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import { console2, stdError, Test, Vm } from "../../lib/forge-std/src/Test.sol";
import { ScenarioTest } from "./Scenario.sol";

contract ProtocolScenarioTest is ScenarioTest {

    function setUp() public {
        _setUp();
    }

    function test_mintM() public {
        // 2023-01-01 00:00:00
        _protocol.updateIndex(); // Init compunding. but why?
        assertProtocolIndexing(1_000, 1_000000000000000000, 1_000000000000000000, t[0]);
        assertMTokenIndexing(      0, 1_000000000000000000, 1_000000000000000000, t[0]);

        console2.log("  Initially activate Michael as a minter");
        vm.prank(_michael.addr);
        _protocol.activateMinter(_michael.addr);

        assertTrue(_protocol.isActiveMinter(_michael.addr));

        // 2023-01-01 08:00:00
        t[1] = _advanceTimeBy(8 hours);
        console2.log("  Victor is creating a signature for Michael");

        assertProtocolIndexing(1_000, 1_000000000000000000, 1_000091328371095022, t[0]);
        assertMTokenIndexing(      0, 1_000000000000000000, 1_000000000000000000, t[0]);

        uint256 collateral = 1_000_000e6; // 1 Mio collateral
        uint256[] memory retrievalIds = new uint256[](0); // no retrievals to be closed
        bytes32 metadataHash = keccak256("My Metadata"); // random metadata
        uint256 signatureTimestamp = _currentTimestamp;

        bytes memory signature = _createUpdateCollateralSignature(
            _michael.addr,
            collateral,
            retrievalIds,
            metadataHash,
            signatureTimestamp,
            _victor.key
        );

        // 2023-01-01 10:00:00
        t[2] = _advanceTimeBy(2 hours);
        console2.log("  Michael has obtained all required signatures (=1) and updates its collateral");

        address[] memory validators = new address[](1);
        uint256[] memory timestamps = new uint256[](1);
        bytes[] memory signatures = new bytes[](1);

        validators[0] = _victor.addr;
        timestamps[0] = signatureTimestamp;
        signatures[0] = signature;

        vm.prank(_michael.addr);
        _protocol.updateCollateral(collateral, retrievalIds, metadataHash, validators, timestamps, signatures);   

        assertEq(collateral, _protocol.collateralOf(_michael.addr));
        assertProtocolIndexing(1_000, 1_000114161767100174, 1_000114161767100174, t[2]);
        assertMTokenIndexing(      0, 1_000000000000000000, 1_000000000000000000, t[2]);

        // 2023-01-01 11:00:00
        t[3] = _advanceTimeBy(1 hours);
        console2.log("  Michael is proposing a mint of 500K M for himself");

        uint256 mintAmount = 500_000e6; // 500K M

        vm.prank(_michael.addr);
        uint256 mintId = _protocol.proposeMint(mintAmount, _michael.addr); 

        assertProtocolIndexing(1_000, 1_000114161767100174, 1_000125578660595639, t[2]); // no change in protocol
        assertMTokenIndexing(      0, 1_000000000000000000, 1_000000000000000000, t[2]); // no change in mToken

        // 2023-01-01 11:00:00
        t[4] = _advanceTimeBy(4 hours);
        console2.log("  Michael executing the mint after the mintTTL has passed");

        vm.prank(_michael.addr);
        _protocol.mintM(mintId);

        assertProtocolIndexing(1_000, 1_000171247537898172, 1_000171247537898172, t[4]);
        assertMTokenIndexing(  1_000, 1_000000000000000000, 1_000000000000000000, t[4]); // first time mToken.updateIndex() is called

        assertEq(_protocol.activeOwedMOf(_michael.addr), 499_999_999999); // ~500k
        assertEq(_protocol.activeOwedMOf(_michael.addr), 499_999_999999); // ~500k
        assertEq(_protocol.totalActiveOwedM(), 499_999_999999); // ~500k
        //console2.logUint(_protocol.)
        assertEq(_mToken.balanceOf(_michael.addr), 500_000_000000); // 500k
       // assertEq(_mToken.balanceOf(_vault), 0);

    }







}
