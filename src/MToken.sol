// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { ERC20Permit } from "../lib/common/src/ERC20Permit.sol";

import { IERC20 } from "../lib/common/src/interfaces/IERC20.sol";

import { SPOGRegistrarReader } from "./libs/SPOGRegistrarReader.sol";
import { UIntMath } from "./libs/UIntMath.sol";

import { IMToken } from "./interfaces/IMToken.sol";
import { IRateModel } from "./interfaces/IRateModel.sol";

import { ContinuousIndexing } from "./ContinuousIndexing.sol";

// TODO: Consider an socially/optically "safer" `burn` via `burn(uint amount_)` where the account is `msg.sender`.
// TODO: Some mechanism that allows a UI/script to determine how much an account or the system stands to gain from
//       calling `updateIndex()`.
// TODO: Some increased/decreased earning supply event(s)? Might be useful for a UI/script, or useless in general.

/**
 * @title MToken
 * @author M^ZERO LABS_
 * @notice ERC20 M Token.
 */
contract MToken is IMToken, ContinuousIndexing, ERC20Permit {
    /// @inheritdoc IMToken
    address public immutable protocol;

    /// @inheritdoc IMToken
    address public immutable spogRegistrar;

    /// @dev The total amount of non earning M supply.
    uint128 internal _totalNonEarningSupply;

    /// @dev The total amount of principal of earning M supply. totalEarningSupply = principal * currentIndex
    uint128 internal _totalPrincipalOfEarningSupply;

    /// @notice The balance of M for non-earner or principal of earning M balance for earners.
    mapping(address account => uint128 balance) internal _balances;

    /// @dev Defines if account is an earner - allowed by SPOG and explicitly called `startEarning`.
    // TODO: Consider replace with flag bit/byte in balance.
    mapping(address account => bool isEarning) internal _isEarning;

    /// @dev Checks if account has opted out of earning.
    // TODO: Consider replace with flag bit/byte in balance.
    mapping(address account => bool hasOptedOutOfEarning) internal _hasOptedOutOfEarning;

    modifier onlyProtocol() {
        if (msg.sender != protocol) revert NotProtocol();

        _;
    }

    /**
     * @notice Constructor.
     * @param  spogRegistrar_ The address of the SPOG Registrar contract.
     * @param  protocol_      The address of Protocol.
     */
    constructor(address spogRegistrar_, address protocol_) ContinuousIndexing() ERC20Permit("M Token", "M", 6) {
        spogRegistrar = spogRegistrar_;
        protocol = protocol_;
    }

    /******************************************************************************************************************\
    |                                      External/Public Interactive Functions                                       |
    \******************************************************************************************************************/

    /// @inheritdoc IMToken
    function mint(address account_, uint256 amount_) external onlyProtocol {
        _mint(account_, amount_);
    }

    /// @inheritdoc IMToken
    function burn(address account_, uint256 amount_) external onlyProtocol {
        _burn(account_, amount_);
    }

    /// @inheritdoc IMToken
    function startEarning() external {
        _revertIfNotApprovedEarner(msg.sender);
        _startEarning(msg.sender);
    }

    /// @inheritdoc IMToken
    function startEarning(address account_) external {
        if (_hasOptedOutOfEarning[account_]) revert HasOptedOut();

        _revertIfNotApprovedEarner(account_);
        _startEarning(account_);
    }

    /// @inheritdoc IMToken
    function stopEarning() external {
        optOutOfEarning();
        _stopEarning(msg.sender);
    }

    /// @inheritdoc IMToken
    function stopEarning(address account_) external {
        if (_isApprovedEarner(account_)) revert IsApprovedEarner();

        _stopEarning(account_);
    }

    /// @inheritdoc IMToken
    function optInToEarning() public {
        emit OptedInToEarning(msg.sender);
        _hasOptedOutOfEarning[msg.sender] = false;
    }

    /// @inheritdoc IMToken
    function optOutOfEarning() public {
        emit OptedOutOfEarning(msg.sender);
        _hasOptedOutOfEarning[msg.sender] = true;
    }

    /******************************************************************************************************************\
    |                                       External/Public View/Pure Functions                                        |
    \******************************************************************************************************************/

    /// @inheritdoc IMToken
    function rateModel() public view returns (address rateModel_) {
        return SPOGRegistrarReader.getEarnerRateModel(spogRegistrar);
    }

    /// @inheritdoc IMToken
    function earnerRate() public view returns (uint32 earnerRate_) {
        return _latestRate;
    }

    /// @inheritdoc IMToken
    function totalEarningSupply() public view returns (uint256 totalEarningSupply_) {
        return _getPresentAmount(_totalPrincipalOfEarningSupply, currentIndex());
    }

    /// @inheritdoc IMToken
    function totalNonEarningSupply() external view returns (uint256 totalNonEarningSupply_) {
        return _totalNonEarningSupply;
    }

    /// @inheritdoc IERC20
    function totalSupply() external view returns (uint256 totalSupply_) {
        unchecked {
            return _totalNonEarningSupply + totalEarningSupply();
        }
    }

    /// @inheritdoc IERC20
    function balanceOf(address account_) external view returns (uint256 balance_) {
        return _isEarning[account_] ? _getPresentAmount(_balances[account_], currentIndex()) : _balances[account_];
    }

    /// @inheritdoc IMToken
    function isEarning(address account_) external view returns (bool isEarning_) {
        return _isEarning[account_];
    }

    /// @inheritdoc IMToken
    function hasOptedOutOfEarning(address account_) external view returns (bool hasOpted_) {
        return _hasOptedOutOfEarning[account_];
    }

    /******************************************************************************************************************\
    |                                          Internal Interactive Functions                                          |
    \******************************************************************************************************************/

    /**
     * @dev   Adds principal to `_balances` of an earning account.
     * @param account_         The account to add principal to.
     * @param principalAmount_ The principal amount to add.
     */
    function _addEarningAmount(address account_, uint128 principalAmount_) internal {
        unchecked {
            _balances[account_] += principalAmount_;
            _totalPrincipalOfEarningSupply += principalAmount_;
        }
    }

    /**
     * @dev   Adds amount to `_balances` of a non-earning account.
     * @param account_ The account to add amount to.
     * @param amount_  The amount to add.
     */
    function _addNonEarningAmount(address account_, uint128 amount_) internal {
        unchecked {
            _balances[account_] += amount_;
            _totalNonEarningSupply += amount_;
        }
    }

    /**
     * @dev   Burns amount of earning or non-earning M from account.
     * @param account_ The account to burn from.
     * @param amount_  The amount to burn.
     */
    function _burn(address account_, uint256 amount_) internal {
        emit Transfer(account_, address(0), amount_);

        _isEarning[account_]
            ? _subtractEarningAmount(account_, _getPrincipalAmountAndUpdateIndex(UIntMath.safe128(amount_)))
            : _subtractNonEarningAmount(account_, UIntMath.safe128(amount_));
    }

    /**
     * @dev   Mints amount of earning or non-earning M to account.
     * @param recipient_ The account to mint to.
     * @param amount_    The amount to mint.
     */
    function _mint(address recipient_, uint256 amount_) internal {
        emit Transfer(address(0), recipient_, amount_);

        _isEarning[recipient_]
            ? _addEarningAmount(recipient_, _getPrincipalAmountAndUpdateIndex(UIntMath.safe128(amount_)))
            : _addNonEarningAmount(recipient_, UIntMath.safe128(amount_));
    }

    /**
     * @dev   Starts earning for account.
     * @param account_ The account to start earning for.
     */
    function _startEarning(address account_) internal {
        emit StartedEarning(account_);

        if (_isEarning[account_]) return;

        _isEarning[account_] = true;

        uint128 presentAmount_ = _balances[account_];

        if (presentAmount_ == 0) return;

        uint128 principalAmount_ = _getPrincipalAmountAndUpdateIndex(presentAmount_);

        _balances[account_] = principalAmount_;

        unchecked {
            _totalPrincipalOfEarningSupply += principalAmount_;
            _totalNonEarningSupply -= presentAmount_;
        }
    }

    /**
     * @dev   Stops earning for account.
     * @param account_ The account to stop earning for.
     */
    function _stopEarning(address account_) internal {
        emit StoppedEarning(account_);

        if (!_isEarning[account_]) return;

        _isEarning[account_] = false;

        uint128 principalAmount_ = _balances[account_];

        if (principalAmount_ == 0) return;

        uint128 presentAmount_ = _getPresentAmountAndUpdateIndex(principalAmount_);

        _balances[account_] = presentAmount_;

        unchecked {
            _totalNonEarningSupply += presentAmount_;
            _totalPrincipalOfEarningSupply -= principalAmount_;
        }
    }

    /**
     * @dev   Subtracts principal from `_balances` of an earning account.
     * @param account_         The account to subtract principal from.
     * @param principalAmount_ The principal amount to subtract.
     */
    function _subtractEarningAmount(address account_, uint128 principalAmount_) internal {
        _balances[account_] -= principalAmount_;

        unchecked {
            _totalPrincipalOfEarningSupply -= principalAmount_;
        }
    }

    /**
     * @dev   Subtracts amount from `_balances` of a non-earning account.
     * @param account_ The account to subtract amount from.
     * @param amount_  The amount to subtract.
     */
    function _subtractNonEarningAmount(address account_, uint128 amount_) internal {
        _balances[account_] -= amount_;

        unchecked {
            _totalNonEarningSupply -= amount_;
        }
    }

    /**
     * @dev   Transfer M between both earning and non-earning accounts.
     * @param sender_    The account to transfer from. It can be either earning or non-earning account.
     * @param recipient_ The account to transfer to. It can be either earning or non-earning account.
     * @param amount_    The amount to transfer.
     */
    function _transfer(address sender_, address recipient_, uint256 amount_) internal override {
        emit Transfer(sender_, recipient_, amount_);

        uint128 presentAmount_ = UIntMath.safe128(amount_);

        bool senderIsEarning_ = _isEarning[sender_]; // Only using the sender's earning status more than once.

        // If this is an in-kind transfer, then...
        if (senderIsEarning_ == _isEarning[recipient_]) {
            return
                _transferAmountInKind( // perform an in-kind transfer with...
                    sender_,
                    recipient_,
                    senderIsEarning_ ? _getPrincipalAmount(presentAmount_, currentIndex()) : presentAmount_ // the appropriate amount.
                );
        }

        // If this is not an in-kind transfer, then...
        if (senderIsEarning_) {
            // either the sender is earning and the recipient is not, or...
            _subtractEarningAmount(sender_, _getPrincipalAmountAndUpdateIndex(presentAmount_));
            _addNonEarningAmount(recipient_, presentAmount_);
        } else {
            // the sender is not earning and the recipient is.
            _subtractNonEarningAmount(sender_, presentAmount_);
            _addEarningAmount(recipient_, _getPrincipalAmountAndUpdateIndex(presentAmount_));
        }
    }

    /**
     * @dev   Transfer M between same earning status accounts.
     * @param sender_    The account to transfer from.
     * @param recipient_ The account to transfer to.
     * @param amount_    The amount to transfer.
     */
    function _transferAmountInKind(address sender_, address recipient_, uint128 amount_) internal {
        _balances[sender_] -= amount_;

        unchecked {
            _balances[recipient_] += amount_;
        }
    }

    /******************************************************************************************************************\
    |                                           Internal View/Pure Functions                                           |
    \******************************************************************************************************************/

    /**
     * @dev    Checks if earner was approved by SPOG.
     * @param  account_    The account to check.
     * @return isApproved_ True if approved, false otherwise.
     */
    function _isApprovedEarner(address account_) internal view returns (bool isApproved_) {
        return
            SPOGRegistrarReader.isEarnersListIgnored(spogRegistrar) ||
            SPOGRegistrarReader.isApprovedEarner(spogRegistrar, account_);
    }

    /**
     * @dev    Gets the current earner rate from Spog approved rate model contract.
     * @return rate_ The current earner rate.
     */
    function _rate() internal view override returns (uint32 rate_) {
        (bool success_, bytes memory returnData_) = rateModel().staticcall(
            abi.encodeWithSelector(IRateModel.rate.selector)
        );

        rate_ = (success_ && returnData_.length >= 32) ? UIntMath.bound32(abi.decode(returnData_, (uint256))) : 0;
    }

    /**
     * @dev   Reverts if account is not approved earner.
     * @param account_ The account to check.
     */
    function _revertIfNotApprovedEarner(address account_) internal view {
        if (!_isApprovedEarner(account_)) revert NotApprovedEarner();
    }
}
