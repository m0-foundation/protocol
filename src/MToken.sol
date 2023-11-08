// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { IInterestRateModel } from "./interfaces/IInterestRateModel.sol";
import { IMToken } from "./interfaces/IMToken.sol";

import { InterestMath } from "./libs/InterestMath.sol";
import { SPOGRegistrarReader } from "./libs/SPOGRegistrarReader.sol";

import { ERC20Permit } from "./ERC20Permit.sol";

// TODO: Explicit opt in an opt out for earning interest trumps.
// TODO: Anyone can opt an account in if they have not yet already explicitly opted out.
// TODO: Globals whitelist on or off.
// TODO: Better names for `startEarningInterest`, `stopEarningInterest`, and all other `interest` in general.
// TODO: Handle variable/dynamic interest rates by `updateInterestIndex()` on all interest earning transfers.
// TODO: Expose `interestEarningTotalSupply`.
// TODO: Consider an optically safer `bur`n via `burn(uint amount_)` where the account is `msg.sender`.

contract MToken is IMToken, ERC20Permit {
    address public immutable protocol;
    address public immutable spogRegistrar;

    uint256 internal _interestEarningTotalSupply;

    // TODO: Consider packing these into a single slot.
    uint256 internal _interestIndex;
    uint256 internal _lastUpdated;

    // TODO: Replace with flag bit in balance.
    mapping(address account => bool isEarningInterest) internal _isEarningInterest;

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
        _interestIndex = 1 * InterestMath.EXP_BASE_SCALE;
        _lastUpdated = block.timestamp;
    }

    /******************************************************************************************************************\
    |                                      External/Public Interactive Functions                                       |
    \******************************************************************************************************************/

    function mint(address account_, uint256 amount_) external onlyProtocol {
        _mint(account_, amount_);
    }

    function burn(address account_, uint amount_) external onlyProtocol {
        _burn(account_, amount_);
    }

    function startEarningInterest() external {
        if (!SPOGRegistrarReader.isApprovedInterestEarner(spogRegistrar, msg.sender)) {
            revert NotApprovedInterestEarner();
        }

        _startEarningInterest(msg.sender);
    }

    function stopEarningInterest() external {
        _stopEarningInterest(msg.sender);
    }

    function stopEarningInterest(address account_) external {
        if (SPOGRegistrarReader.isApprovedInterestEarner(spogRegistrar, account_)) revert IsApprovedInterestEarner();

        _stopEarningInterest(account_);
    }

    function updateInterestIndex() public returns (uint256 currentInterestIndex_) {
        currentInterestIndex_ = _currentInterestIndex();
        _interestIndex = currentInterestIndex_;
        _lastUpdated = block.timestamp;
    }

    /******************************************************************************************************************\
    |                                       External/Public View/Pure Functions                                        |
    \******************************************************************************************************************/

    function balanceOf(address account_) external view override returns (uint256 balance_) {
        return
            _isEarningInterest[account_]
                ? InterestMath.multiply(_balances[account_], _currentInterestIndex())
                : _balances[account_];
    }

    function interestRate() public view returns (uint256 rate_) {
        address rateModel_ = SPOGRegistrarReader.getInterestRateModel(spogRegistrar);

        (bool success_, bytes memory returnData_) = rateModel_.staticcall(
            abi.encodeWithSelector(IInterestRateModel.rate.selector)
        );

        return success_ ? abi.decode(returnData_, (uint256)) : 0;
    }

    function isEarningInterest(address account_) external view returns (bool isEarningInterest_) {
        return _isEarningInterest[account_];
    }

    function totalSupply() external view override returns (uint256 totalSupply_) {
        return _totalSupply + InterestMath.multiply(_interestEarningTotalSupply, _currentInterestIndex());
    }

    /******************************************************************************************************************\
    |                                          Internal Interactive Functions                                          |
    \******************************************************************************************************************/

    function _burn(address account_, uint256 amount_) internal override {
        _decreaseBalance(account_, InterestMath.divide(amount_, _currentInterestIndex()), amount_);

        emit Transfer(account_, address(0), amount_);
    }

    function _mint(address recipient_, uint256 amount_) internal override {
        _increaseBalance(recipient_, InterestMath.divide(amount_, _currentInterestIndex()), amount_);

        emit Transfer(address(0), recipient_, amount_);
    }

    function _startEarningInterest(address account_) internal {
        if (_isEarningInterest[account_]) revert AlreadyEarningInterest();

        uint256 presentAmount_ = _balances[account_];
        uint256 principalAmount_ = InterestMath.divide(presentAmount_, _currentInterestIndex());

        _balances[account_] = principalAmount_;

        unchecked {
            _interestEarningTotalSupply += principalAmount_;
        }

        _totalSupply -= presentAmount_;

        _isEarningInterest[account_] = true;

        emit StartedEarningInterest(account_);
    }

    function _stopEarningInterest(address account_) internal {
        if (!_isEarningInterest[account_]) revert AlreadyNotEarningInterest();

        uint256 principalAmount_ = _balances[account_];
        uint256 presentAmount_ = InterestMath.multiply(principalAmount_, _currentInterestIndex());

        _balances[account_] = presentAmount_;

        unchecked {
            _totalSupply += presentAmount_;
        }

        _interestEarningTotalSupply -= principalAmount_;

        _isEarningInterest[account_] = false;

        emit StoppedEarningInterest(account_);
    }

    function _transfer(address sender_, address recipient_, uint256 amount_) internal override {
        uint256 principalAmount_ = InterestMath.divide(amount_, _currentInterestIndex());

        _decreaseBalance(sender_, principalAmount_, amount_);
        _increaseBalance(recipient_, principalAmount_, amount_);

        emit Transfer(sender_, recipient_, amount_);
    }

    function _decreaseBalance(address account_, uint256 principalAmount_, uint256 presentAmount_) internal {
        if (_isEarningInterest[account_]) {
            _balances[account_] -= principalAmount_;
            _interestEarningTotalSupply -= principalAmount_;
        } else {
            _balances[account_] -= presentAmount_;
            _totalSupply -= presentAmount_;
        }
    }

    function _increaseBalance(address account_, uint256 principalAmount_, uint256 presentAmount_) internal {
        unchecked {
            if (_isEarningInterest[account_]) {
                _balances[account_] += principalAmount_;
                _interestEarningTotalSupply += principalAmount_;
            } else {
                _balances[account_] += presentAmount_;
                _totalSupply += presentAmount_;
            }
        }
    }

    /******************************************************************************************************************\
    |                                           Internal View/Pure Functions                                           |
    \******************************************************************************************************************/

    function _currentInterestIndex() internal view returns (uint256 currentInterestIndex_) {
        return
            InterestMath.multiply(
                _interestIndex,
                InterestMath.getContinuousIndex(
                    InterestMath.convertFromBasisPoints(interestRate()),
                    block.timestamp - _lastUpdated
                )
            );
    }
}
