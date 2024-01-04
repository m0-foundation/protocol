// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { IERC20 } from "../../lib/common/src/interfaces/IERC20.sol";

import { IMToken } from "../../src/interfaces/IMToken.sol";

import { TTGRegistrarReader } from "../../src/libs/TTGRegistrarReader.sol";

import { INonfungiblePositionManager } from "../vendor/uniswap-v3/interfaces/INonfungiblePositionManager.sol";
import { IUniswapV3Factory } from "../vendor/uniswap-v3/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "../vendor/uniswap-v3/interfaces/IUniswapV3Pool.sol";
import { TransferHelper } from "../vendor/uniswap-v3/libraries/TransferHelper.sol";
import { TickMath } from "../vendor/uniswap-v3/utils/TickMath.sol";
import { encodePriceSqrt } from "../vendor/uniswap-v3/utils/Math.sol";

import { ForkBaseSetup } from "./ForkBaseSetup.t.sol";

contract UniswapV3PositionForkTest is ForkBaseSetup {
    /// @dev USDC on Ethereum Mainnet
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @dev Uniswap V3 stable pair fee
    uint24 public constant poolFee = 100; // 0.01% in bps

    // Implementing `onERC721Received` so this contract can receive custody of erc721 tokens
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function test_UniswapV3Position_nonEarning() public {
        vm.selectFork(mainnetFork);

        UniswapV3PositionManager positionManager_ = new UniswapV3PositionManager();

        address pool_ = positionManager_.createPool(address(_mToken), USDC, poolFee);

        uint256 mintAmount_ = 1_000_000e6;

        vm.prank(address(_minterGateway));
        _mToken.mint(address(this), mintAmount_);

        deal(USDC, address(this), mintAmount_);

        TransferHelper.safeApprove(address(_mToken), address(positionManager_), mintAmount_);
        TransferHelper.safeApprove(USDC, address(positionManager_), mintAmount_);

        (uint256 tokenId_, , , ) = positionManager_.mintNewPosition(poolFee, address(_mToken), USDC, mintAmount_);

        positionManager_.retrieveNFT(tokenId_);

        _registrar.addToList(TTGRegistrarReader.EARNERS_LIST, address(this));
        _mToken.startEarning();

        assertTrue(_mToken.isEarning(address(this)));

        assertEq(_mToken.balanceOf(pool_), mintAmount_);
        assertEq(IERC20(USDC).balanceOf(pool_), mintAmount_);

        // Check that the pool has not allowed earning on behalf
        assertFalse(_mToken.hasAllowedEarningOnBehalf(pool_));

        // Will revert since it is not possible to start earning on behalf of the pool
        vm.expectRevert(IMToken.HasNotAllowedEarningOnBehalf.selector);
        _mToken.startEarningOnBehalfOf(pool_);

        // Move 1 year forward and check that no interest has accrued
        vm.warp(block.timestamp + 365 days);

        // Despite having started earning and owning the NFT position, no interest has accrued
        // since the pool is the one holding the tokens and `startEarningOnBehalfOf` can't be called
        // since the pool contract can't call `allowEarningOnBehalf`
        assertEq(_mToken.balanceOf(pool_), mintAmount_);
        assertEq(IERC20(USDC).balanceOf(pool_), mintAmount_);
    }
}

contract UniswapV3PositionManager {
    /// @dev Uniswap V3 Position Manager on Ethereum Mainnet
    INonfungiblePositionManager public nonfungiblePositionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    /// @dev Uniswap V3 Factory on Ethereum Mainnet
    IUniswapV3Factory public factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    /// @notice Represents the deposit of an NFT
    struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }

    /// @dev deposits[tokenId] => Deposit
    mapping(uint256 => Deposit) public deposits;

    function createPool(address token0_, address token1__, uint24 fee_) external returns (address pool_) {
        pool_ = factory.createPool(token0_, token1__, fee_);
        IUniswapV3Pool(pool_).initialize(encodePriceSqrt(1, 1));
    }

    function _createDeposit(address owner_, uint256 tokenId_) internal {
        (, , address token0_, address token1_, , , , uint128 liquidity_, , , , ) = nonfungiblePositionManager.positions(
            tokenId_
        );

        deposits[tokenId_] = Deposit({ owner: owner_, liquidity: liquidity_, token0: token0_, token1: token1_ });
    }

    function mintNewPosition(
        uint24 poolFee_,
        address token0_,
        address token1_,
        uint256 mintAmount_
    ) external returns (uint256 tokenId_, uint128 liquidity_, uint256 amount0_, uint256 amount1_) {
        // Transfer tokens to contract
        TransferHelper.safeTransferFrom(token0_, msg.sender, address(this), mintAmount_);
        TransferHelper.safeTransferFrom(token1_, msg.sender, address(this), mintAmount_);

        TransferHelper.safeApprove(token0_, address(nonfungiblePositionManager), mintAmount_);
        TransferHelper.safeApprove(token1_, address(nonfungiblePositionManager), mintAmount_);

        // Note that the pool defined by token0_/token1_ and poolFee_ must already be created and initialized in order to mint
        (tokenId_, liquidity_, amount0_, amount1_) = nonfungiblePositionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0_,
                token1: token1_,
                fee: poolFee_,
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                amount0Desired: mintAmount_,
                amount1Desired: mintAmount_,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            })
        );

        // Store deposit in `deposits` mapping
        _createDeposit(msg.sender, tokenId_);

        // Remove allowance and refund in both assets
        if (amount0_ < mintAmount_) {
            TransferHelper.safeApprove(token0_, address(nonfungiblePositionManager), 0);
            TransferHelper.safeTransfer(token0_, msg.sender, mintAmount_ - amount0_);
        }

        if (amount1_ < mintAmount_) {
            TransferHelper.safeApprove(token1_, address(nonfungiblePositionManager), 0);
            TransferHelper.safeTransfer(token1_, msg.sender, mintAmount_ - amount1_);
        }
    }

    // Implementing `onERC721Received` so this contract can receive custody of erc721 tokens
    function onERC721Received(address operator, address, uint256 tokenId, bytes calldata) external returns (bytes4) {
        _createDeposit(operator, tokenId);
        return this.onERC721Received.selector;
    }

    /// @notice Transfers the NFT to the owner
    /// @param tokenId The id of the erc721
    function retrieveNFT(uint256 tokenId) external {
        // must be the owner of the NFT
        require(msg.sender == deposits[tokenId].owner, "Not the owner");

        // transfer ownership to original owner
        nonfungiblePositionManager.safeTransferFrom(address(this), msg.sender, tokenId);

        //remove information related to tokenId
        delete deposits[tokenId];
    }
}
