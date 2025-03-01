// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Pool} from "../exchange/UniswapV3.sol";

interface IKodiakVaultV1 {
  function mint(
    uint256 mintAmount,
    address receiver
  ) external returns (uint256 amount0, uint256 amount1, uint128 liquidityMinted);

  function burn(
    uint256 burnAmount,
    address receiver
  ) external returns (uint256 amount0, uint256 amount1, uint128 liquidityBurned);

  function getMintAmounts(
    uint256 amount0Max,
    uint256 amount1Max
  ) external view returns (uint256 amount0, uint256 amount1, uint256 mintAmount);

  function getUnderlyingBalances() external view returns (uint256 amount0, uint256 amount1);

  function getPositionID() external view returns (bytes32 positionID);

  function token0() external view returns (address);

  function token1() external view returns (address);

  function upperTick() external view returns (int24);

  function lowerTick() external view returns (int24);

  function pool() external view returns (IUniswapV3Pool);

  function totalSupply() external view returns (uint256);

  function balanceOf(address account) external view returns (uint256);
}

interface IGauge {
  function deposit(uint256 amount, address account) external;

  function withdraw(uint256 amount) external;

  // solhint-disable-next-line func-name-mixedcase
  function claim_rewards(address account) external;

  // solhint-disable-next-line func-name-mixedcase
  function staking_token() external returns (address);
}

interface IXKdkTokenUsage {
  function allocate(address userAddress, uint256 amount, bytes calldata data) external;

  function deallocate(address userAddress, uint256 amount, bytes calldata data) external;
}

interface IxKodiak {
  struct RedeemInfo {
    uint256 kdkAmount; // KDK amount to receive when vesting has ended
    uint256 xKodiakAmount; // xKDK amount to redeem
    uint256 endTime;
    IXKdkTokenUsage rewardsAddress;
    uint256 rewardsAllocation; // Share of redeeming xKDK to allocate to the Rewards Usage contract
  }

  function getUserRedeemsLength(address userAddress) external view returns (uint256);

  function redeem(uint256 xKdkAmount, uint256 duration) external;

  function finalizeRedeem(uint256 redeemIndex) external;

  function getUserRedeem(
    address userAddress,
    uint256 redeemIndex
  )
    external
    view
    returns (
      uint256 kdkAmount,
      uint256 xKdkAmount,
      uint256 endTime,
      address rewardsContract,
      uint256 rewardsAllocation
    );
}

interface IKodiakV1RouterStaking {
  function addLiquidity(
    IKodiakVaultV1 pool,
    uint256 amount0Max,
    uint256 amount1Max,
    uint256 amount0Min,
    uint256 amount1Min,
    uint256 amountSharesMin,
    address receiver
  ) external returns (uint256 amount0, uint256 amount1, uint256 mintAmount);

  function addLiquidityETH(
    IKodiakVaultV1 pool,
    uint256 amount0Max,
    uint256 amount1Max,
    uint256 amount0Min,
    uint256 amount1Min,
    uint256 amountSharesMin,
    address receiver
  ) external payable returns (uint256 amount0, uint256 amount1, uint256 mintAmount);

  function addLiquidityAndStake(
    IGauge gauge,
    uint256 amount0Max,
    uint256 amount1Max,
    uint256 amount0Min,
    uint256 amount1Min,
    uint256 amountSharesMin,
    address receiver
  ) external returns (uint256 amount0, uint256 amount1, uint256 mintAmount);

  function addLiquidityETHAndStake(
    IGauge gauge,
    uint256 amount0Max,
    uint256 amount1Max,
    uint256 amount0Min,
    uint256 amount1Min,
    uint256 amountSharesMin,
    address receiver
  ) external payable returns (uint256 amount0, uint256 amount1, uint256 mintAmount);

  function removeLiquidity(
    IKodiakVaultV1 pool,
    uint256 burnAmount,
    uint256 amount0Min,
    uint256 amount1Min,
    address receiver
  ) external returns (uint256 amount0, uint256 amount1, uint128 liquidityBurned);

  function removeLiquidityETH(
    IKodiakVaultV1 pool,
    uint256 burnAmount,
    uint256 amount0Min,
    uint256 amount1Min,
    address payable receiver
  ) external returns (uint256 amount0, uint256 amount1, uint128 liquidityBurned);

  function removeLiquidityAndUnstake(
    IGauge gauge,
    uint256 burnAmount,
    uint256 amount0Min,
    uint256 amount1Min,
    address receiver
  ) external returns (uint256 amount0, uint256 amount1, uint128 liquidityBurned);

  function removeLiquidityETHAndUnstake(
    IGauge gauge,
    uint256 burnAmount,
    uint256 amount0Min,
    uint256 amount1Min,
    address payable receiver
  ) external returns (uint256 amount0, uint256 amount1, uint128 liquidityBurned);
}
