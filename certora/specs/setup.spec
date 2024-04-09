methods {
	function ContinuousIndexingMath.getContinuousIndex(uint64 yearlyRate, uint32 time) internal returns (uint48) => ghostContinuousIndex(yearlyRate, time);
	function ContinuousIndexingMath.multiplyIndicesUp(uint128 index, uint48 deltaIndex) internal returns (uint144) => ghostMultiplyIndices(index, deltaIndex);
	function ContinuousIndexingMath.multiplyIndicesDown(uint128 index, uint48 deltaIndex) internal returns (uint144) => ghostMultiplyIndices(index, deltaIndex);

	function MinterGatewayHarness.getMinterRate() external returns (uint32);
	function MTokenHarness.getEarnerRate() external returns (uint32);
	function MinterGateway._rate() internal returns (uint32) => ghostMinterRate;
	function MToken._rate() internal returns (uint32) => ghostEarnerRate;
	
	function MinterGatewayHarness.latestUpdateTimestamp() external returns (uint40) envfree;
	function MTokenHarness.latestUpdateTimestamp() external returns (uint40) envfree;
	function MTokenHarness.getInternalBalanceOf(address) external returns (uint240) envfree;

	function _._verifyValidatorSignatures(
        address minter_,
        uint256 collateral_,
        uint256[] calldata retrievalIds_,
        bytes32 metadataHash_,
        address[] calldata validators_,
        uint256[] calldata timestamps_,
        bytes[] calldata signatures_
    ) internal => NONDET;  // assumption that the ERC-712 verification is passing

	function _._getDigest(bytes32 internalDigest_) internal => NONDET; // ERC-712 verification
	function _._getDomainSeparator() internal => NONDET; // ERC-712

	function ContinuousIndexingMath.divideDown(uint240 x, uint128 index) internal returns (uint112) => divideDownCVL(x,index);
	function ContinuousIndexingMath.divideUp(uint240 x, uint128 index) internal returns (uint112) => divideUpCVL(x,index);
	function ContinuousIndexingMath.multiplyDown(uint112 x, uint128 index) internal returns (uint240) => multiplyDownCVL(x,index);
	function ContinuousIndexingMath.multiplyUp(uint112 x, uint128 index) internal returns (uint240) => multiplyUpCVL(x,index);
}

definition UINT256_MAX() returns uint256 = max_uint256;
definition UINT112_MAX() returns uint240 = max_uint112;
definition UINT128_MAX() returns uint240 = max_uint128;
definition UINT112x128_MAX() returns uint240 = 1766847064778384329583297500742918175539924679078620667118468273195188225;  // UINT112_MAX * UINT128_MAX
definition ValidTimestamp(env e) returns bool = 
	e.block.timestamp < 4102444800 && e.block.timestamp > 1704067200; 
	// [01.01.2024 00:00:00, 01.01.2100 00:00:00]

ghost uint32 ghostMinterRate;
ghost uint32 ghostEarnerRate;

ghost ghostContinuousIndex(uint64, uint32) returns uint48 {
	axiom forall uint32 time. 
		ghostContinuousIndex(0, time) == EXP_SCALED_ONE_48(); // EXP_SCALED_ONE = 1e12
	axiom forall uint64 yearlyRate.
		ghostContinuousIndex(yearlyRate, 0) == EXP_SCALED_ONE_48(); // EXP_SCALED_ONE = 1e12
	axiom forall uint64 yearlyRate1. 
			forall uint64 yearlyRate2. 
				forall uint32 time.
					yearlyRate1 >= yearlyRate2 && yearlyRate2 > 0 =>
						ghostContinuousIndex(yearlyRate1, time) >= ghostContinuousIndex(yearlyRate2, time);
	axiom forall uint64 yearlyRate. 
			forall uint32 time1. 
				forall uint32 time2.
					time1 >= time2 && time2 > 0 =>
						ghostContinuousIndex(yearlyRate, time1) >= ghostContinuousIndex(yearlyRate, time2);
}

ghost ghostMultiplyIndices(uint128, uint48) returns uint144 {
	axiom forall uint128 index1. 
			forall uint128 index2. 
				forall uint48 deltaIndex.
					index1 >= index2 && index2 > 0 =>
						ghostMultiplyIndices(index1, deltaIndex) >= ghostMultiplyIndices(index2, deltaIndex);
	axiom forall uint128 index. 
			forall uint48 deltaIndex1. 
				forall uint48 deltaIndex2.
					deltaIndex1 >= deltaIndex2 && deltaIndex2 > 0 =>
						ghostMultiplyIndices(index, deltaIndex1) >= ghostMultiplyIndices(index, deltaIndex2);
	axiom forall uint128 index. 
			forall uint48 deltaIndex.
				index == 0 || deltaIndex == 0 =>
					ghostMultiplyIndices(index, deltaIndex) == 0;
	axiom forall uint128 index. 
		to_mathint(ghostMultiplyIndices(index, EXP_SCALED_ONE_48())) == to_mathint(index);
}
