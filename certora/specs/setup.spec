methods {
	function ContinuousIndexingMath.getContinuousIndex(uint64 yearlyRate, uint32 time) internal returns (uint48) => ghostContinuousIndex(yearlyRate, time);
	function ContinuousIndexingMath.multiplyIndicesUp(uint128 index, uint48 deltaIndex) internal returns (uint144) => ghostMultiplyIndices(index, deltaIndex);
	function ContinuousIndexingMath.multiplyIndicesDown(uint128 index, uint48 deltaIndex) internal returns (uint144) => ghostMultiplyIndices(index, deltaIndex);

	function MTokenHarness.latestUpdateTimestamp() external returns (uint40) envfree;
	function MTokenHarness.getInternalBalanceOf(address) external returns (uint240) envfree;

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
