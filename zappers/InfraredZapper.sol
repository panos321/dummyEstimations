// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ZapperBase} from "./ZapperBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IDexType} from "../interfaces/IDexType.sol";
import {ILpRouter} from "../interfaces/ILpRouter.sol";
import {SphereXProtected} from "@spherex-xyz/contracts/src/SphereXProtected.sol";
import {IBeraPool, IBeraVault, IAsset} from "../interfaces/exchange/Beraswap.sol";

/**
 * @title InfraredZapper
 * @notice A zapper contract that enables single-token deposits and withdrawals for Infrared Strategy
 */
contract InfraredZapper is ZapperBase {
  using SafeERC20 for IERC20;

  mapping(address => bool) public isAssetSingleToken;
  mapping(address => IDexType.DexType) public assetDex;

  event AssetInfoSet(address asset, bool isSingleToken, IDexType.DexType dex);

  constructor(
    address devAddress,
    address wrappedNative,
    address stablecoin,
    address swapRouter,
    address lpRouter,
    address feeRecipient,
    uint16 zapInFee,
    uint16 zapOutFee
  ) ZapperBase(devAddress, wrappedNative, stablecoin, swapRouter, lpRouter, feeRecipient, zapInFee, zapOutFee) {}

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
    sphereXGuardPublic(0x07c1e85d, 0x3218e83a)
    returns (uint256 tokenOutAmount, ReturnedAsset[] memory returnedAssets)
  {
    // Transfer tokens if needed
    if (recipient != address(this)) {
      tokenInAmount = _safeTransferFromTokens(tokenIn, tokenInAmount);
    }

    address[] memory tokens;
    if (isAssetSingleToken[asset]) {
      IERC20(tokenIn).safeTransfer(address(swapRouter), tokenInAmount);
      tokenOutAmount = swapRouter.swapWithDefaultDex(address(tokenIn), asset, tokenInAmount, 0, recipient);
      tokens = new address[](1);
      tokens[0] = address(tokenIn);
      returnedAssets = _returnAssets(tokens);
      return (tokenOutAmount, returnedAssets);
    }

    return _swapToAssetsLp(asset, tokenIn, tokenInAmount, recipient);
  }

  /**
   * @notice Converts input token amount to vault's asset
   * @param asset The vault's asset
   * @param tokenIn The token being deposited
   * @param tokenInAmount The amount of tokens being deposited
   * @param recipient The address to receive the asset
   * @return tokenOutAmount Amount of asset received
   * @return returnedAssets Array of remaining token balances to be returned to the user
   */
  function _swapToAssetsLp(
    address asset,
    address tokenIn,
    uint256 tokenInAmount,
    address recipient
  ) internal returns (uint256 tokenOutAmount, ReturnedAsset[] memory returnedAssets) {
    // Add liquidity
    IERC20(tokenIn).safeTransfer(address(lpRouter), tokenInAmount);
    tokenOutAmount = lpRouter.addLiquidity(asset, tokenIn, tokenInAmount, recipient, assetDex[asset]);

    // Return assets
    address[] memory checkTokens = new address[](1);
    checkTokens[0] = tokenIn;
    returnedAssets = _returnAssets(checkTokens);
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
    sphereXGuardPublic(0x362279f7, 0xf99e6387)
    returns (uint256 tokenOutAmount, ReturnedAsset[] memory returnedAssets)
  {
    // Transfer tokens if needed
    if (recipient != address(this)) {
      assetsInAmount = _safeTransferFromTokens(asset, assetsInAmount);
    }

    if (isAssetSingleToken[asset]) {
      IERC20(asset).safeTransfer(address(swapRouter), assetsInAmount);
      tokenOutAmount = swapRouter.swapWithDefaultDex(asset, tokenOut, assetsInAmount, 0, recipient);
      address[] memory tokens = new address[](1);
      tokens[0] = asset;
      returnedAssets = _returnAssets(tokens);
      return (tokenOutAmount, returnedAssets);
    }

    return _swapFromAssetsLp(asset, tokenOut, assetsInAmount, recipient);
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
  function _swapFromAssetsLp(
    address asset,
    address tokenOut,
    uint256 assetsInAmount,
    address recipient
  ) internal returns (uint256 tokenOutAmount, ReturnedAsset[] memory returnedAssets) {
    // Remove liquidity
    IERC20(asset).safeTransfer(address(lpRouter), assetsInAmount);
    tokenOutAmount = lpRouter.removeLiquidity(asset, assetsInAmount, recipient, tokenOut, assetDex[asset]);

    if (recipient != address(this)) {
      _returnAsset(tokenOut, recipient);
    }

    address[] memory checkTokens = new address[](1);
    checkTokens[0] = address(0);
    returnedAssets = _returnAssets(checkTokens);
  }

  function setAssetInfo(address asset, bool isSingleToken, IDexType.DexType dex) external onlyGovernance {
    _revertAddressZero(asset);
    isAssetSingleToken[asset] = isSingleToken;
    assetDex[asset] = dex;
    emit AssetInfoSet(asset, isSingleToken, dex);
  }
}
