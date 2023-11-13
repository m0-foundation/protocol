// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { IInterestRateModel } from "./interfaces/IInterestRateModel.sol";
import { IMToken } from "./interfaces/IMToken.sol";

import { InterestMath } from "./libs/InterestMath.sol";
import { SPOGRegistrarReader } from "./libs/SPOGRegistrarReader.sol";

import { ERC20Permit } from "./ERC20Permit.sol";

// TODO: Consider an socially/optically "safer" `burn` via `burn(uint amount_)` where the account is `msg.sender`.
// TODO: Some mechanism that allows a UI/script to determine how much an account or the system stands to gain from
//       calling `updateIndex()`.
// TODO: Some increased/decreased earning supply event(s)? Might be useful for a UI/script, or useless in general.
// TODO: Is an `indexUpdated` event useful?

contract MToken is IMToken, ERC20Permit {
    address public immutable protocol;
    address public immutable spogRegistrar;

    uint256 internal _totalEarningSupplyPrincipal;

    // TODO: Consider packing these into a single slot.
    uint256 internal _index;
    uint256 internal _lastUpdated;

    // TODO: Consider replace with flag bit/byte in balance.
    mapping(address account => bool isEarning) internal _isEarning;

    // TODO: Consider replace with flag bit/byte in balance.
    mapping(address account => bool hasOptedOut) internal _hasOptedOut;

    modifier onlyProtocol() {
        if (msg.sender != protocol) revert NotProtocol();

        _;
    }

    /**
     * @notice Constructor.
     * @param protocol_ The address of Protocol
     */
    constructor(address protocol_, address spogRegistrar_) ERC20Permit("M Token", "M", 18) {
        protocol = protocol_;
        spogRegistrar = spogRegistrar_;
        _index = 1 * InterestMath.EXP_BASE_SCALE;
        _lastUpdated = block.timestamp;
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

    function startEarning() external {
        _revertIfNotApprovedEarner(msg.sender);

        _startEarning(msg.sender);
    }

    function startEarning(address account_) external {
        _revertIfNotApprovedEarner(account_);

        if (_hasOptedOut[account_]) revert HasOptedOut();

        _startEarning(account_);
    }

    function stopEarning() external {
        _hasOptedOut[msg.sender] = true;
        _stopEarning(msg.sender);
    }

    function stopEarning(address account_) external {
        if (_isApprovedEarner(account_)) revert IsApprovedEarner();

        _stopEarning(account_);
    }

    function updateIndex() public returns (uint256 currentIndex_) {
        currentIndex_ = _currentIndex();
        _index = currentIndex_;
        _lastUpdated = block.timestamp;
    }

    /******************************************************************************************************************\
    |                                       External/Public View/Pure Functions                                        |
    \******************************************************************************************************************/

    function balanceOf(address account_) external view override returns (uint256 balance_) {
        return _isEarning[account_] ? InterestMath.multiply(_balances[account_], _currentIndex()) : _balances[account_];
    }

    function earningRate() public view returns (uint256 rate_) {
        address rateModel_ = SPOGRegistrarReader.getEarningRateModel(spogRegistrar);

        (bool success_, bytes memory returnData_) = rateModel_.staticcall(
            abi.encodeWithSelector(IInterestRateModel.rate.selector)
        );

        return success_ ? abi.decode(returnData_, (uint256)) : 0;
    }

    function hasOptedOut(address account_) external view returns (bool hasOpted_) {
        return _hasOptedOut[account_];
    }

    function isEarning(address account_) external view returns (bool isEarning_) {
        return _isEarning[account_];
    }

    function totalEarningSupply() public view returns (uint256 totalEarningSupply_) {
        return InterestMath.multiply(_totalEarningSupplyPrincipal, _currentIndex());
    }

    function totalSupply() external view override returns (uint256 totalSupply_) {
        return _totalSupply + totalEarningSupply();
    }

    /******************************************************************************************************************\
    |                                          Internal Interactive Functions                                          |
    \******************************************************************************************************************/

    function _addEarningAmount(address account_, uint256 amount_) internal {
        unchecked {
            _balances[account_] += amount_;
            _totalEarningSupplyPrincipal += amount_;
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

    function _getPrincipalAmountAndUpdateIndex(uint256 amount_) internal returns (uint256 principalAmount_) {
        return InterestMath.divide(amount_, updateIndex());
    }

    function _getPresentAmountAndUpdateIndex(uint256 amount_) internal returns (uint256 presentAmount_) {
        return InterestMath.multiply(amount_, updateIndex());
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

    function _subtractEarningAmount(address account_, uint256 amount_) internal {
        _balances[account_] -= amount_;
        _totalEarningSupplyPrincipal -= amount_;
    }

    function _subtractNonEarningAmount(address account_, uint256 amount_) internal {
        _balances[account_] -= amount_;
        _totalSupply -= amount_;
    }

    function _transfer(address sender_, address recipient_, uint256 amount_) internal override {
        emit Transfer(sender_, recipient_, amount_);

        bool senderIsEarning_ = _isEarning[sender_];
        bool recipientIsEarning_ = _isEarning[recipient_];

        if (!senderIsEarning_ && !recipientIsEarning_) return _transferAmountInKind(sender_, recipient_, amount_);

        uint256 principalAmount_ = _getPrincipalAmountAndUpdateIndex(amount_);

        if (!senderIsEarning_ && recipientIsEarning_) {
            _subtractNonEarningAmount(sender_, amount_);
            _addEarningAmount(recipient_, principalAmount_);

            return;
        }

        if (!recipientIsEarning_) {
            _subtractEarningAmount(sender_, principalAmount_);
            _addNonEarningAmount(recipient_, amount_);

            return;
        }

        _transferAmountInKind(sender_, recipient_, principalAmount_);
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

    function _currentIndex() internal view returns (uint256 currentIndex_) {
        return
            InterestMath.multiply(
                _index,
                InterestMath.getContinuousIndex(
                    InterestMath.convertFromBasisPoints(earningRate()),
                    block.timestamp - _lastUpdated
                )
            );
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
