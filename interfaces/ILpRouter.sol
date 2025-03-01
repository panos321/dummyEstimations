// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IDexType} from "./IDexType.sol";

interface ILpRouter is IDexType {
  /// @notice Thrown when router arrays have mismatched lengths
  error InvalidRouterLength();

  /// @notice Thrown when router address is zero
  error ZeroRouterAddress();

  /// @notice Thrown when address is zero
  error ZeroAddress();

  /// @notice Thrown when a function is called by an address that isn't governance
  error NotGovernance();

  /// @notice Emitted when the governance is updated
  event GovernanceUpdated(address indexed oldGovernance, address indexed newGovernance);

  /// @notice Emitted when a router is set for a DEX
  /// @param dex The DEX index
  /// @param router The router address
  event SetRouter(uint8 dex, address indexed router);

  /// @notice Struct for parameters of the addLiquidity function
  /// @param lp The address of the LP token
  /// @param base The address of the base token
  /// @param quote The address of the quote token
  /// @param poolIdx The index of the pool
  /// @param baseAmount The amount of base token to add
  /// @param quoteAmount The amount of quote token to add
  /// @param limitLower The lower limit of the price
  /// @param limitHigher The higher limit of the price
  /// @param recipient The recipient of the LP tokens
  /// @param extraParams Additional parameters
  struct AddLiquidityParams {
    address lp;
    address base;
    address quote;
    uint256 poolIdx;
    uint256 baseAmount;
    uint256 quoteAmount;
    uint128 limitLower;
    uint128 limitHigher;
    address recipient;
    bytes extraParams;
  }

  /// @notice Struct for parameters of the removeLiquidity function
  /// @param lp The address of the LP token
  /// @param lpAmount The amount of LP tokens to remove
  /// @param limitLower The lower limit of the price
  /// @param limitHigher The higher limit of the price
  /// @param recipient The recipient of the base and quote tokens
  /// @param extraParams Additional parameters
  struct RemoveLiquidityParams {
    address lp;
    uint256 lpAmount;
    uint128 limitLower;
    uint128 limitHigher;
    address recipient;
    bytes extraParams;
  }

  /// @notice Adds liquidity to a pool using the default DEX
  /// @param params_ The parameters for the addLiquidity function
  /// @return lpAmountOut The amount of LP tokens received
  function addLiquidityWithDefaultDex(AddLiquidityParams calldata params_) external returns (uint256 lpAmountOut);

  /// @notice Adds liquidity to a pool with a specified DEX
  /// @param params_ The parameters for the addLiquidity function
  /// @param dexType_ The DEX to use
  /// @return lpAmountOut The amount of LP tokens received
  function addLiquidity(
    AddLiquidityParams calldata params_,
    IDexType.DexType dexType_
  ) external returns (uint256 lpAmountOut);

  /// @notice Removes liquidity from a pool using the default DEX
  /// @param params_ The parameters for the removeLiquidity function
  /// @return baseAmount The amount of base tokens received
  /// @return quoteAmount The amount of quote tokens received
  function removeLiquidityWithDefaultDex(
    RemoveLiquidityParams calldata params_
  ) external returns (uint256 baseAmount, uint256 quoteAmount);

  /// @notice Removes liquidity from a pool with a specified DEX
  /// @param params_ The parameters for the removeLiquidity function
  /// @param dexType_ The DEX to use
  /// @return baseAmount The amount of base tokens received
  /// @return quoteAmount The amount of quote tokens received
  function removeLiquidity(
    RemoveLiquidityParams calldata params_,
    IDexType.DexType dexType_
  ) external returns (uint256 baseAmount, uint256 quoteAmount);
}
