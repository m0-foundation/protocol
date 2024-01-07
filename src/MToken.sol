// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { ERC20Extended } from "../lib/common/src/ERC20Extended.sol";
import { UIntMath } from "../lib/common/src/libs/UIntMath.sol";

import { IERC20 } from "../lib/common/src/interfaces/IERC20.sol";

import { TTGRegistrarReader } from "./libs/TTGRegistrarReader.sol";

import { IMToken } from "./interfaces/IMToken.sol";
import { IRateModel } from "./interfaces/IRateModel.sol";

import { ContinuousIndexing } from "./abstract/ContinuousIndexing.sol";

/**
 * @title  MToken
 * @author M^0 Labs
 * @notice ERC20 M Token.
 */
contract MToken is IMToken, ContinuousIndexing, ERC20Extended {
    struct MBalance {
        bool isEarning;
        bool hasAllowedEarningOnBehalf;
        uint240 rawBalance; // balance (for a non earning account) or principal balance that accrued interest
    }

    /// @inheritdoc IMToken
    address public immutable minterGateway;

    /// @inheritdoc IMToken
    address public immutable ttgRegistrar;

    /// @dev The total amount of non earning M supply.
    uint240 internal _totalNonEarningSupply;

    /// @dev The principal of the total amount of earning M supply. totalEarningSupply = principal * currentIndex
    uint112 internal _principalOfTotalEarningSupply;

    /// @notice The balance of M for non-earner or principal of earning M balance for earners.
    mapping(address account => MBalance balance) internal _balances;

    /// @dev Modifier to check if caller is Minter Gateway.
    modifier onlyMinterGateway() {
        if (msg.sender != minterGateway) revert NotMinterGateway();

        _;
    }

    /**
     * @notice Constructs the M Token contract.
     * @param  ttgRegistrar_ The address of the TTG Registrar contract.
     * @param  minterGateway_     The address of Minter Gateway.
     */
    constructor(address ttgRegistrar_, address minterGateway_) ContinuousIndexing() ERC20Extended("M Token", "M", 6) {
        if ((ttgRegistrar = ttgRegistrar_) == address(0)) revert ZeroTTGRegistrar();
        if ((minterGateway = minterGateway_) == address(0)) revert ZeroMinterGateway();
    }

    /******************************************************************************************************************\
    |                                      External/Public Interactive Functions                                       |
    \******************************************************************************************************************/

    /// @inheritdoc IMToken
    function mint(address account_, uint256 amount_) external onlyMinterGateway {
        _mint(account_, amount_);
    }

    /// @inheritdoc IMToken
    function burn(address account_, uint256 amount_) external onlyMinterGateway {
        _burn(account_, amount_);
    }

    /// @inheritdoc IMToken
    function startEarning() external {
        _revertIfNotApprovedEarner(msg.sender);
        _startEarning(msg.sender);
    }

    /// @inheritdoc IMToken
    function startEarningOnBehalfOf(address account_) external {
        if (!_balances[account_].hasAllowedEarningOnBehalf) revert HasNotAllowedEarningOnBehalf();

        _revertIfNotApprovedEarner(account_);
        _startEarning(account_);
    }

    /// @inheritdoc IMToken
    function stopEarning() external {
        disallowEarningOnBehalf();
        _stopEarning(msg.sender);
    }

    /// @inheritdoc IMToken
    function stopEarningOnBehalfOf(address account_) external {
        if (_isApprovedEarner(account_)) revert IsApprovedEarner();

        _stopEarning(account_);
    }

    /// @inheritdoc IMToken
    function allowEarningOnBehalf() public {
        emit AllowedEarningOnBehalf(msg.sender);
        _balances[msg.sender].hasAllowedEarningOnBehalf = true;
    }

    /// @inheritdoc IMToken
    function disallowEarningOnBehalf() public {
        emit DisallowedEarningOnBehalf(msg.sender);
        _balances[msg.sender].hasAllowedEarningOnBehalf = false;
    }

    /******************************************************************************************************************\
    |                                       External/Public View/Pure Functions                                        |
    \******************************************************************************************************************/

    /// @inheritdoc IMToken
    function rateModel() public view returns (address rateModel_) {
        return TTGRegistrarReader.getEarnerRateModel(ttgRegistrar);
    }

    /// @inheritdoc IMToken
    function earnerRate() public view returns (uint32 earnerRate_) {
        return _latestRate;
    }

    /// @inheritdoc IMToken
    function totalEarningSupply() public view returns (uint256 totalEarningSupply_) {
        return _getPresentAmount(_principalOfTotalEarningSupply);
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

        return
            mBalance_.isEarning
                ? _getPresentAmount(uint112(mBalance_.rawBalance)) // Treat the raw balance as principal for earner.
                : mBalance_.rawBalance;
    }

    /// @inheritdoc IMToken
    function isEarning(address account_) external view returns (bool isEarning_) {
        return _balances[account_].isEarning;
    }

    /// @inheritdoc IMToken
    function hasAllowedEarningOnBehalf(address account_) external view returns (bool) {
        return _balances[account_].hasAllowedEarningOnBehalf;
    }

    /******************************************************************************************************************\
    |                                          Internal Interactive Functions                                          |
    \******************************************************************************************************************/

    /**
     * @dev   Adds principal to `_balances` of an earning account.
     * @param account_         The account to add principal to.
     * @param principalAmount_ The principal amount to add.
     */
    function _addEarningAmount(address account_, uint112 principalAmount_) internal {
        unchecked {
            _balances[account_].rawBalance += principalAmount_;
            _principalOfTotalEarningSupply += principalAmount_;
        }
    }

    /**
     * @dev   Adds amount to `_balances` of a non-earning account.
     * @param account_ The account to add amount to.
     * @param amount_  The amount to add.
     */
    function _addNonEarningAmount(address account_, uint240 amount_) internal {
        unchecked {
            _balances[account_].rawBalance += amount_;
            _totalNonEarningSupply += amount_;
        }
    }

    /**
     * @dev   Burns amount of earning or non-earning M from account.
     * @param account_ The account to burn from.
     * @param amount_  The present amount to burn.
     */
    function _burn(address account_, uint256 amount_) internal {
        emit Transfer(account_, address(0), amount_);

        if (_balances[account_].isEarning) {
            // NOTE: When burning a present amount, round the principal up in favor of the protocol.
            _subtractEarningAmount(account_, _getPrincipalAmountRoundedUp(UIntMath.safe240(amount_)));
            updateIndex();
        } else {
            _subtractNonEarningAmount(account_, UIntMath.safe240(amount_));
        }
    }

    /**
     * @dev   Mints amount of earning or non-earning M to account.
     * @param recipient_ The account to mint to.
     * @param amount_    The present amount to mint.
     */
    function _mint(address recipient_, uint256 amount_) internal {
        emit Transfer(address(0), recipient_, amount_);

        if (_balances[recipient_].isEarning) {
            // NOTE: When minting a present amount, round the principal down in favor of the protocol.
            _addEarningAmount(recipient_, _getPrincipalAmountRoundedDown(UIntMath.safe240(amount_)));
            updateIndex();
        } else {
            _addNonEarningAmount(recipient_, UIntMath.safe240(amount_));
        }
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

        // Treat the raw balance as present amount for non earner.
        uint240 amount_ = _balances[account_].rawBalance;

        if (amount_ == 0) return;

        // NOTE: When converting a non-earning balance into an earning balance, round the principal down in favor of
        //       the Minter Gateway.
        uint112 principalAmount_ = _getPrincipalAmountRoundedDown(amount_);

        _balances[account_].rawBalance = principalAmount_;

        unchecked {
            _principalOfTotalEarningSupply += principalAmount_;
            _totalNonEarningSupply -= amount_;
        }

        updateIndex();
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

        // Treat the raw balance as principal for earner.
        uint112 principalAmount_ = uint112(_balances[account_].rawBalance);

        if (principalAmount_ == 0) return;

        uint240 amount_ = _getPresentAmount(principalAmount_);

        _balances[account_].rawBalance = amount_;

        unchecked {
            _totalNonEarningSupply += amount_;
            _principalOfTotalEarningSupply -= principalAmount_;
        }

        updateIndex();
    }

    /**
     * @dev   Subtracts principal from `_balances` of an earning account.
     * @param account_         The account to subtract principal from.
     * @param principalAmount_ The principal amount to subtract.
     */
    function _subtractEarningAmount(address account_, uint112 principalAmount_) internal {
        _balances[account_].rawBalance -= principalAmount_;

        unchecked {
            _principalOfTotalEarningSupply -= principalAmount_;
        }
    }

    /**
     * @dev   Subtracts amount from `_balances` of a non-earning account.
     * @param account_ The account to subtract amount from.
     * @param amount_  The amount to subtract.
     */
    function _subtractNonEarningAmount(address account_, uint240 amount_) internal {
        _balances[account_].rawBalance -= amount_;

        unchecked {
            _totalNonEarningSupply -= amount_;
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

        uint240 safeAmount_ = UIntMath.safe240(amount_);

        bool senderIsEarning_ = _balances[sender_].isEarning; // Only using the sender's earning status more than once.

        // If this is an in-kind transfer, then...
        if (senderIsEarning_ == _balances[recipient_].isEarning) {
            // NOTE: When subtracting a present amount from an earner, round the principal up in favor of the protocol.
            return
                _transferAmountInKind( // perform an in-kind transfer with...
                    sender_,
                    recipient_,
                    senderIsEarning_ ? _getPrincipalAmountRoundedUp(safeAmount_) : safeAmount_ // the appropriate amount.
                );
        }

        // If this is not an in-kind transfer, then...
        if (senderIsEarning_) {
            // either the sender is earning and the recipient is not, or...
            // NOTE: When subtracting a present amount from an earner, round the principal up in favor of the protocol.
            _subtractEarningAmount(sender_, _getPrincipalAmountRoundedUp(safeAmount_));
            _addNonEarningAmount(recipient_, safeAmount_);
        } else {
            // the sender is not earning and the recipient is.
            // NOTE: When adding a present amount to an earner, round the principal down in favor of the protocol.
            _subtractNonEarningAmount(sender_, safeAmount_);
            _addEarningAmount(recipient_, _getPrincipalAmountRoundedDown(safeAmount_));
        }

        updateIndex();
    }

    /**
     * @dev   Transfer M between same earning status accounts.
     * @param sender_    The account to transfer from.
     * @param recipient_ The account to transfer to.
     * @param amount_    The amount (present or principal) to transfer.
     */
    function _transferAmountInKind(address sender_, address recipient_, uint240 amount_) internal {
        _balances[sender_].rawBalance -= amount_;

        unchecked {
            _balances[recipient_].rawBalance += amount_;
        }
    }

    /******************************************************************************************************************\
    |                                           Internal View/Pure Functions                                           |
    \******************************************************************************************************************/

    /**
     * @dev   Returns the present amount (rounded down) given the principal amount, using the current index.
     *        All present amounts are rounded down in favor of the protocol.
     * @param principalAmount_ The principal amount.
     */
    function _getPresentAmount(uint112 principalAmount_) internal view returns (uint240 amount_) {
        return _getPresentAmount(principalAmount_, currentIndex());
    }

    /**
     * @dev   Returns the present amount (rounded down) given the principal amount and an index.
     *        All present amounts are rounded down in favor of the protocol, since they are assets.
     * @param principalAmount_ The principal amount.
     * @param index_           An index
     */
    function _getPresentAmount(uint112 principalAmount_, uint128 index_) internal pure returns (uint240 amount_) {
        return _getPresentAmountRoundedDown(principalAmount_, index_);
    }

    /**
     * @dev    Checks if earner was approved by TTG.
     * @param  account_    The account to check.
     * @return isApproved_ True if approved, false otherwise.
     */
    function _isApprovedEarner(address account_) internal view returns (bool isApproved_) {
        return
            TTGRegistrarReader.isEarnersListIgnored(ttgRegistrar) ||
            TTGRegistrarReader.isApprovedEarner(ttgRegistrar, account_);
    }

    /**
     * @dev    Gets the current earner rate from TTG approved rate model contract.
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
