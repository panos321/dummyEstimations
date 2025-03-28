// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISushiMultiPositionLiquidityManager is IERC20 {
  /**
   * @dev Withdraws tokens in proportion to the vault's holdings.
   * @param shares Shares burned by sender
   * @param amount0Min Revert if resulting `amount0` is smaller than this
   * @param amount1Min Revert if resulting `amount1` is smaller than this
   * @param to Recipient of tokens
   * @return amount0 Amount of token0 sent to recipient
   * @return amount1 Amount of token1 sent to recipient
   */
  function withdraw(
    uint256 shares,
    uint256 amount0Min,
    uint256 amount1Min,
    address to
  ) external returns (uint256 amount0, uint256 amount1);

  /// @dev Calculates the vault's total holdings of token0 and token1.
  ///      in other words, how much of each token the vault would hold if it withdrew
  ///      all its liquidity from Uniswap.
  ///      This function DOES NOT include fees earned since the last burn.
  ///      To include fees, first poke() and then call getTotalAmounts.
  ///      There's a function inside the periphery to do so.
  function getTotalAmounts() external view returns (uint256 total0, uint256 total1);

  function poke() external;

  function token0() external view returns (address);

  function token1() external view returns (address);
}

interface ISteerPeriphery {
  /**
    @param _vaultAddress	address	The address of the vault to deposit to
    @param amount0Desired	uint256	Max amount of token0 to deposit
    @param amount1Desired	uint256	Max amount of token1 to deposit
    @param amount0Min	    uint256	Revert if resulting amount0 is less than this
    @param amount1Min	    uint256	Revert if resulting amount1 is less than this
    @param to	            address	Recipient of shares
    */

  function deposit(
    address _vaultAddress,
    uint256 amount0Desired,
    uint256 amount1Desired,
    uint256 amount0Min,
    uint256 amount1Min,
    address to
  ) external;
}
