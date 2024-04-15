import "ContinuousMathCVL.spec";

using ContinuousIndexingMathHarness as harness;

methods {
    function harness.divideDown(uint240 x, uint128 index) external returns (uint112) envfree;
	function harness.divideUp(uint240 x, uint128 index) external returns (uint112) envfree;
	function harness.multiplyDown(uint112 x, uint128 index) external returns (uint240) envfree;
	function harness.multiplyUp(uint112 x, uint128 index) external returns (uint240) envfree;
}

rule divideDown_equivalence(uint240 x, uint128 index) {
    assert harness.divideDown(x, index) == divideDownCVL(x, index);
}

rule divideUp_equivalence(uint240 x, uint128 index) {
    assert harness.divideUp(x, index) == divideUpCVL(x, index);
}

rule multiplyDown_equivalence(uint112 x, uint128 index) {
    assert harness.multiplyDown(x, index) == multiplyDownCVL(x, index);
}

rule multiplyUp_equivalence(uint112 x, uint128 index) {
    assert harness.multiplyUp(x, index) == multiplyUpCVL(x, index);
}
