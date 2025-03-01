// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ZapperBase} from "../zappers/ZapperBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVault} from "../interfaces/IVault.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";
import {IDexType} from "../interfaces/IDexType.sol";

contract MockZapper is ZapperBase {
  using SafeERC20 for IERC20;

  constructor(
    address governance,
    address wrappedNative,
    address usdcToken,
    address swapRouter,
    address lpRouter,
    address feeRecipient,
    uint16 zapInFee,
    uint16 zapOutFee
  ) ZapperBase(governance, wrappedNative, usdcToken, swapRouter, lpRouter, feeRecipient, zapInFee, zapOutFee) {}

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
  ) public override returns (uint256 tokenOutAmount, ReturnedAsset[] memory returnedAssets) {
    if (recipient != address(this)) {
      tokenInAmount = _safeTransferFromTokens(tokenIn, tokenInAmount);
    }
    address tokenOut = asset;

    if (tokenOut != address(tokenIn)) {
      IERC20(tokenIn).safeTransfer(address(swapRouter), tokenInAmount);
      tokenOutAmount = swapRouter.swap(
        address(tokenIn),
        tokenOut,
        tokenInAmount,
        0,
        address(this),
        IDexType.DexType.UNISWAP_V3
      );
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
  ) public override returns (uint256 tokenOutAmount, ReturnedAsset[] memory returnedAssets) {
    if (recipient != address(this)) {
      assetsInAmount = _safeTransferFromTokens(asset, assetsInAmount);
    }
    address tokenIn = asset;

    if (address(tokenIn) != address(tokenOut)) {
      IERC20(tokenIn).safeTransfer(address(swapRouter), assetsInAmount);
      tokenOutAmount = swapRouter.swap(
        address(tokenIn),
        address(tokenOut),
        assetsInAmount,
        0,
        address(this),
        IDexType.DexType.UNISWAP_V3
      );
    }

    address[] memory tokens = new address[](2);
    tokens[0] = address(tokenOut);
    tokens[1] = address(tokenIn);
    returnedAssets = _returnAssets(tokens);
  }
}
