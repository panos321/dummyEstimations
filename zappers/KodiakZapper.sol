// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ZapperBase} from "./ZapperBase.sol";
import {IUniProxy, IHypervisor} from "../interfaces/gamma/IGamma.sol";
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

  IKodiakV1RouterStaking public kodiakRouterStaking;

  constructor(
    address governanceAddress,
    address wrappedNative,
    address stableCoin,
    address swapRouter,
    address lpRouter,
    address feeRecipient,
    uint16 zapInFee,
    uint16 zapOutFee,
    address kodiakRouterStakingAddress
  ) ZapperBase(governanceAddress, wrappedNative, stableCoin, swapRouter, lpRouter, feeRecipient, zapInFee, zapOutFee) {
    kodiakRouterStaking = IKodiakV1RouterStaking(kodiakRouterStakingAddress);
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

    // Divide tokenInAmount into optimal amounts for liquidity based on the current kodiak vault's ratio
    (uint256 amount0, uint256 amount1, address token0, address token1) = _getAmountsForLiquidity(
      address(tokenIn),
      asset,
      tokenInAmount
    );

    // Swap tokenIn to token0 if needed
    if (token0 != address(tokenIn)) {
      IERC20(tokenIn).safeTransfer(address(swapRouter), amount0);
      amount0 = swapRouter.swapWithDefaultDex(address(tokenIn), token0, amount0, 0, address(this));
    }

    // Swap tokenIn to token1 if needed
    if (token1 != address(tokenIn)) {
      IERC20(tokenIn).safeTransfer(address(swapRouter), amount1);
      amount1 = swapRouter.swapWithDefaultDex(address(tokenIn), token1, amount1, 0, address(this));
    }

    tokenOutAmount = _addLiquidity(asset, token0, token1, recipient);

    address[] memory tokens = new address[](3);
    tokens[0] = token0;
    tokens[1] = token1;
    tokens[2] = address(tokenIn);
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
    IKodiakVaultV1 kodiakVault = IKodiakVaultV1(asset);
    (address token0, address token1) = (kodiakVault.token0(), kodiakVault.token1());

    _approveTokenIfNeeded(address(kodiakVault), address(kodiakRouterStaking));

    (uint256 amount0, uint256 amount1, ) = IKodiakV1RouterStaking(kodiakRouterStaking).removeLiquidity(
      kodiakVault,
      assetsInAmount,
      0,
      0,
      address(this)
    );

    if (token0 != address(tokenOut)) {
      IERC20(token0).safeTransfer(address(swapRouter), amount0);
      amount0 = swapRouter.swapWithDefaultDex(address(token0), address(tokenOut), amount0, 0, address(this));
    }
    if (token1 != address(tokenOut)) {
      IERC20(token1).safeTransfer(address(swapRouter), amount1);
      amount1 = swapRouter.swapWithDefaultDex(address(token1), address(tokenOut), amount1, 0, address(this));
    }
    tokenOutAmount = amount0 + amount1;
    if (recipient != address(this)) {
      _returnAsset(tokenOut, recipient);
    }

    address[] memory tokens = new address[](2);
    tokens[0] = tokenOut == token0 ? address(0) : address(token0);
    tokens[1] = tokenOut == token1 ? address(0) : address(token1);
    returnedAssets = _returnAssets(tokens);
  }

  function _getTokenBalances(address token0, address token1) internal view returns (uint256, uint256) {
    return (IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)));
  }

  function _getKodiakVaultMintAmount(
    IKodiakVaultV1 kodiakVault,
    uint256 token0MaxAmount,
    uint256 token1MaxAmount
  ) internal view returns (uint256 token0Amount, uint256 token1Amount, uint256 mintAmount) {
    (token0Amount, token1Amount, mintAmount) = kodiakVault.getMintAmounts(token0MaxAmount, token1MaxAmount);
  }

  function _getAmountsForLiquidity(
    address tokenIn,
    address kodiakVaultAddress,
    uint256 amount
  ) internal view returns (uint256 amount0, uint256 amount1, address token0, address token1) {
    IKodiakVaultV1 kodiak = IKodiakVaultV1(kodiakVaultAddress);
    (amount0, amount1) = kodiak.getUnderlyingBalances();
    (token0, token1) = (kodiak.token0(), kodiak.token1());

    if (token0 != tokenIn) {
      uint256 oneUnit = 10 ** IERC20Metadata(token0).decimals();
      uint256 price0 = swapRouter.getQuote(token0, tokenIn, oneUnit, IDexType.DexType.KODIAK_V3);
      amount0 = (amount0 * price0) / oneUnit;
    }
    if (token1 != tokenIn) {
      uint256 oneUnit = 10 ** IERC20Metadata(token1).decimals();
      uint256 price1 = swapRouter.getQuote(token1, tokenIn, oneUnit, IDexType.DexType.KODIAK_V3);
      amount1 = (amount1 * price1) / oneUnit;
    }

    (amount0, amount1) = _divideAmountInRatio(amount, amount0, amount1);
  }

  struct Amounts {
    uint256 token0AmountMin;
    uint256 token1AmountMin;
    uint256 mintAmountMin;
  }

  function _addLiquidity(
    address asset,
    address token0,
    address token1,
    address recipient
  ) internal sphereXGuardInternal(0x58d48777) returns (uint256 tokenOutAmount) {
    (uint256 amount0, uint256 amount1) = _getTokenBalances(address(token0), address(token1));

    Amounts memory amounts;
    (amounts.token0AmountMin, amounts.token1AmountMin, amounts.mintAmountMin) = _getKodiakVaultMintAmount(
      IKodiakVaultV1(asset),
      amount0,
      amount1
    );

    _approveTokenIfNeeded(address(token0), address(kodiakRouterStaking));
    _approveTokenIfNeeded(address(token1), address(kodiakRouterStaking));

    (, , tokenOutAmount) = IKodiakV1RouterStaking(kodiakRouterStaking).addLiquidity(
      IKodiakVaultV1(asset),
      amount0,
      amount1,
      amounts.token0AmountMin,
      amounts.token1AmountMin,
      amounts.mintAmountMin,
      recipient
    );
  }
}
