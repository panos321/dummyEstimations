// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";
import {MockERC20} from "./MockERC20.sol";

import {IBeraPool} from "../interfaces/exchange/Beraswap.sol";

contract MockSwapRouter is ISwapRouter {
  address public immutable wrappedNative;
  DexType public defaultDex;

  constructor(address wrappedNativeAddress) {
    require(wrappedNativeAddress != address(0), "Invalid wrapped native address");
    wrappedNative = wrappedNativeAddress;
  }

  function swapWithDefaultDex(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMinimum,
    address recipient
  ) external returns (uint256 amountOut) {
    // Burn input tokens
    MockERC20(tokenIn).burnFrom(msg.sender, amountIn);

    amountOut = amountIn;
    require(amountOut >= amountOutMinimum, "Insufficient output amount");

    // Mint output tokens
    MockERC20(tokenOut).mint(recipient, amountOut);

    return amountOut;
  }

  function swap(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMinimum,
    address recipient,
    DexType dex
  ) external returns (uint256 amountOut) {
    if (
      dex != DexType.UNISWAP_V2 &&
      dex != DexType.UNISWAP_V3 &&
      dex != DexType.SUSHISWAP_V2 &&
      dex != DexType.SUSHISWAP_V3 &&
      dex != DexType.CAMELOT_V3
    ) revert UnsupportedDexType();
    // Ignore dex parameter in mock, just use default swap
    return this.swapWithDefaultDex(tokenIn, tokenOut, amountIn, amountOutMinimum, recipient);
  }

  function swapWithPathWithDefaultDex(
    address[] calldata path,
    uint256 amountIn,
    uint256 amountOutMinimum,
    address recipient
  ) external returns (uint256 amountOut) {
    require(path.length >= 2, "Invalid path length");

    // Burn input tokens
    MockERC20(path[0]).burnFrom(msg.sender, amountIn);

    amountOut = amountIn;
    require(amountOut >= amountOutMinimum, "Insufficient output amount");

    // Mint output tokens to recipient
    MockERC20(path[path.length - 1]).mint(recipient, amountOut);

    return amountOut;
  }

  function swapWithPath(
    address[] calldata path,
    uint256 amountIn,
    uint256 amountOutMinimum,
    address recipient,
    DexType
  ) external returns (uint256 amountOut) {
    // Ignore dex parameter in mock, just use default swapWithPath
    return this.swapWithPathWithDefaultDex(path, amountIn, amountOutMinimum, recipient);
  }

  function routers(uint8 dex) external view override returns (address) {}

  function factories(uint8 dex) external view override returns (address) {}

  function getQuoteWithDefaultDex(
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  ) external view override returns (uint256 amountOut) {}

  function getQuote(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    DexType dex
  ) external view override returns (uint256 amountOut) {}

  function getQuoteWithPathWithDefaultDex(
    address[] memory path,
    uint256 amountIn
  ) external view override returns (uint256 amountOut) {}

  function getQuoteWithPath(
    address[] memory path,
    uint256 amountIn,
    DexType dex
  ) external view override returns (uint256 amountOut) {}
}
