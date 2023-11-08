// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { ERC20Helper } from "../lib/erc20-helper/src/ERC20Helper.sol";

import { IMToken } from "./interfaces/IMToken.sol";
import { IMStakingToken } from "./interfaces/IMStakingToken.sol";

import { InterestMath } from "./libs/InterestMath.sol";

import { ERC20Permit } from "./ERC20Permit.sol";
import { ERC712 } from "./ERC712.sol";

abstract contract MStakingToken is IMStakingToken, ERC20Permit {
    uint256 internal _stakingIndex;
    uint256 internal _lastUpdated;

    address internal immutable _stakedToken;

    mapping(address account => uint256 index) internal _stakingIndices;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address stakedToken_
    ) ERC20Permit(name_, symbol_, decimals_) {
        _stakedToken = stakedToken_;
    }

    /******************************************************************************************************************\
    |                                      External/Public Interactive Functions                                       |
    \******************************************************************************************************************/

    function stake(uint256 amount_) external {
        uint256 currentStakingIndex_ = update();
        uint256 principalAmount_ = InterestMath.divide(amount_, currentStakingIndex_);

        _mint(msg.sender, principalAmount_);

        IMToken(_stakedToken).burn(msg.sender, amount_);
    }

    function withdraw(uint256 amount_, address destination_) external {
        uint256 currentStakingIndex_ = update();
        uint256 principalAmount_ = InterestMath.divide(amount_, currentStakingIndex_);

        _burn(msg.sender, principalAmount_);

        IMToken(_stakedToken).mint(destination_, amount_);
    }

    function update() public returns (uint256 currentStakingIndex_) {
        currentStakingIndex_ = _stakingIndex = _getCurrentStakingIndex();
        _lastUpdated = block.timestamp;
    }

    /******************************************************************************************************************\
    |                                       External/Public View/Pure Functions                                        |
    \******************************************************************************************************************/

    function balanceOf(address account_) external view override returns (uint256 balance_) {
        return InterestMath.multiply(_balances[account_], _getCurrentStakingIndex());
    }

    function totalSupply() external view override returns (uint256 totalSupply_) {
        return InterestMath.multiply(_totalSupply, _getCurrentStakingIndex());
    }

    /******************************************************************************************************************\
    |                                          Internal Interactive Functions                                          |
    \******************************************************************************************************************/

    function _burn(address account_, uint256 amount_) internal override {
        uint256 currentStakingIndex_ = update();
        uint256 principalAmount_ = InterestMath.divide(amount_, currentStakingIndex_);

        _balances[account_] -= principalAmount_;
        _totalSupply -= principalAmount_;

        emit Transfer(account_, address(0), amount_);
    }

    function _mint(address recipient_, uint256 amount_) internal override {
        uint256 currentStakingIndex_ = update();
        uint256 principalAmount_ = InterestMath.divide(amount_, currentStakingIndex_);

        _balances[recipient_] += principalAmount_;
        _totalSupply += principalAmount_;

        emit Transfer(address(0), recipient_, amount_);
    }

    function _transfer(address sender_, address recipient_, uint256 amount_) internal override {
        uint256 currentStakingIndex_ = update();
        uint256 principalAmount_ = InterestMath.divide(amount_, currentStakingIndex_);

        _balances[sender_] -= principalAmount_;
        _balances[recipient_] += principalAmount_;

        emit Transfer(sender_, recipient_, amount_);
    }

    /******************************************************************************************************************\
    |                                           Internal View/Pure Functions                                           |
    \******************************************************************************************************************/

    function _getCurrentStakingIndex() internal view returns (uint256 currentStakingIndex_) {
        return
            InterestMath.multiply(
                _stakingIndex,
                InterestMath.getContinuousRate(_getStakingRate(), block.timestamp - _lastUpdated)
            );
    }

    function _getStakingRate() internal view virtual returns (uint256 stakingRate_);
}
