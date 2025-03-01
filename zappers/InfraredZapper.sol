// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ZapperBase} from "./ZapperBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IDexType} from "../interfaces/IDexType.sol";
import {ICropSwapLp} from "../interfaces/exchange/Crocswap.sol";
import {ILpRouter} from "../interfaces/ILpRouter.sol";
import {SphereXProtected} from "@spherex-xyz/contracts/src/SphereXProtected.sol";

/**
 * @title InfraredZapper
 * @notice A zapper contract that enables single-token deposits and withdrawals for Infrared Strategy
 */
contract InfraredZapper is ZapperBase {
  using SafeERC20 for IERC20;

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
    if (recipient != address(this)) {
      tokenInAmount = _safeTransferFromTokens(tokenIn, tokenInAmount);
    }

    ICropSwapLp lp = ICropSwapLp(asset);
    address base = lp.baseToken();
    address quote = lp.quoteToken();

    uint256 baseAmount = tokenInAmount / 2;
    uint256 quoteAmount = tokenInAmount - baseAmount;

    if (address(tokenIn) != base) {
      IERC20(tokenIn).safeTransfer(address(swapRouter), baseAmount);
      baseAmount = swapRouter.swapWithDefaultDex(address(tokenIn), base, baseAmount, 0, address(this));
    }
    if (address(tokenIn) != quote) {
      IERC20(tokenIn).safeTransfer(address(swapRouter), quoteAmount);
      quoteAmount = swapRouter.swapWithDefaultDex(address(tokenIn), quote, quoteAmount, 0, address(this));
    }

    IERC20(base).safeTransfer(address(lpRouter), baseAmount);
    IERC20(quote).safeTransfer(address(lpRouter), quoteAmount);

    tokenOutAmount = lpRouter.addLiquidity(
      ILpRouter.AddLiquidityParams({
        lp: address(lp),
        base: base,
        quote: quote,
        poolIdx: lp.poolType(),
        baseAmount: baseAmount,
        quoteAmount: quoteAmount,
        limitLower: uint128(0),
        limitHigher: type(uint128).max,
        recipient: recipient,
        extraParams: ""
      }),
      IDexType.DexType.BEX
    );

    // remaining base and quote token amounts
    baseAmount = IERC20(base).balanceOf(address(this));
    quoteAmount = IERC20(quote).balanceOf(address(this));

    // if we have remaining base or quote tokens, convert them back to the input token
    if (base != address(tokenIn) && baseAmount > 0) {
      IERC20(base).safeTransfer(address(swapRouter), baseAmount);
      baseAmount = swapRouter.swapWithDefaultDex(base, address(tokenIn), baseAmount, 0, address(this));
    }
    if (quote != address(tokenIn) && quoteAmount > 0) {
      IERC20(quote).safeTransfer(address(swapRouter), quoteAmount);
      quoteAmount = swapRouter.swapWithDefaultDex(quote, address(tokenIn), quoteAmount, 0, address(this));
    }

    address[] memory tokens = new address[](3);
    tokens[0] = base;
    tokens[1] = quote;
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
    sphereXGuardPublic(0x362279f7, 0xf99e6387)
    returns (uint256 tokenOutAmount, ReturnedAsset[] memory returnedAssets)
  {
    if (recipient != address(this)) {
      assetsInAmount = _safeTransferFromTokens(asset, assetsInAmount);
    }
    ICropSwapLp lp = ICropSwapLp(asset);
    address base = lp.baseToken();
    address quote = lp.quoteToken();

    IERC20(lp).safeTransfer(address(lpRouter), assetsInAmount);
    (uint256 baseAmount, uint256 quoteAmount) = lpRouter.removeLiquidity(
      ILpRouter.RemoveLiquidityParams({
        lp: address(lp),
        lpAmount: assetsInAmount,
        limitLower: uint128(0),
        limitHigher: type(uint128).max,
        recipient: address(this),
        extraParams: ""
      }),
      IDexType.DexType.BEX
    );

    if (address(tokenOut) != base) {
      IERC20(base).safeTransfer(address(swapRouter), baseAmount);
      baseAmount = swapRouter.swapWithDefaultDex(base, address(tokenOut), baseAmount, 0, address(this));
    }
    if (address(tokenOut) != quote) {
      IERC20(quote).safeTransfer(address(swapRouter), quoteAmount);
      quoteAmount = swapRouter.swapWithDefaultDex(quote, address(tokenOut), quoteAmount, 0, address(this));
    }
    tokenOutAmount = baseAmount + quoteAmount;
    if (recipient != address(this)) {
      _returnAsset(tokenOut, recipient);
    }

    address[] memory tokens = new address[](2);
    tokens[0] = base == tokenOut ? address(0) : base;
    tokens[1] = quote == tokenOut ? address(0) : quote;
    returnedAssets = _returnAssets(tokens);
  }
}
