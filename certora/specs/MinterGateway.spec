// import "./erc20.spec";

// using DummyERC20A as tokenA;
// using DummyERC20B as tokenB;

// methods {
//     function _.transfer(address token_, address to_, uint256 amount_) internal with(env e) => CVLTransfer(e, token_, to_, amount_) expect (bool);
// }

// function CVLTransfer(env e, address token_, address to_, uint256 amount_) returns bool {
//     if (token_ == tokenA) {
//         return tokenA.transfer(e, to_, amount_);
//     } else {
//         return tokenB.transfer(e, to_, amount_);
//     }
// }




rule sanity(method f)
{
	env e;
	calldataarg args;
	f(e,args);
	satisfy true;
    // assert false;
}