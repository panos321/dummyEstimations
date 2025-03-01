// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ZapperBase} from "./ZapperBase.sol";
import {IKodiakVaultV1, IKodiakV1RouterStaking} from "../interfaces/kodiak/IKodiak.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVault} from "../interfaces/IVault.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";
import {IDexType} from "../interfaces/IDexType.sol";
import {SphereXProtected} from "@spherex-xyz/contracts/src/SphereXProtected.sol";

/**
 * @title KodiakZapper
 * @notice A zapper contract that enables single-token deposits and withdrawals for Kodiak vaults
 * @dev This contract handles the conversion between a single input token and the token pair required by Kodiak vaults.
 * It manages the optimal ratio calculation and token swaps to match Kodiak's deposit requirements.
 *
 * Key features:
 * - Single token deposits: Users can deposit a single token which gets converted to the required token pair
 * - Optimal ratio calculation: Automatically determines the best token ratio for deposits
 * - Withdrawal to single token: Converts withdrawn token pairs back to a single desired token
 * - Supports both native token and ERC20 deposits
 */
contract KodiakZapper is ZapperBase {
  using SafeERC20 for IERC20;

  constructor(
    address governanceAddress,
    address wrappedNative,
    address stableCoin,
    address swapRouter,
    address lpRouter,
    address feeRecipient,
    uint16 zapInFee,
    uint16 zapOutFee
  ) ZapperBase(governanceAddress, wrappedNative, stableCoin, swapRouter, lpRouter, feeRecipient, zapInFee, zapOutFee) {}

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
    sphereXGuardPublic(0xab984628, 0x3218e83a)
    returns (uint256 tokenOutAmount, ReturnedAsset[] memory returnedAssets)
  {
    if (recipient != address(this)) {
      tokenInAmount = _safeTransferFromTokens(tokenIn, tokenInAmount);
    }

    //send tokenIn to lpRouter
    IERC20(tokenIn).safeTransfer(address(lpRouter), tokenInAmount);

    // Swap tokenIn to token0 and token1 and get LP tokens balance from steer vault
    tokenOutAmount = lpRouter.addLiquidity(asset, tokenIn, tokenInAmount, address(this), IDexType.DexType.KODIAK_V3);

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
    sphereXGuardPublic(0xf64350eb, 0xf99e6387)
    returns (uint256 tokenOutAmount, ReturnedAsset[] memory returnedAssets)
  {
    if (recipient != address(this)) {
      assetsInAmount = _safeTransferFromTokens(asset, assetsInAmount);
    }

    //send assetsIn to lpRouter
    IERC20(asset).safeTransfer(address(lpRouter), assetsInAmount);

    tokenOutAmount = lpRouter.removeLiquidity(
      asset,
      assetsInAmount,
      address(this),
      tokenOut,
      IDexType.DexType.KODIAK_V3
    );

    if (recipient != address(this)) {
      _returnAsset(tokenOut, recipient);
    }
  }
}
