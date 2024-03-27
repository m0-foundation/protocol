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
			SumTrackingSetup(e);
			setLegalInitialState(e);
			requireInvariant SumOfBalancesEqualsTotalSupplyMToken();
        }
		preserved deactivateMinter(address minter) with (env e) {
			SumTrackingSetup(e);
			setLegalInitialState(e);
			require minterGateway.getPresentAmount(e, max_uint112) + minterGateway.totalInactiveOwedM(e) < max_uint240;
			requireInvariant SumOfBalancesEqualsTotalSupplyMToken();
        }
		preserved activateMinter(address minter) with (env e) {
			/// Need to be proven:
			require minterGateway._rawOwedM[minter] == 0;  // passes
			SumTrackingSetup(e);
			setLegalInitialState(e);
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
			SumTrackingSetup(e);
			setLegalInitialState(e);
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

/// @title Latest times and indexes remain synced after executing any method of minterGateway
rule LatestTimesRemainSynched(method f, env e) filtered{f -> !f.isView && !f.isPure} {
	setLegalInitialState(e);
	require LatestTimesAreSynched(e);
	require LatestIndexAndRatesAreSynched(e);
	require MToken.getLatestUpdateTimestampInMToken(e) <= assert_uint40(e.block.timestamp);
		env eP;
		require eP.block.timestamp >= e.block.timestamp;
		require ValidTimestamp(eP);
		calldataarg args;
		f(eP,args);
	assert LatestTimesAreSynched(eP);
	assert LatestIndexAndRatesAreSynched(eP);
	assert MToken.getLatestUpdateTimestampInMToken(eP) <= assert_uint40(eP.block.timestamp);
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

/* we exported the next rule into a separate spec since it requires excessive computation
/// @title MZero Protocol Property 1: totalOwedM >= totalMSupply
/// This property is mentioned in the MZero protocol engineering spec doc
rule r01_totalOwedMExceedsTotalMSupply(method f) filtered {
	f -> !f.isView  // view functions are not interesting to verify since they obviously cannot violate this property
}{
	env e; calldataarg args;
	SumTrackingSetup(e);
	setLegalInitialState(e);

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
} */

/// @title MZero Protocol Property 2: totalOwedM = totalActiveOwedM + totalInactiveOwedM
/// This property is mentioned in the MZero protocol engineering spec doc
rule r02_totalOwedMCorrectness {
	env e;
	// There is an assumption in the solidity code about why
	// a potential unchecked overflow is not possible. This should
	// be verified separately.
	assert minterGateway.totalOwedM(e) == require_uint240(minterGateway.totalActiveOwedM(e) + minterGateway.totalInactiveOwedM);
}

/// @title MZero Protocol Property 3: totalMSupply = totalNonEarningMSupply + totalEarningMSupply
/// This property is mentioned in the MZero protocol engineering spec doc
rule r03_totalMSupplyCorrectness {
	env e;
	// There is an assumption in the solidity code about why
	// a potential unchecked overflow is not possible. This should
	// be verified separately.
	assert minterGateway.totalMSupply(e) == require_uint240(MToken.totalNonEarningSupply + MToken.totalEarningSupply(e));
}

/// @title MZero Protocol Property 9: 
/// Minters cannot generate M unless their Eligible Collateral 
/// (tracked by Collateral Value) is sufficiently high (they are overcollateralized)
rule r09_mintersCannotMintMUnlessAreOvercollateralized {
	env e; address minter; uint256 mintId;
	
	uint256 maxAllowedActiveOwedMOfMinter = maxAllowedActiveOwedMOf(e, minter);
	uint256 activeOwedMOfMinter = assert_uint256(activeOwedMOf(e, minter)); // this is uint240 so this cast always succeeds
	
	mintM(e, mintId);
	// if mint was called without reverting the caller must 
	// be overcollateralized
	assert e.msg.sender == minter => activeOwedMOfMinter <= maxAllowedActiveOwedMOfMinter;
}

/// @title MZero Protocol Property 10: If a minter does not call update during the 
/// required interval, their eligible collateral is assumed 0.
rule r10_collateralOfMinterIsZeroIfMinterDoesNotCallUpdate {
	env e;
	address minter;
	// the following returns uint40 so it can always be cast to uint256
	uint256 expiry_time = assert_uint256(collateralExpiryTimestampOf(e, minter));
	uint240 collateralOfMinter = collateralOf(e, minter);

	assert e.block.timestamp > expiry_time => collateralOfMinter == 0;
}

/// @title MZero Protocol Property 13:  A Propose Mint call cannot succeed 
/// before MintDelay time has elapsed.
rule r13_minterMustWaitMintDelayTimeToMintM {
	env e;
	require e.block.timestamp > 1704060000;  // 01.01.2024 00:00:00
	uint256 mintId;
    uint40 createdAt = minterGateway._mintProposals[e.msg.sender].createdAt;
	uint32 mintDelay = mintDelay(e);

	mintM(e, mintId);

	// if mintM did not revert, it must be that the proposal
	// was created at least mintDelay seconds ago

	assert assert_uint256(createdAt) <= e.block.timestamp => 
			assert_uint256(createdAt + mintDelay) <= e.block.timestamp;
}

/// @title Sanity rule to check all methods are reachable and do not always revert.
rule sanity(method f)
{
	env e;
	calldataarg args;
	f(e,args);
	satisfy true;
}

/// @title It is not possible that minter can be both deactivated and active
invariant minterStatesCannotBeContradicting(address minter) 
	!(minterGateway._minterStates[minter].isDeactivated &&
	minterGateway._minterStates[minter].isActive);

/// @title In two consecutive calls at the same timestamp of updateIndex(),
/// the second call should not increase the MToken balance of the ttgVault
rule consecutiveCallOfUpdateIndexCannotIncreaseMToken() {
	env e;
	setLegalInitialState(e);
	minterGateway.updateIndex(e);  // first call
	
	uint240 totalMSupplyBefore = minterGateway.totalMSupply(e);
	minterGateway.updateIndex(e);  // second call should not change the state
	uint240 totalMSupplyAfter = minterGateway.totalMSupply(e);

	assert totalMSupplyBefore == totalMSupplyAfter;
}


/// @title Only the balance of msg.sender can be reduced when calling burnM()
rule r08_burnReducesOnlyTheBalanceOfMsgSender() {
	env e;
	SumTrackingSetup(e);
	setLegalInitialState(e);

	requireInvariant SumOfBalancesEqualsTotalSupply();
	requireInvariant SumOfBalancesEqualsTotalSupplyMToken();

	require minterGateway.totalOwedM(e) >= minterGateway.totalActiveOwedM(e);  // assume no overflow
	require minterGateway.totalOwedM(e) >= minterGateway.totalInactiveOwedM;   // assume no overflow

	require MToken.totalSupply(e) >= assert_uint256(MToken.totalEarningSupply(e));  // assume no overflow
	require MToken.totalSupply(e) >= assert_uint256(MToken.totalNonEarningSupply(e));  // assume no overflow

	require minterGateway.excessOwedM(e) + MToken.totalSupply(e) < max_uint240;  // assume no overflow

	address account;
	address minter; uint256 maxPrincipalAmount; uint256 maxAmount;
	address vault = minterGateway.ttgVault(e);

	uint256 balanceBefore = MToken.balanceOf(e, account);
	burnM(e, minter, maxPrincipalAmount, maxAmount);
	uint256 balanceAfter = MToken.balanceOf(e, account);
	
	assert (e.msg.sender != account) => balanceBefore <= balanceAfter;
	assert (e.msg.sender == account) && account != vault => balanceBefore >= balanceAfter;
}

/// @title Any validator can always freeze any minter
rule r16_validatorCanAlwaysFreezeAnyMinter() {
	env e1; env e2; address minter; address validator;
	require e2.block.timestamp < 4102444800; // 01.01.2100 00:00:00
	require e2.block.timestamp > 1704067200; // 01.01.2024 00:00:00

	bool isValidator = isValidatorApprovedByTTG(e1, validator);
	minterGateway.freezeMinter(e2, minter);

	assert e2.msg.sender == validator => isValidator && minterGateway._minterStates[minter].frozenUntilTimestamp >= assert_uint40(e2.block.timestamp);
}

/// @title Any validator can cancel any existing mintId
rule r16_validatorCanAlwaysCancelAnyExistingMintId() {
	env e1; env e2; address minter; uint256 mintId; address validator;

	bool isValidator = isValidatorApprovedByTTG(e1, validator);
	
	uint48 idBefore = minterGateway._mintProposals[minter].id;
	minterGateway.cancelMint(e2, minter, mintId);
	uint48 idAfter = minterGateway._mintProposals[minter].id;

	assert e2.msg.sender == validator => isValidator && idBefore == assert_uint48(mintId) && idAfter == 0;
}

/// @title After calling minterGateway.updateIndex() the excessOwedM() should be zero
rule mgUpdateIndexZeroesExcessOwedM() {
	env e;
	setLegalInitialState(e);

	uint240 excessOwedMBefore = minterGateway.excessOwedM(e);
	minterGateway.updateIndex(e);
	uint240 excessOwedMAfter = minterGateway.excessOwedM(e);

	address vault = minterGateway.ttgVault(e);
	bool vaultIsEarning = MToken.getIsEarning(e,vault);

	assert !vaultIsEarning => excessOwedMAfter == 0;
}
