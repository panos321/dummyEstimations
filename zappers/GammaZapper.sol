// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ZapperBase} from "./ZapperBase.sol";
import {IUniProxy, IHypervisor} from "../interfaces/gamma/IGamma.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVault} from "../interfaces/IVault.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";
import {IDexType} from "../interfaces/IDexType.sol";
import {SphereXProtected} from "@spherex-xyz/contracts/src/SphereXProtected.sol";

/**
 * @title GammaZapper
 * @notice A zapper contract that enables single-token deposits and withdrawals for Gamma Hypervisor vaults
 * @dev This contract handles the conversion between a single input token and the token pair required by Gamma vaults.
 * It manages the optimal ratio calculation and token swaps to match Gamma's deposit requirements.
 *
 * Key features:
 * - Single token deposits: Users can deposit a single token which gets converted to the required token pair
 * - Optimal ratio calculation: Automatically determines the best token ratio for deposits
 * - Withdrawal to single token: Converts withdrawn token pairs back to a single desired token
 * - Supports both native token and ERC20 deposits
 */
contract GammaZapper is ZapperBase {
  using SafeERC20 for IERC20;
  IUniProxy public gammaUniProxy;

  /// @notice Error thrown when the minimum input amount is too low for the Gamma vault
  error MinInAmountTooLow();

  constructor(
    address dev,
    address wrappedNative,
    address stablecoin,
    address swapRouter,
    address lpRouter,
    address feeRecipient,
    uint16 zapInFee,
    uint16 zapOutFee,
    address gammaUniProxyAddress
  ) ZapperBase(dev, wrappedNative, stablecoin, swapRouter, lpRouter, feeRecipient, zapInFee, zapOutFee) {
    if (gammaUniProxyAddress == address(0)) revert ZeroAddress();
    gammaUniProxy = IUniProxy(gammaUniProxyAddress);
  }

  struct Amounts {
    uint256 amount0;
    uint256 amount1;
    address token0;
    address token1;
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
    sphereXGuardPublic(0x597ae2e7, 0x3218e83a)
    returns (uint256 tokenOutAmount, ReturnedAsset[] memory returnedAssets)
  {
    if (recipient != address(this)) {
      tokenInAmount = _safeTransferFromTokens(tokenIn, tokenInAmount);
    }
    Amounts memory amounts;
    (amounts.amount0, amounts.amount1, amounts.token0, amounts.token1) = _getAmountsForLiquidity(
      asset,
      tokenIn,
      tokenInAmount
    );

    if (amounts.token0 != tokenIn) {
      IERC20(tokenIn).safeTransfer(address(swapRouter), amounts.amount0);
      amounts.amount0 = swapRouter.swap(
        tokenIn,
        amounts.token0,
        amounts.amount0,
        0,
        address(this),
        IDexType.DexType.UNISWAP_V3
      );
    }

    if (amounts.token1 != amounts.token0) {
      IERC20(tokenIn).safeTransfer(address(swapRouter), amounts.amount1);
      amounts.amount1 = swapRouter.swap(
        tokenIn,
        amounts.token1,
        amounts.amount1,
        0,
        address(this),
        IDexType.DexType.UNISWAP_V3
      );
    }

    (amounts.amount0, amounts.amount1) = _updateDepositAmountsIfNeeded(asset, amounts.amount0, amounts.amount1);

    _approveTokenIfNeeded(amounts.token0, asset);
    _approveTokenIfNeeded(amounts.token1, asset);
    uint256[4] memory minInAmounts = [uint256(0), uint256(0), uint256(0), uint256(0)];
    tokenOutAmount = IUniProxy(gammaUniProxy).deposit(amounts.amount0, amounts.amount1, recipient, asset, minInAmounts);
    if (recipient != address(this)) {
      IERC20(asset).safeTransfer(recipient, tokenOutAmount);
    }

    address[] memory tokens = new address[](3);
    tokens[0] = amounts.token0;
    tokens[1] = amounts.token1;
    tokens[2] = tokenIn;
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
    sphereXGuardPublic(0x2e2427dc, 0xf99e6387)
    returns (uint256 tokenOutAmount, ReturnedAsset[] memory returnedAssets)
  {
    if (recipient != address(this)) {
      assetsInAmount = _safeTransferFromTokens(asset, assetsInAmount);
    }
    IHypervisor gammaVault = IHypervisor(asset);
    Amounts memory amounts;
    (amounts.token0, amounts.token1) = (gammaVault.token0(), gammaVault.token1());

    uint256[4] memory minInAmounts = [uint256(0), uint256(0), uint256(0), uint256(0)];
    (amounts.amount0, amounts.amount1) = gammaVault.withdraw(
      assetsInAmount,
      address(this),
      address(this),
      minInAmounts
    );

    if (amounts.token0 != tokenOut) {
      IERC20(amounts.token0).safeTransfer(address(swapRouter), amounts.amount0);
      tokenOutAmount = swapRouter.swap(
        amounts.token0,
        tokenOut,
        amounts.amount0,
        0,
        address(this),
        IDexType.DexType.UNISWAP_V3
      );
    } else {
      tokenOutAmount = amounts.amount0;
    }
    if (amounts.token1 != tokenOut) {
      IERC20(amounts.token1).safeTransfer(address(swapRouter), amounts.amount1);
      tokenOutAmount += swapRouter.swap(
        amounts.token1,
        tokenOut,
        amounts.amount1,
        0,
        address(this),
        IDexType.DexType.UNISWAP_V3
      );
    } else {
      tokenOutAmount += amounts.amount1;
    }
    if (recipient != address(this)) {
      _returnAsset(tokenOut, recipient);
    }
    address[] memory tokens = new address[](2);
    tokens[0] = tokenOut == amounts.token0 ? address(0) : amounts.token0;
    tokens[1] = tokenOut == amounts.token1 ? address(0) : amounts.token1;
    returnedAssets = _returnAssets(tokens);
  }

  /**
   * @notice Adjusts the deposit amounts based on min and max amounts of the gamma vault
   * @param gammaVault The address of the Gamma vault
   * @param amount0 The amount of token0 to be deposited
   * @param amount1 The amount of token1 to be deposited
   * @return amount0 The updated amount of token0 to be deposited
   * @return amount1 The updated amount of token1 to be deposited
   */
  function _updateDepositAmountsIfNeeded(
    address gammaVault,
    uint256 amount0,
    uint256 amount1
  ) internal view returns (uint256, uint256) {
    (address token0, address token1) = (IHypervisor(gammaVault).token0(), IHypervisor(gammaVault).token1());
    (uint token1MinAmount, uint token1MaxAmount) = IUniProxy(gammaUniProxy).getDepositAmount(
      gammaVault,
      token0,
      amount0
    );

    if (amount1 > token1MaxAmount) {
      amount1 = token1MaxAmount;
    } else if (amount1 < token1MinAmount) {
      (uint token0MinAmount, uint token0MaxAmount) = IUniProxy(gammaUniProxy).getDepositAmount(
        gammaVault,
        token1,
        amount1
      );

      if (amount0 < token0MinAmount) {
        revert MinInAmountTooLow();
      }

      if (amount0 > token0MaxAmount) {
        amount0 = token0MaxAmount;
      }
    }

    return (amount0, amount1);
  }

  /**
   * @notice Calculates the optimal token0/token1 ratio for depositing into a Gamma vault.
   * The Uniproxy getDepositAmount function is used to find the amount of one token by providing the amount of the other token. We can use this to find the
   * ratio of the two tokens in the hypervisor, As a starting point we use half of the zapped amount as the amount of token0, then we use the getDepositAmount
   * function to find the amount of token1. With these two values we can find the ratio, first we need to convert both the amounts in base token (wrappedNative)
   * then we can find the ratio of token0 to token1. With this ratio we can convert the zapped amount to the correct amount of token0 and token1
   * @param gammaVault The address of the Gamma vault
   * @param tokenIn The token being deposited
   * @param tokenInAmount The amount of tokens being deposited
   * @return amount0 The amount of token0 to be deposited
   * @return amount1 The amount of token1 to be deposited
   * @return token0 The address of the token0
   * @return token1 The address of the token1
   */
  function _getAmountsForLiquidity(
    address gammaVault,
    address tokenIn,
    uint256 tokenInAmount
  ) internal view returns (uint256 amount0, uint256 amount1, address token0, address token1) {
    (token0, token1) = (IHypervisor(gammaVault).token0(), IHypervisor(gammaVault).token1());
    amount0 = tokenInAmount / 2;
    (, amount1) = IUniProxy(gammaUniProxy).getDepositAmount(gammaVault, token0, amount0);

    if (token0 != tokenIn) {
      uint256 oneUnit = 10 ** IERC20Metadata(token0).decimals();
      uint256 price0 = swapRouter.getQuote(token0, tokenIn, oneUnit, IDexType.DexType.UNISWAP_V3);
      amount0 = (amount0 * price0 * 10 ** 18) / oneUnit;
    }
    if (token1 != tokenIn) {
      uint256 oneUnit = 10 ** IERC20Metadata(token1).decimals();
      uint256 price1 = swapRouter.getQuote(token1, tokenIn, oneUnit, IDexType.DexType.UNISWAP_V3);
      amount1 = (amount1 * price1 * 10 ** 18) / oneUnit;
    }
    (amount0, amount1) = _divideAmountInRatio(tokenInAmount, amount0, amount1);
  }
}
