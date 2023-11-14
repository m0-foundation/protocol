// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { SPOGRegistrarReader } from "./libs/SPOGRegistrarReader.sol";

import { IInterestRateModel } from "./interfaces/IInterestRateModel.sol";
import { IMToken } from "./interfaces/IMToken.sol";

import { ContinuousInterestIndexing } from "./ContinuousInterestIndexing.sol";
import { ERC20Permit } from "./ERC20Permit.sol";

// TODO: Consider an socially/optically "safer" `burn` via `burn(uint amount_)` where the account is `msg.sender`.
// TODO: Some mechanism that allows a UI/script to determine how much an account or the system stands to gain from
//       calling `updateIndex()`.
// TODO: Some increased/decreased earning supply event(s)? Might be useful for a UI/script, or useless in general.
// TODO: Is an `indexUpdated` event useful?

contract MToken is IMToken, ContinuousInterestIndexing, ERC20Permit {
    address public immutable protocol;
    address public immutable spogRegistrar;

    uint256 internal _totalEarningSupplyPrincipal;

    // TODO: Consider replace with flag bit/byte in balance.
    mapping(address account => bool isEarning) internal _isEarning;

    // TODO: Consider replace with flag bit/byte in balance.
    mapping(address account => bool hasOptedOutOfEarning) internal _hasOptedOutOfEarning;

    modifier onlyProtocol() {
        if (msg.sender != protocol) revert NotProtocol();

        _;
    }

    /**
     * @notice Constructor.
     * @param protocol_ The address of Protocol
     */
    constructor(
        address protocol_,
        address spogRegistrar_
    ) ContinuousInterestIndexing() ERC20Permit("M Token", "M", 18) {
        protocol = protocol_;
        spogRegistrar = spogRegistrar_;
    }

    /******************************************************************************************************************\
    |                                      External/Public Interactive Functions                                       |
    \******************************************************************************************************************/

    function burn(address account_, uint256 amount_) external onlyProtocol {
        _burn(account_, amount_);
    }

    function mint(address account_, uint256 amount_) external onlyProtocol {
        _mint(account_, amount_);
    }

    function optOutOfEarning() public {
        emit OptedOutOfEarning(msg.sender);
        _hasOptedOutOfEarning[msg.sender] = true;
    }

    function startEarning() external {
        _revertIfNotApprovedEarner(msg.sender);

        _startEarning(msg.sender);
    }

    function startEarning(address account_) external {
        _revertIfNotApprovedEarner(account_);

        if (_hasOptedOutOfEarning[account_]) revert HasOptedOut();

        _startEarning(account_);
    }

    function stopEarning() external {
        optOutOfEarning();
        _stopEarning(msg.sender);
    }

    function stopEarning(address account_) external {
        if (_isApprovedEarner(account_)) revert IsApprovedEarner();

        _stopEarning(account_);
    }

    /******************************************************************************************************************\
    |                                       External/Public View/Pure Functions                                        |
    \******************************************************************************************************************/

    function balanceOf(address account_) external view override returns (uint256 balance_) {
        return _isEarning[account_] ? _getPresentAmount(_balances[account_], currentIndex()) : _balances[account_];
    }

    function earningRate() public view returns (uint256 rate_) {
        return _rate();
    }

    function hasOptedOutOfEarning(address account_) external view returns (bool hasOpted_) {
        return _hasOptedOutOfEarning[account_];
    }

    function isEarning(address account_) external view returns (bool isEarning_) {
        return _isEarning[account_];
    }

    function totalEarningSupply() public view returns (uint256 totalEarningSupply_) {
        return _getPresentAmount(_totalEarningSupplyPrincipal, currentIndex());
    }

    function totalSupply() external view override returns (uint256 totalSupply_) {
        return _totalSupply + totalEarningSupply();
    }

    /******************************************************************************************************************\
    |                                          Internal Interactive Functions                                          |
    \******************************************************************************************************************/

    function _addEarningAmount(address account_, uint256 principalAmount_) internal {
        unchecked {
            _balances[account_] += principalAmount_;
            _totalEarningSupplyPrincipal += principalAmount_;
        }
    }

    function _addNonEarningAmount(address account_, uint256 amount_) internal {
        unchecked {
            _balances[account_] += amount_;
            _totalSupply += amount_;
        }
    }

    function _burn(address account_, uint256 amount_) internal override {
        emit Transfer(account_, address(0), amount_);

        _isEarning[account_]
            ? _subtractEarningAmount(account_, _getPrincipalAmountAndUpdateIndex(amount_))
            : _subtractNonEarningAmount(account_, amount_);
    }

    function _mint(address recipient_, uint256 amount_) internal override {
        emit Transfer(address(0), recipient_, amount_);

        _isEarning[recipient_]
            ? _addEarningAmount(recipient_, _getPrincipalAmountAndUpdateIndex(amount_))
            : _addNonEarningAmount(recipient_, amount_);
    }

    function _startEarning(address account_) internal {
        if (_isEarning[account_]) revert AlreadyEarning();

        uint256 presentAmount_ = _balances[account_];
        uint256 principalAmount_ = _getPrincipalAmountAndUpdateIndex(presentAmount_);

        _balances[account_] = principalAmount_;

        unchecked {
            _totalEarningSupplyPrincipal += principalAmount_;
        }

        _totalSupply -= presentAmount_;

        _isEarning[account_] = true;

        emit StartedEarning(account_);
    }

    function _stopEarning(address account_) internal {
        if (!_isEarning[account_]) revert AlreadyNotEarning();

        uint256 principalAmount_ = _balances[account_];
        uint256 presentAmount_ = _getPresentAmountAndUpdateIndex(principalAmount_);

        _balances[account_] = presentAmount_;

        unchecked {
            _totalSupply += presentAmount_;
        }

        _totalEarningSupplyPrincipal -= principalAmount_;

        _isEarning[account_] = false;

        emit StoppedEarning(account_);
    }

    function _subtractEarningAmount(address account_, uint256 principalAmount_) internal {
        _balances[account_] -= principalAmount_;
        _totalEarningSupplyPrincipal -= principalAmount_;
    }

    function _subtractNonEarningAmount(address account_, uint256 amount_) internal {
        _balances[account_] -= amount_;
        _totalSupply -= amount_;
    }

    function _transfer(address sender_, address recipient_, uint256 amount_) internal override {
        emit Transfer(sender_, recipient_, amount_);

        bool senderIsEarning_ = _isEarning[sender_]; // Only using the sender's earning status more than once.

        // If this is an in-kind transfer, then...
        if (senderIsEarning_ == _isEarning[recipient_]) {
            return
                _transferAmountInKind( // perform an in-kind transfer with...
                    sender_,
                    recipient_,
                    senderIsEarning_ ? _getPrincipalAmountAndUpdateIndex(amount_) : amount_ // the appropriate amount.
                );
        }

        // If this is not an in-kind transfer, then...
        if (senderIsEarning_) {
            // either the sender is earning and the recipient is not, or...
            _subtractEarningAmount(sender_, _getPrincipalAmountAndUpdateIndex(amount_));
            _addNonEarningAmount(recipient_, amount_);
        } else {
            // the sender is not earning and the recipient is.
            _subtractNonEarningAmount(sender_, amount_);
            _addEarningAmount(recipient_, _getPrincipalAmountAndUpdateIndex(amount_));
        }
    }

    function _transferAmountInKind(address sender_, address recipient_, uint256 amount_) internal {
        _balances[sender_] -= amount_;

        unchecked {
            _balances[recipient_] += amount_;
        }
    }

    /******************************************************************************************************************\
    |                                           Internal View/Pure Functions                                           |
    \******************************************************************************************************************/

    function _rate() internal view override returns (uint256 rate_) {
        address rateModel_ = SPOGRegistrarReader.getEarningRateModel(spogRegistrar);

        (bool success_, bytes memory returnData_) = rateModel_.staticcall(
            abi.encodeWithSelector(IInterestRateModel.rate.selector)
        );

        return success_ ? abi.decode(returnData_, (uint256)) : 0;
    }

    function _isApprovedEarner(address account_) internal view returns (bool isApproved_) {
        return
            SPOGRegistrarReader.isEarnersListIgnored(spogRegistrar) ||
            SPOGRegistrarReader.isApprovedEarner(spogRegistrar, account_);
    }

    function _revertIfNotApprovedEarner(address account_) internal view {
        if (!_isApprovedEarner(account_)) revert NotApprovedEarner();
    }
}
