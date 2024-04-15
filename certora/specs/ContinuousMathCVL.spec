definition EXP_SCALED_ONE() returns uint56 = 10^12;
definition EXP_SCALED_ONE_48() returns uint48 = 10^12;

function mulDivDownCVL(uint256 x, uint256 y, uint256 z) returns uint256 {
    uint256 res;
    require z != 0;
    mathint xy = x * y;
    mathint fz = res * z;

    require xy >= fz;
    require fz + z > xy;
    return res; 
}

function divideDownCVL(uint240 x, uint128 index) returns uint112 {
	return require_uint112(
		mulDivDownCVL(assert_uint256(x) , assert_uint256(EXP_SCALED_ONE()), assert_uint256(index))
	);
}

function divideUpCVL(uint240 x, uint128 index) returns uint112 {
	uint256 temp = require_uint256(EXP_SCALED_ONE() * x + index - 1);
	return require_uint112(
		mulDivDownCVL(temp , 1, assert_uint256(index))
	);
}

function multiplyDownCVL(uint112 x, uint128 index) returns uint240 {
	return assert_uint240(
		mulDivDownCVL(assert_uint256(x), assert_uint256(index), assert_uint256(EXP_SCALED_ONE()))
	);
}

function multiplyUpCVL(uint112 x, uint128 index) returns uint240 {
	uint256 temp = require_uint256(index * x + EXP_SCALED_ONE() - 1);
	return assert_uint240(
		mulDivDownCVL(temp, 1, assert_uint256(EXP_SCALED_ONE()))
	);
}
