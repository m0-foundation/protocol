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
    type MBalance is uint256;

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
        if (hasOptedOutOfEarning(account_)) revert HasOptedOut();

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
        _balances[msg.sender] = MBalance.wrap(MBalance.unwrap(_balances[msg.sender]) & ~(uint256(1) << 254));
    }

    /// @inheritdoc IMToken
    function optOutOfEarning() public {
        emit OptedOutOfEarning(msg.sender);
        _balances[msg.sender] = MBalance.wrap(MBalance.unwrap(_balances[msg.sender]) | (1 << 254));
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
        (uint256 earningBit_, , uint128 rawBalance_) = _extract(_balances[account_]);

        return earningBit_ == 0 ? rawBalance_ : _getPresentAmount(rawBalance_);
    }

    /// @inheritdoc IMToken
    function isEarning(address account_) external view returns (bool isEarning_) {
        return (MBalance.unwrap(_balances[account_]) >> 255) != 0;
    }

    /// @inheritdoc IMToken
    function hasOptedOutOfEarning(address account_) public view returns (bool hasOpted_) {
        return ((MBalance.unwrap(_balances[account_]) << 1) >> 255) != 0;
    }

    /******************************************************************************************************************\
    |                                          Internal Interactive Functions                                          |
    \******************************************************************************************************************/

    /**
     * @notice Burns amount of earning or non-earning M from account.
     * @param account_ The account to burn from.
     * @param amount_  The amount to burn.
     */
    function _burn(address account_, uint256 amount_) internal {
        emit Transfer(account_, address(0), amount_);

        if (amount_ == 0) return;

        (uint256 earningBit_, uint256 optOutBit_, uint128 rawBalance_) = _extract(_balances[account_]);

        uint128 presentValue_ = UIntMath.safe128(amount_);

        if (earningBit_ == 0) {
            _balances[account_] = MBalance.wrap(optOutBit_ | (rawBalance_ - presentValue_));

            unchecked {
                _totalNonEarningSupply -= presentValue_;
            }
        } else {
            uint128 principalAmount_ = _getPrincipalAmount(presentValue_);
            _balances[account_] = MBalance.wrap(earningBit_ | optOutBit_ | (rawBalance_ - principalAmount_));

            unchecked {
                _totalPrincipalOfEarningSupply -= principalAmount_;
            }

            updateIndex();
        }
    }

    /**
     * @dev   Mints amount of earning or non-earning M to account.
     * @param recipient_ The account to mint to.
     * @param amount_    The amount to mint.
     */
    function _mint(address recipient_, uint256 amount_) internal {
        emit Transfer(address(0), recipient_, amount_);

        if (amount_ == 0) return;

        (uint256 earningBit_, uint256 optOutBit_, uint128 rawBalance_) = _extract(_balances[recipient_]);

        uint128 presentValue_ = UIntMath.safe128(amount_);

        if (earningBit_ == 0) {
            unchecked {
                _balances[recipient_] = MBalance.wrap(optOutBit_ | (rawBalance_ + presentValue_));
            }

            _totalNonEarningSupply += presentValue_;
        } else {
            uint128 principalAmount_ = _getPrincipalAmount(presentValue_);

            unchecked {
                _balances[recipient_] = MBalance.wrap(earningBit_ | optOutBit_ | (rawBalance_ + principalAmount_));
            }

            _totalPrincipalOfEarningSupply += principalAmount_;

            updateIndex();
        }
    }

    /**
     * @dev   Starts earning for account.
     * @param account_ The account to start earning for.
     */
    function _startEarning(address account_) internal {
        emit StartedEarning(account_);

        (uint256 earningBit_, uint256 optOutBit_, uint128 presentAmount_) = _extract(_balances[account_]);

        if (earningBit_ != 0) return;

        if (presentAmount_ == 0) {
            _balances[account_] = MBalance.wrap((1 << 255) | optOutBit_);
            return;
        }

        uint128 principalAmount_ = _getPrincipalAmount(presentAmount_);

        _balances[account_] = MBalance.wrap((1 << 255) | optOutBit_ | principalAmount_);

        unchecked {
            _totalNonEarningSupply -= presentAmount_;
        }

        unchecked {
            _totalPrincipalOfEarningSupply += principalAmount_;
        }

        updateIndex();
    }

    /**
     * @dev   Stops earning for account.
     * @param account_ The account to stop earning for.
     */
    function _stopEarning(address account_) internal {
        emit StoppedEarning(account_);

        (uint256 earningBit_, uint256 optOutBit_, uint128 principalAmount_) = _extract(_balances[account_]);

        if (earningBit_ == 0) return;

        if (principalAmount_ == 0) {
            _balances[account_] = MBalance.wrap(optOutBit_);
            return;
        }

        uint128 presentAmount_ = _getPresentAmount(principalAmount_);

        _balances[account_] = MBalance.wrap(optOutBit_ | presentAmount_);

        unchecked {
            _totalPrincipalOfEarningSupply -= principalAmount_;
        }

        unchecked {
            _totalNonEarningSupply += presentAmount_;
        }

        updateIndex();
    }

    /**
     * @dev   Transfer M between both earning and non-earning accounts.
     * @param sender_    The account to transfer from. It can be either earning or non-earning account.
     * @param recipient_ The account to transfer to. It can be either earning or non-earning account.
     * @param amount_    The amount to transfer.
     */
    function _transfer(address sender_, address recipient_, uint256 amount_) internal override {
        emit Transfer(sender_, recipient_, amount_);

        (uint256 senderEarningBit_, uint256 senderOptOutBit_, uint128 senderRawBalance_) = _extract(_balances[sender_]);

        (uint256 recipientEarningBit_, uint256 recipientOptOutBit_, uint128 recipientRawBalance_) = _extract(
            _balances[recipient_]
        );

        uint128 presentAmount_ = UIntMath.safe128(amount_);

        uint128 principalAmount_ = (senderEarningBit_ != 0 || recipientEarningBit_ != 0)
            ? _getPrincipalAmount(presentAmount_)
            : 0;

        int256 presentAmountChange_;
        int256 principalAmountChange_;

        if (senderEarningBit_ == 0) {
            _balances[sender_] = MBalance.wrap(senderOptOutBit_ | (senderRawBalance_ - presentAmount_));
            presentAmountChange_ = -int256(uint256(presentAmount_));
        } else {
            _balances[sender_] = MBalance.wrap(
                senderEarningBit_ | senderOptOutBit_ | (senderRawBalance_ - principalAmount_)
            );
            principalAmountChange_ = -int256(uint256(principalAmount_));
        }

        if (recipientEarningBit_ == 0) {
            unchecked {
                _balances[recipient_] = MBalance.wrap(recipientOptOutBit_ | (recipientRawBalance_ + presentAmount_));
                presentAmountChange_ += int256(uint256(presentAmount_));
            }
        } else {
            unchecked {
                _balances[recipient_] = MBalance.wrap(
                    recipientEarningBit_ | recipientOptOutBit_ | (recipientRawBalance_ + principalAmount_)
                );
                principalAmountChange_ += int256(uint256(principalAmount_));
            }
        }

        if (presentAmountChange_ != 0) {
            unchecked {
                _totalNonEarningSupply = uint128(
                    uint256(int256(uint256(_totalNonEarningSupply)) + presentAmountChange_)
                );
            }
        }

        if (principalAmountChange_ != 0) {
            unchecked {
                _totalPrincipalOfEarningSupply = uint128(
                    uint256(int256(uint256(_totalPrincipalOfEarningSupply)) + principalAmountChange_)
                );
            }

            updateIndex();
        }
    }

    /******************************************************************************************************************\
    |                                           Internal View/Pure Functions                                           |
    \******************************************************************************************************************/

    function _extract(MBalance mBalance) internal pure returns (uint256, uint256, uint128) {
        uint256 unwrapped_ = MBalance.unwrap(mBalance);

        return ((unwrapped_ >> 255) << 255, ((unwrapped_ << 1) >> 255) << 254, uint128(unwrapped_));
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
