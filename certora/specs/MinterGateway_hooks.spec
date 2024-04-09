import "setup.spec";

using MinterGatewayHarness as minterGateway;

/// True sum of balances.
ghost mathint sumOfBalances { init_state axiom sumOfBalances == 0; }
ghost mathint sumOfActiveBalances { init_state axiom sumOfActiveBalances == 0; }
ghost mathint sumOfInactiveBalances { init_state axiom sumOfInactiveBalances == 0; }

/// The initial value is being updated as we access the acounts balances one-by-one.
/// Should only be used as an initial value, never post-action!
ghost mathint sumOfBalances_init { init_state axiom sumOfBalances_init == 0; }
ghost mathint sumOfActiveBalances_init { init_state axiom sumOfActiveBalances_init == 0; }
ghost mathint sumOfInactiveBalances_init { init_state axiom sumOfInactiveBalances_init == 0; }

ghost mapping(address => bool) didAccessAccount;

function SumTrackingSetup_Minter(env e) {
    require sumOfBalances == sumOfBalances_init;
	require sumOfActiveBalances == sumOfActiveBalances_init;
	require sumOfInactiveBalances == sumOfInactiveBalances_init;
    //havoc didAccessAccount assuming 
	require forall address minter. !didAccessAccount[minter];
}

hook Sstore minterGateway._minterStates[KEY address minter].isActive bool isActive (bool wasActive) {
	uint240 _balance =  minterGateway._rawOwedM[minter];
	//require to_mathint(_balance) <= to_mathint(UINT112_MAX());
	if(isActive && !wasActive) {
		sumOfActiveBalances = sumOfActiveBalances + _balance;
		sumOfInactiveBalances = sumOfInactiveBalances - _balance;
	}
	else if(!isActive && wasActive) {
		sumOfActiveBalances = sumOfActiveBalances - _balance;
		sumOfInactiveBalances = sumOfInactiveBalances + _balance;
	}
}

hook Sload uint240 _balance minterGateway._rawOwedM[KEY address minter] {
    if(!didAccessAccount[minter]) {
        didAccessAccount[minter] = true;
        sumOfBalances_init = sumOfBalances_init - _balance;
        require sumOfBalances_init >= 0;
		if (minterGateway._minterStates[minter].isActive) {
			sumOfActiveBalances_init = sumOfActiveBalances_init - _balance;
			require sumOfActiveBalances_init >= 0;
		} else {
			sumOfInactiveBalances_init = sumOfInactiveBalances_init - _balance;
			require sumOfInactiveBalances_init >= 0;
		}
    }
}

hook Sstore minterGateway._rawOwedM[KEY address minter] uint240 _balance (uint240 _balance_old) {
    if(!didAccessAccount[minter]) {
        didAccessAccount[minter] = true;
        sumOfBalances_init = sumOfBalances_init - _balance_old;
        require sumOfBalances_init >= 0;
		
		if (minterGateway._minterStates[minter].isActive) {
			sumOfActiveBalances_init = sumOfActiveBalances_init - _balance_old;
			require sumOfActiveBalances_init >= 0;
		} else {
			sumOfInactiveBalances_init = sumOfInactiveBalances_init - _balance_old;
			require sumOfInactiveBalances_init >= 0;
		}
    }
    sumOfBalances = sumOfBalances + _balance - _balance_old;
	
	if (minterGateway._minterStates[minter].isActive) {
		sumOfActiveBalances = sumOfActiveBalances + _balance - _balance_old;
	}
	else {
		sumOfInactiveBalances = sumOfInactiveBalances + _balance - _balance_old;
	}
}
