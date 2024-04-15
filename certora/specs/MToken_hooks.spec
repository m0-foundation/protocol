import "setup.spec";

using MTokenHarness as MToken;

/// True sum of balances.
ghost mathint sumOfBalancesMToken { init_state axiom sumOfBalancesMToken == 0; }
ghost mathint sumOfActiveBalancesMToken { init_state axiom sumOfActiveBalancesMToken == 0; }
ghost mathint sumOfInactiveBalancesMToken { init_state axiom sumOfInactiveBalancesMToken == 0; }

/// The initial value is being updated as we access the acounts balances one-by-one.
/// Should only be used as an initial value, never post-action!
ghost mathint sumOfBalancesMToken_init { init_state axiom sumOfBalancesMToken_init == 0; }
ghost mathint sumOfActiveBalancesMToken_init { init_state axiom sumOfActiveBalancesMToken_init == 0; }
ghost mathint sumOfInactiveBalancesMToken_init { init_state axiom sumOfInactiveBalancesMToken_init == 0; }

ghost mapping(address => bool) g_rawBalanceAccessed;  // for each address checks if the rawBalance was ever read
ghost mapping(address => bool) g_isEarning;  // for each address account - offset 0
ghost mapping(address => uint240) g_rawBalance;  // for each address account - offset 8

hook Sstore MToken._balances[KEY address k].isEarning bool isEarning (bool wasEarning) {
	g_isEarning[k] = isEarning;
	uint240 balance = MToken._balances[k].rawBalance;
	if(isEarning && !wasEarning) {
		sumOfActiveBalancesMToken = sumOfActiveBalancesMToken + balance;
		sumOfInactiveBalancesMToken = sumOfInactiveBalancesMToken - balance;
	}
	else if(!isEarning && wasEarning) {
		sumOfActiveBalancesMToken = sumOfActiveBalancesMToken - balance;
		sumOfInactiveBalancesMToken = sumOfInactiveBalancesMToken + balance; 
	}
}

hook Sload bool isEarning MToken._balances[KEY address k].isEarning {
	require g_isEarning[k] == isEarning;
}

hook Sstore MToken._balances[KEY address k].rawBalance uint240 rawBalance (uint240 rawBalance_old) {
	g_rawBalance[k] = rawBalance;
	// require rawBalance <= UINT112_MAX();  // ensure we don't overflow
	if (!g_rawBalanceAccessed[k] && g_isEarning[k]) {
		require rawBalance <= UINT112_MAX();  // earning
		g_rawBalanceAccessed[k] = true;
		
		sumOfBalancesMToken_init = sumOfBalancesMToken_init - rawBalance_old;
        require sumOfBalancesMToken_init >= 0;

		sumOfActiveBalancesMToken_init = sumOfActiveBalancesMToken_init - rawBalance_old;
		require sumOfActiveBalancesMToken_init >= 0;
	} else if (!g_rawBalanceAccessed[k] && !g_isEarning[k]) {
		require rawBalance <= UINT112x128_MAX();  // non earning
		g_rawBalanceAccessed[k] = true;

		sumOfBalancesMToken_init = sumOfBalancesMToken_init - rawBalance_old;
        require sumOfBalancesMToken_init >= 0;

		sumOfInactiveBalancesMToken_init = sumOfInactiveBalancesMToken_init - rawBalance_old;
		require sumOfInactiveBalancesMToken_init >= 0;
	}
	sumOfBalancesMToken = sumOfBalancesMToken + rawBalance - rawBalance_old;

	if (g_isEarning[k]) {
		sumOfActiveBalancesMToken = sumOfActiveBalancesMToken + rawBalance - rawBalance_old;
	} else {
		sumOfInactiveBalancesMToken = sumOfInactiveBalancesMToken + rawBalance - rawBalance_old;
	}
}

hook Sload uint240 rawBalance MToken._balances[KEY address k].rawBalance {
	require g_rawBalance[k] == rawBalance;
	if (!g_rawBalanceAccessed[k] && g_isEarning[k]) {
		require rawBalance <= UINT112_MAX();  // earning
		g_rawBalanceAccessed[k] = true;
		
		sumOfBalancesMToken_init = sumOfBalancesMToken_init - rawBalance;
        require sumOfBalancesMToken_init >= 0;

		sumOfActiveBalancesMToken_init = sumOfActiveBalancesMToken_init - rawBalance;
		require sumOfActiveBalancesMToken_init >= 0;
	} else if (!g_rawBalanceAccessed[k] && !g_isEarning[k]) {
		require rawBalance <= UINT112x128_MAX();  // non earning
		g_rawBalanceAccessed[k] = true;

		sumOfBalancesMToken_init = sumOfBalancesMToken_init - rawBalance;
        require sumOfBalancesMToken_init >= 0;

		sumOfInactiveBalancesMToken_init = sumOfInactiveBalancesMToken_init - rawBalance;
		require sumOfInactiveBalancesMToken_init >= 0;
	}
	// require rawBalance <= UINT112_MAX();  // ensure we don't overflow
}

function SumTrackingSetup_MToken(env e) {
	require sumOfBalancesMToken == sumOfBalancesMToken_init;
	require sumOfActiveBalancesMToken == sumOfActiveBalancesMToken_init;
	require sumOfInactiveBalancesMToken == sumOfInactiveBalancesMToken_init;
	setAllRawBalanceAccessedToFalse();
}

function setAllRawBalanceAccessedToFalse() {
	require forall address a. !g_rawBalanceAccessed[a];
	//havoc g_rawBalanceAccessed assuming 
    //    forall address a. !g_rawBalanceAccessed@new[a];
}
