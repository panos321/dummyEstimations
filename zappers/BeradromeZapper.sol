// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ZapperBase} from "./ZapperBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVault} from "../interfaces/IVault.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";
import {IDexType} from "../interfaces/IDexType.sol";
import {IBeradromeStaking} from "../interfaces/beradrome/IBeradrome.sol";
import {SphereXProtected} from "@spherex-xyz/contracts/src/SphereXProtected.sol";

/**
 * @title BeradromeZapper
 * @notice A zapper contract that enables single-token deposits and withdrawals for steer protocol vaults
 * @dev This contract handles the conversion between a single input token and the token pair required by steer vaults.
 * It manages the optimal ratio calculation and token swaps to match steer's deposit requirements.
 *
 * Key features:
 * - Single token deposits: Users can deposit a single token which gets converted to the required token pair
 * - Optimal ratio calculation: Automatically determines the best token ratio for deposits
 * - Withdrawal to single token: Converts withdrawn token pairs back to a single desired token
 * - Supports both native token and ERC20 deposits
 */
contract BeradromeZapper is ZapperBase {
  using SafeERC20 for IERC20;

  address ibgt = 0x46eFC86F0D7455F135CC9df501673739d513E982;

  constructor(
    address dev,
    address wrappedNative,
    address stablecoin,
    address swapRouter,
    address lpRouter,
    address feeRecipient,
    uint16 zapInFee,
    uint16 zapOutFee
  ) ZapperBase(dev, wrappedNative, stablecoin, swapRouter, lpRouter, feeRecipient, zapInFee, zapOutFee) {}

  /**
   * @notice Converts input token amount to vault's asset
   * @param asset The vault's asset
   * @param tokenIn The token being deposited
   * @param tokenInAmount The amount of tokens being deposited
   * @param recipient The address to receive the asset
   * @return tokenOutAmount Amount of asset received
   * @return returnedAssets Array of remaining token balances to be returned to the user
   */
  function swapToAssets(
    address asset,
    address tokenIn,
    uint256 tokenInAmount,
    address recipient
  )
    public
    override
    sphereXGuardPublic(0x3b9bf319, 0x3218e83a)
    returns (uint256 tokenOutAmount, ReturnedAsset[] memory returnedAssets)
  {
    if (recipient != address(this)) {
      tokenInAmount = _safeTransferFromTokens(tokenIn, tokenInAmount);
    }

    // BEX lp
    if (asset != ibgt) {
      IERC20(tokenIn).forceApprove(address(lpRouter), tokenInAmount);
      tokenOutAmount = lpRouter.addLiquidity(asset, tokenIn, tokenInAmount, address(this), IDexType.DexType.BEX);
    } else {
      // Swap tokenIn to asset if needed
      if (asset != address(tokenIn)) {
        IERC20(tokenIn).safeTransfer(address(swapRouter), tokenInAmount);
        tokenInAmount = swapRouter.swapWithDefaultDex(address(tokenIn), asset, tokenInAmount, 0, address(this));
      }

      // Get LP tokens balance from steer vault
      tokenOutAmount = IERC20(asset).balanceOf(address(this));
    }

    if (recipient != address(this)) {
      IERC20(asset).safeTransfer(recipient, tokenOutAmount);
    }

    address[] memory tokens = new address[](1);
    tokens[0] = address(tokenIn);

    returnedAssets = _returnAssets(tokens);
  }

  /**
   * @notice Converts vault's asset to output token
   * @param asset The vault's asset
   * @param tokenOut The token the user wants to receive
   * @param assetsInAmount The amount of LP tokens being withdrawn
   * @param recipient The address to receive the output token
   * @return tokenOutAmount The amount of desired tokens received
   * @return returnedAssets Array of remaining token balances to be returned to the user
   */
  function swapFromAssets(
    address asset,
    address tokenOut,
    uint256 assetsInAmount,
    address recipient
  )
    public
    override
    sphereXGuardPublic(0xe20e5fa2, 0xf99e6387)
    returns (uint256 tokenOutAmount, ReturnedAsset[] memory returnedAssets)
  {
    if (recipient != address(this)) {
      assetsInAmount = _safeTransferFromTokens(asset, assetsInAmount);
    }

    if (asset != address(tokenOut)) {
      IERC20(asset).safeTransfer(address(swapRouter), assetsInAmount);
      tokenOutAmount = swapRouter.swapWithDefaultDex(
        address(asset),
        address(tokenOut),
        assetsInAmount,
        0,
        address(this)
      );
    }

    if (recipient != address(this)) {
      _returnAsset(tokenOut, recipient);
    }

    address[] memory tokens = new address[](1);
    tokens[0] = asset == tokenOut ? address(0) : address(asset);
    returnedAssets = _returnAssets(tokens);
  }
}
