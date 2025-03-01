// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ZapperBase} from "./ZapperBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVault} from "../interfaces/IVault.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";
import {IDexType} from "../interfaces/IDexType.sol";
import {ISteerPeriphery, ISushiMultiPositionLiquidityManager} from "../interfaces/steer/ISteer.sol";
import {SphereXProtected} from "@spherex-xyz/contracts/src/SphereXProtected.sol";

/**
 * @title SteerZapper
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
contract SteerZapper is ZapperBase {
  using SafeERC20 for IERC20;

  /// @notice Periphery contract use to add liquidity in steer vaults
  ISteerPeriphery public steerPeriphery;

  constructor(
    address dev,
    address wrappedNative,
    address stablecoin,
    address swapRouter,
    address lpRouter,
    address feeRecipient,
    uint16 zapInFee,
    uint16 zapOutFee,
    address steerPeripheryAddress
  ) ZapperBase(dev, wrappedNative, stablecoin, swapRouter, lpRouter, feeRecipient, zapInFee, zapOutFee) {
    if (steerPeripheryAddress == address(0)) revert ZeroAddress();
    steerPeriphery = ISteerPeriphery(steerPeripheryAddress);
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
    sphereXGuardPublic(0xbcff8354, 0x3218e83a)
    returns (uint256 tokenOutAmount, ReturnedAsset[] memory returnedAssets)
  {
    if (recipient != address(this)) {
      tokenInAmount = _safeTransferFromTokens(tokenIn, tokenInAmount);
    }

    // Divide tokenInAmount into optimal amounts for liquidity based on the current steer vault's ratio
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

    // Deposit liquidity to Steer Periphery contract
    IERC20(token0).forceApprove(address(steerPeriphery), amount0);
    IERC20(token1).forceApprove(address(steerPeriphery), amount1);

    // Add liquidity to steer vault
    steerPeriphery.deposit(asset, amount0, amount1, 0, 0, address(this));

    // Get LP tokens balance from steer vault
    tokenOutAmount = IERC20(asset).balanceOf(address(this));
    if (recipient != address(this)) {
      IERC20(asset).safeTransfer(recipient, tokenOutAmount);
    }

    // Swap back token0 and token1 to tokenIn if needed
    amount0 = IERC20(token0).balanceOf(address(this));
    amount1 = IERC20(token1).balanceOf(address(this));
    if (token0 != address(tokenIn) && amount0 > 0) {
      IERC20(token0).safeTransfer(address(swapRouter), amount0);
      amount0 = swapRouter.swapWithDefaultDex(address(token0), address(tokenIn), amount0, 0, address(this));
    }

    // Swap tokenIn to token1 if needed
    if (token1 != address(tokenIn) && amount1 > 0) {
      IERC20(token1).safeTransfer(address(swapRouter), amount1);
      amount1 = swapRouter.swapWithDefaultDex(address(token1), address(tokenIn), amount1, 0, address(this));
    }

    address[] memory tokens = new address[](3);
    tokens[0] = address(token0);
    tokens[1] = address(token1);
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
    sphereXGuardPublic(0xec29f0e1, 0xf99e6387)
    returns (uint256 tokenOutAmount, ReturnedAsset[] memory returnedAssets)
  {
    if (recipient != address(this)) {
      assetsInAmount = _safeTransferFromTokens(asset, assetsInAmount);
    }
    ISushiMultiPositionLiquidityManager steerVault = ISushiMultiPositionLiquidityManager(asset);
    (address token0, address token1) = (steerVault.token0(), steerVault.token1());
    (uint256 amount0, uint256 amount1) = steerVault.withdraw(assetsInAmount, 0, 0, address(this));

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

  /**
   * @notice Calculates the optimal amounts of token0 and token1 needed for liquidity provision
   * @dev Uses the current ratio of tokens in the steer vault to determine optimal split of input amount
   * @param tokenIn The address of the input token being provided
   * @param steerVaultAddress The address of the steer vault
   * @param amount The total amount of tokenIn to split between token0 and token1
   * @return amount0 The amount of token0 needed
   * @return amount1 The amount of token1 needed
   * @return token0 The address of the first token in the pair
   * @return token1 The address of the second token in the pair
   */
  function _getAmountsForLiquidity(
    address tokenIn,
    address steerVaultAddress,
    uint256 amount
  ) internal view returns (uint256 amount0, uint256 amount1, address token0, address token1) {
    ISushiMultiPositionLiquidityManager steerVault = ISushiMultiPositionLiquidityManager(steerVaultAddress);
    (amount0, amount1) = steerVault.getTotalAmounts();
    (token0, token1) = (steerVault.token0(), steerVault.token1());

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
}
