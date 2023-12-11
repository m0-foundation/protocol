// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import { IMToken } from "../../../src/interfaces/IMToken.sol";

contract MockMToken is IMToken
{
    bool internal _failUpdateIndex = false;
    bool internal _failBurn = false;
    bool internal _failMint = false;
    bool internal _failStartEarning = false;
    bool internal _failStopEarning = false;

    uint256 internal _currentIndex = 100;
    uint256 internal _latestIndex = 101;
    uint256 internal _latestUpdateTimestamp = 103;
    uint256 internal _earnerRate = 1;
    bool internal _hasOptedOutOfEarning = false;
    bool internal _isEarning = false;
    address internal _protocol;
    address internal _rateModel;
    address internal _spogRegistrar;
    uint256 internal _totalEarningSupply = 1;
    uint256 internal _totalNonEarningSupply = 1;
    bool internal _approveSuccess = true;
    bool internal _decreaseAllowanceSuccess = true;
    bool internal _increaseAllowanceSuccess = true;
    bool internal _transferSuccess = true;
    bool internal _transferFromSuccess = true;
    uint256 internal _allowance = 0;
    uint256 internal _balanceOf = 1;
    uint8 internal _decimals = 6;
    string internal _name = "mzero";
    string internal _symbol = "M";
    uint256 internal _totalSupply = 1000;
    uint256 internal _nonce = 1;

    event ExecutedCurrentIndex();
    event ExecutedLastIndex();
    event ExecutedUpdateIndex();
    event ExecutedLatestUpdateTimestamp();
    event ExecutedBurn(address account, uint256 amount);
    event ExecutedMint(address account, uint256 amount);
    event ExecutedStartEarning(address account);
    event ExecutedStopEarning(address account);
    event ExecutedEarnerRate();
    event ExecutedHasOptedOutOfEarning(address account);
    event ExecutedIsEarning(address account);
    event ExecutedProtocol();
    event ExecutedRateModel();
    event ExecutedSpogRegistrar();
    event ExecutedTotalEarningSupply();
    event ExecutedTotalNonEarningSupply();
    event ExecutedPermit(address owner, address spender, uint256 value, uint256 deadline);
    event ExecutedApprove(address spender, uint256 amount);
    event ExecutedDecreaseAllowance(address spender, uint256 subtractedAmount);
    event ExecutedIncreaseAllowance(address spender, uint256 addedAmount);
    event ExecutedTransfer(address recipient, uint256 amount);
    event ExecutedTransferFrom(address sender, address recipient, uint256 amount);
    event ExecutedAllowance(address account, address spender);
    event ExecutedBalanceOf(address account);
    event ExecutedDecimals();
    event ExecutedName();
    event ExecutedSymbol();
    event ExecutedTotalSupply();
    event ExecutedNonces(address account);

function currentIndex() external view returns (uint256) {
        //emit ExecutedCurrentIndex();
        return _currentIndex;
    }

    function latestIndex() external view returns (uint256) {
        //emit ExecutedLastIndex();
        return _latestIndex;
    }

    function latestUpdateTimestamp() external view returns (uint256) {
        //emit ExecutedLatestUpdateTimestamp();
        return _latestUpdateTimestamp;
    }

    function updateIndex() external returns (uint256) {
        if (_failUpdateIndex) revert();
        emit ExecutedUpdateIndex();
        return _currentIndex;
    }

    function burn(address account_, uint256 amount_) external {
        if (_failBurn) revert();
        emit ExecutedMint(account_, amount_);
    }

    function mint(address account_, uint256 amount_) external {
        if (_failMint) revert();
        emit ExecutedBurn(account_, amount_);
    }

    function startEarning() external {
        if (_failStartEarning) revert();
        emit  ExecutedStartEarning(address(0));
    }

    function startEarning(address account_) external {
        if (_failStartEarning) revert();
        emit  ExecutedStartEarning(account_);
    }

    function stopEarning() external {
        if (_failStopEarning) revert();
        emit ExecutedStopEarning(address(0));
    }

    function stopEarning(address account_) external {
        if (_failStopEarning) revert();
        emit ExecutedStopEarning(account_);
    }

    function earnerRate() external view returns (uint256) {
        //emit ExecutedEarnerRate();
        return _earnerRate;
    }

    function hasOptedOutOfEarning(address account) external view returns (bool) {
        //emit ExecutedHasOptedOutOfEarning(account);
        return _hasOptedOutOfEarning;
    }

    function isEarning(address account) external view returns (bool) {
        //emit ExecutedIsEarning(account);
        return _isEarning;
    }

    function protocol() external view returns (address) {
        //emit ExecutedProtocol();
        return _protocol;
    }

    function rateModel() external view returns (address) {
        //emit ExecutedRateModel();
        return _rateModel;
    }

    function spogRegistrar() external view returns (address) {
        //emit ExecutedSpogRegistrar();
        return _spogRegistrar;
    }

    function totalEarningSupply() external view returns (uint256) {
        //emit ExecutedTotalEarningSupply();
        return _totalEarningSupply;
    }

    function totalNonEarningSupply() external view returns (uint256) {
        //emit ExecutedTotalEarningSupply();
        return _totalNonEarningSupply;
    }

    function permit(address owner_, address spender_, uint256 value_, uint256 deadline_, uint8 v_, bytes32 r_, bytes32 s_) external {
        emit ExecutedPermit(owner_, spender_, value_, deadline_);
    }

    function permit(address owner_, address spender_, uint256 value_, uint256 deadline_, bytes memory signature_) external {
        emit ExecutedPermit(owner_, spender_, value_, deadline_);
    }

    function PERMIT_TYPEHASH() external view returns (bytes32) {
        return keccak256("random_string");
    }

    function approve(address spender_, uint256 amount_) external returns (bool) {
        emit ExecutedApprove(spender_, amount_);
        return _approveSuccess;
    }

    function decreaseAllowance(address spender_, uint256 subtractedAmount_) external returns (bool) {
        emit ExecutedDecreaseAllowance(spender_, subtractedAmount_);
        return _decreaseAllowanceSuccess;
    }

    function increaseAllowance(address spender_, uint256 addedAmount_) external returns (bool) {
        emit ExecutedIncreaseAllowance(spender_, addedAmount_);
        return _increaseAllowanceSuccess;
    }

    function transfer(address recipient_, uint256 amount_) external returns (bool) {
        emit ExecutedTransfer(recipient_, amount_);
        return _transferSuccess;
    }

    function transferFrom(address sender_, address recipient_, uint256 amount_) external returns (bool) {
        emit ExecutedTransferFrom(sender_, recipient_, amount_);
        return _transferFromSuccess;
    }

    function allowance(address account_, address spender_) external view returns (uint256) {
       // emit ExecutedAllowance(account_, spender_);
        return _allowance;
    }

    function balanceOf(address account_) external view returns (uint256) {
        //emit ExecutedBalanceOf(account_);
        return _balanceOf;
    }

    function decimals() external view returns (uint8) {
        //emit ExecutedDecimals();
        return _decimals;
    }

    function name() external view returns (string memory) {
        //emit ExecutedName();
        return _name;
    }

    function symbol() external view returns (string memory) {
        //emit ExecutedSymbol();
        return _symbol;
    }

    function totalSupply() external view returns (uint256) {
        //emit ExecutedTotalSupply();
        return _totalSupply;
    }

    function nonces(address account) external view returns (uint256) {
        //emit ExecutedNonces(account);
        return _nonce;
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32 domainSeparator) {
        return keccak256("signature");
    }

    function __failUpdateIndex(bool failUpdateIndex_) external {
        _failUpdateIndex = failUpdateIndex_;
    }

    function __failBurn(bool failBurn_) external {
        _failBurn = failBurn_;
    }

    function __failMint(bool failMint_) external {
        _failMint = failMint_;
    }

    function __failStartEarning(bool failStartEarning_) external {
        _failStartEarning = failStartEarning_;
    }

    function __failStopEarning(bool failStopEarning_) external {
        _failStopEarning= failStopEarning_;
    }

    function __setCurrentIndex(uint256 currentIndex_) external {
        _currentIndex = currentIndex_;
    }

    function __setLatestIndex(uint256 latestIndex_) external {
        _latestIndex = latestIndex_;
    }

    function __setLatestUpdateTimestamp(uint256 latestUpdateTimestamp_) external {
        _latestUpdateTimestamp = latestUpdateTimestamp_;
    }

    function __setEarnerRate(uint256 earnerRate_) external {
        _earnerRate = earnerRate_;
    }

    function __setHasOptedOutOfEarning(bool hasOptedOutOfEarning_) external {
        _hasOptedOutOfEarning = hasOptedOutOfEarning_;
    }

    function __setIsEarning(bool isEarning_) external {
        _isEarning = isEarning_;
    }

    function __setProtocol(address protocol_) external {
        _protocol = protocol_;
    }

    function __setRateModel(address rateModel_) external {
        _rateModel = rateModel_;
    }

    function __setSpogRegistrar(address spogRegistrar_) external {
        _spogRegistrar = spogRegistrar_;
    }

    function __setTotalEarningSupply(uint256 totalEarningSupply_) external {
        _totalEarningSupply = totalEarningSupply_;
    }

    function __setTotalNonEarningSupply(uint256 totalNonEarningSupply_) external {
        _totalNonEarningSupply = totalNonEarningSupply_;
    }

    function __setApproveSuccess(bool approveSuccess_) external {
        _approveSuccess = approveSuccess_;
    }

    function __setDecreaseAllowanceSuccess(bool decreaseAllowanceSuccess_) external {
        _decreaseAllowanceSuccess = decreaseAllowanceSuccess_;
    }

    function __setIncreaseAllowanceSuccess(bool increaseAllowanceSuccess_) external {
        _increaseAllowanceSuccess = increaseAllowanceSuccess_;
    }

    function __setTransferSuccess(bool transferSuccess_) external {
        _transferSuccess = transferSuccess_;
    }

    function __setTransferFromSuccess(bool transferFromSuccess_) external {
        _transferFromSuccess = transferFromSuccess_;
    }

    function __setAllowance(uint256 allowance_) external {
        _allowance = allowance_;
    }

    function __setBalanceOf(uint256 balanceOf_) external {
        _balanceOf = balanceOf_;
    }

    function __setDecimals(uint8 decimals_) external {
        _decimals = decimals_;
    }

    function __setName(string memory name_) external {
        _name = name_;
    }

    function __setSymbol(string memory symbol_) external {
        _symbol = symbol_;
    }

    function __setTotalSupply(uint256 totalSupply_) external {
        _totalSupply = totalSupply_;
    }

    function __setNonce(uint256 nonce_) external {
        _nonce = nonce_;
    }

}
