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
    struct MBalance {
        bool isEarning;
        bool hasOptedOutOfEarning;
        uint128 rawBalance;
    }

    /// @inheritdoc IMToken
    address public immutable protocol;

    /// @inheritdoc IMToken
    address public immutable spogRegistrar;

    /// @dev The total amount of non earning M supply.
    uint128 internal _totalNonEarningSupply;

    /// @dev The total amount of principal of earning M supply. totalEarningSupply = principal * currentIndex
    uint128 internal _totalPrincipalOfEarningSupply;

    /// @notice The balance of M for non-earner or principal of earning M balance for earners.
    mapping(address account => MBalance balance) internal _balances;

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
        if (_balances[account_].hasOptedOutOfEarning) revert HasOptedOut();

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
        _balances[msg.sender].hasOptedOutOfEarning = false;
    }

    /// @inheritdoc IMToken
    function optOutOfEarning() public {
        emit OptedOutOfEarning(msg.sender);
        _balances[msg.sender].hasOptedOutOfEarning = true;
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
        return _getPresentAmount(_totalPrincipalOfEarningSupply);
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
        MBalance storage mBalance_ = _balances[account_];

        return mBalance_.isEarning ? _getPresentAmount(mBalance_.rawBalance) : mBalance_.rawBalance;
    }

    /// @inheritdoc IMToken
    function isEarning(address account_) external view returns (bool isEarning_) {
        return _balances[account_].isEarning;
    }

    /// @inheritdoc IMToken
    function hasOptedOutOfEarning(address account_) external view returns (bool hasOpted_) {
        return _balances[account_].hasOptedOutOfEarning;
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
            _balances[account_].rawBalance += principalAmount_;
            _totalPrincipalOfEarningSupply += principalAmount_;
        }
    }

    /**
     * @dev   Adds amount to `_balances` of a non-earning account.
     * @param account_       The account to add amount to.
     * @param presentAmount_ The present amount to add.
     */
    function _addNonEarningAmount(address account_, uint128 presentAmount_) internal {
        unchecked {
            _balances[account_].rawBalance += presentAmount_;
            _totalNonEarningSupply += presentAmount_;
        }
    }

    /**
     * @dev   Burns amount of earning or non-earning M from account.
     * @param account_ The account to burn from.
     * @param amount_  The present amount to burn.
     */
    function _burn(address account_, uint256 amount_) internal {
        emit Transfer(account_, address(0), amount_);

        // NOTE: When burning a present amount, round the principal up to favour of the protocol.
        _balances[account_].isEarning
            ? _subtractEarningAmount(account_, _getPrincipalAmountRoundedUp(UIntMath.safe128(amount_), updateIndex()))
            : _subtractNonEarningAmount(account_, UIntMath.safe128(amount_));
    }

    /**
     * @dev   Mints amount of earning or non-earning M to account.
     * @param recipient_ The account to mint to.
     * @param amount_    The present amount to mint.
     */
    function _mint(address recipient_, uint256 amount_) internal {
        emit Transfer(address(0), recipient_, amount_);

        // NOTE: When minting a present amount, round the principal down to favour of the protocol.
        _balances[recipient_].isEarning
            ? _addEarningAmount(recipient_, _getPrincipalAmountRoundedDown(UIntMath.safe128(amount_), updateIndex()))
            : _addNonEarningAmount(recipient_, UIntMath.safe128(amount_));
    }

    /**
     * @dev   Starts earning for account.
     * @param account_ The account to start earning for.
     */
    function _startEarning(address account_) internal {
        emit StartedEarning(account_);

        MBalance storage mBalance_ = _balances[account_];

        if (mBalance_.isEarning) return;

        mBalance_.isEarning = true;

        uint128 presentAmount_ = _balances[account_].rawBalance;

        if (presentAmount_ == 0) return;

        // NOTE: When converting a non-earning balance into an earning balance, round the principal down in favour of
        //       the protocol.
        uint128 principalAmount_ = _getPrincipalAmountRoundedDown(presentAmount_, updateIndex());

        _balances[account_].rawBalance = principalAmount_;

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

        MBalance storage mBalance_ = _balances[account_];

        if (!mBalance_.isEarning) return;

        mBalance_.isEarning = false;

        uint128 principalAmount_ = _balances[account_].rawBalance;

        if (principalAmount_ == 0) return;

        uint128 presentAmount_ = _getPresentAmount(principalAmount_, updateIndex());

        _balances[account_].rawBalance = presentAmount_;

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
        _balances[account_].rawBalance -= principalAmount_;

        unchecked {
            _totalPrincipalOfEarningSupply -= principalAmount_;
        }
    }

    /**
     * @dev   Subtracts amount from `_balances` of a non-earning account.
     * @param account_       The account to subtract amount from.
     * @param presentAmount_ The present amount to subtract.
     */
    function _subtractNonEarningAmount(address account_, uint128 presentAmount_) internal {
        _balances[account_].rawBalance -= presentAmount_;

        unchecked {
            _totalNonEarningSupply -= presentAmount_;
        }
    }

    /**
     * @dev   Transfer M between both earning and non-earning accounts.
     * @param sender_    The account to transfer from. It can be either earning or non-earning account.
     * @param recipient_ The account to transfer to. It can be either earning or non-earning account.
     * @param amount_    The present amount to transfer.
     */
    function _transfer(address sender_, address recipient_, uint256 amount_) internal override {
        emit Transfer(sender_, recipient_, amount_);

        uint128 presentAmount_ = UIntMath.safe128(amount_);

        bool senderIsEarning_ = _balances[sender_].isEarning; // Only using the sender's earning status more than once.

        // If this is an in-kind transfer, then...
        if (senderIsEarning_ == _balances[recipient_].isEarning) {
            // NOTE: When subtracting a present value from an earner, round the principal up in favour of the protocol.
            return
                _transferAmountInKind( // perform an in-kind transfer with...
                    sender_,
                    recipient_,
                    senderIsEarning_ ? _getPrincipalAmountRoundedUp(presentAmount_) : presentAmount_ // the appropriate amount.
                );
        }

        // If this is not an in-kind transfer, then...
        if (senderIsEarning_) {
            // either the sender is earning and the recipient is not, or...
            // NOTE: When subtracting a present value from an earner, round the principal up in favour of the protocol.
            _subtractEarningAmount(sender_, _getPrincipalAmountRoundedUp(presentAmount_, updateIndex()));
            _addNonEarningAmount(recipient_, presentAmount_);
        } else {
            // the sender is not earning and the recipient is.
            // NOTE: When adding a present value to an earner, round the principal down in favour of the protocol.
            _subtractNonEarningAmount(sender_, presentAmount_);
            _addEarningAmount(recipient_, _getPrincipalAmountRoundedDown(presentAmount_, updateIndex()));
        }
    }

    /**
     * @dev   Transfer M between same earning status accounts.
     * @param sender_    The account to transfer from.
     * @param recipient_ The account to transfer to.
     * @param amount_    The amount (present or principal) to transfer.
     */
    function _transferAmountInKind(address sender_, address recipient_, uint128 amount_) internal {
        _balances[sender_].rawBalance -= amount_;

        unchecked {
            _balances[recipient_].rawBalance += amount_;
        }
    }

    /******************************************************************************************************************\
    |                                           Internal View/Pure Functions                                           |
    \******************************************************************************************************************/

    /**
     * @dev   Returns the present value (rounded down) given the principal value, using the current index.
     *        All present values are rounded down in favour of the protocol.
     * @param principalAmount_ The principal value.
     */
    function _getPresentAmount(uint128 principalAmount_) internal view returns (uint128 presentValue_) {
        return _getPresentAmount(principalAmount_, currentIndex());
    }

    /**
     * @dev   Returns the present value (rounded down) given the principal value and an index.
     *        All present values are rounded down in favour of the protocol, since they are assets.
     * @param principalAmount_ The principal value.
     * @param index_           An index
     */
    function _getPresentAmount(uint128 principalAmount_, uint128 index_) internal pure returns (uint128 presentValue_) {
        return _getPresentAmountRoundedDown(principalAmount_, index_);
    }

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
