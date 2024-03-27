import "./ContinuousMathCVL.spec";
import "./MinterGateway_hooks.spec";
import "./MToken_hooks.spec";

using MockTTGRegistrar as MockTTGRegistrarContract;

function SumTrackingSetup(env e) {
    SumTrackingSetup_MToken(e);
	SumTrackingSetup_Minter(e);
}

/// @title The sum of active/inactive balances equals to the respective total (in minterGateway)
invariant SumOfBalancesEqualsTotalSupply()
	sumOfInactiveBalances == to_mathint(minterGateway.totalInactiveOwedM)
	&&
	sumOfActiveBalances == to_mathint(minterGateway.principalOfTotalActiveOwedM) 
	&& 
	sumOfActiveBalances <= to_mathint(UINT112_MAX())
    {
        preserved with(env e) {
			setLegalInitialState(e);
            SumTrackingSetup(e);
			requireInvariant SumOfBalancesEqualsTotalSupplyMToken();
        }
		preserved deactivateMinter(address minter) with (env e) {
			setLegalInitialState(e);
            SumTrackingSetup(e);
			require minterGateway.getPresentAmount(e, max_uint112) + minterGateway.totalInactiveOwedM(e) < max_uint240;
			requireInvariant SumOfBalancesEqualsTotalSupplyMToken();
        }
		preserved activateMinter(address minter) with (env e) {
			/// Need to be proven:
			require minterGateway._rawOwedM[minter] == 0;  // passes
			setLegalInitialState(e);
            SumTrackingSetup(e);
			requireInvariant SumOfBalancesEqualsTotalSupplyMToken();
		}
    }

/// @title The sum of active/inactive balances equals to the respective total (in MToken)
invariant SumOfBalancesEqualsTotalSupplyMToken()
	sumOfInactiveBalancesMToken == to_mathint(MToken.totalNonEarningSupply)
	&&
	sumOfActiveBalancesMToken == to_mathint(MToken.principalOfTotalEarningSupply)
    {
        preserved with(env e) {
			setLegalInitialState(e);
            SumTrackingSetup(e);
			requireInvariant SumOfBalancesEqualsTotalSupply();
        }
    }

function LatestTimesAreSynched(env e) returns bool {
	return 
		MToken.getLatestUpdateTimestampInMToken(e) ==
		minterGateway.getLatestUpdateTimestampInMinterGateway(e);
}

function LatestIndexAndRatesAreSynched(env e) returns bool {
	uint128 currentIndex_token = MToken.currentIndex(e);
	uint128 latestIndex_token = MToken.getLatestIndexInMToken(e);
	uint32 currentRate_token = MToken.getEarnerRate(e);
	uint32 latestRate_token =  MToken.getLatestRateInMToken(e);
	uint256 latestTimestamp_token = assert_uint256(MToken.getLatestUpdateTimestampInMToken(e));

	uint128 currentIndex_minter = minterGateway.currentIndex(e);
	uint128 latestIndex_minter= minterGateway.getLatestIndexInMinterGateway(e);
	uint32 currentRate_minter = minterGateway.getMinterRate(e);
	uint32 latestRate_minter =  minterGateway.getLatestRateInMinterGateway(e);
	uint256 latestTimestamp_minter = minterGateway.getLatestUpdateTimestampInMinterGateway(e);

	return (
		latestTimestamp_token == e.block.timestamp =>
		(currentIndex_token == latestIndex_token && currentRate_token == latestRate_token)
	)
	&&
	(
		latestTimestamp_minter == e.block.timestamp =>
		(currentIndex_minter == latestIndex_minter && currentRate_minter == latestRate_minter)
	);
}

function setLegalInitialState(env e) {
	require ValidTimestamp(e);
	require LatestTimesAreSynched(e);
	require LatestIndexAndRatesAreSynched(e);
	require MToken.getLatestRateInMToken(e) < 40000;  // up to 400%
	require minterGateway.getLatestRateInMinterGateway(e) < 40000;  // up to 400%
	require MToken.getLatestIndexInMToken(e) >= assert_uint128(EXP_SCALED_ONE());
	require minterGateway.getLatestIndexInMinterGateway(e) >= assert_uint128(EXP_SCALED_ONE());

	address vault;
	require minterGateway.ttgVault(e) == vault;
	require vault != 0 && vault != minterGateway && vault != MToken && vault != MockTTGRegistrarContract;

	bool vaultIsEarning = MToken.getIsEarning(e,vault);
	require !vaultIsEarning;  // vault cannot be earning
}

/// @title MZero Protocol Property 1: totalOwedM >= totalMSupply
/// This property is mentioned in the MZero protocol engineering spec doc
rule r01_totalOwedMExceedsTotalMSupply(method f) filtered {
	f -> !f.isView  // view functions are not interesting to verify since they obviously cannot violate this property
}{
	env e; calldataarg args;
	setLegalInitialState(e);
	SumTrackingSetup(e);

	requireInvariant SumOfBalancesEqualsTotalSupplyMToken();
	requireInvariant SumOfBalancesEqualsTotalSupply();
	require minterGateway.getPresentAmount(e, max_uint112) + minterGateway.totalInactiveOwedM(e) < max_uint240;  // assume no overflow of totalOwedM

	require minterGateway.totalOwedM(e) >= minterGateway.totalActiveOwedM(e);  // assume no overflow
	require minterGateway.totalOwedM(e) >= minterGateway.totalInactiveOwedM;   // assume no overflow

	require MToken.totalSupply(e) >= assert_uint256(MToken.totalEarningSupply(e));  // assume no overflow
	require MToken.totalSupply(e) >= assert_uint256(MToken.totalNonEarningSupply(e));  // assume no overflow

	require minterGateway.excessOwedM(e) + MToken.totalSupply(e) < max_uint240;  // assume no overflow

	uint240 totalOwedMBefore = minterGateway.totalOwedM(e);
	uint240 totalMSupplyBefore = minterGateway.totalMSupply(e);
		f(e, args);
	uint240 totalOwedMAfter = minterGateway.totalOwedM(e);
	uint240 totalMSupplyAfter = minterGateway.totalMSupply(e);
	assert totalOwedMBefore >= totalMSupplyBefore => totalOwedMAfter >= totalMSupplyAfter;
}
