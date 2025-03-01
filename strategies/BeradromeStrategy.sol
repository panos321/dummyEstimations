// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {StrategyBase} from "./StrategyBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IBeradromeGauge, IBeradromeStaking} from "../interfaces/beradrome/IBeradrome.sol";
import {SphereXProtected} from "@spherex-xyz/contracts/src/SphereXProtected.sol";

/**
 * @title BeradromeStrategy
 * @notice A strategy contract for managing Gamma LP positions
 * @dev This strategy is a basic implementation that holds Gamma LP tokens without additional staking
 * It inherits from StrategyBase and overrides the required functions
 */
contract BeradromeStrategy is StrategyBase {
  using SafeERC20 for IERC20;

  IBeradromeStaking public staking;
  IBeradromeGauge public gauge;
  uint256 public rewardTokensLength = 1;

  error ZeroRewardTokens();

  /**
   * @notice Initializes the Gamma strategy
   * @param assetAddress Address of the Asset token this strategy manages
   * @param governanceAddress Address of the governance controller
   * @param strategistAddress Address of the strategist
   * @param controllerAddress Address of the controller contract
   * @param timelockAddress Address of the timelock contract
   * @param wrappedNativeAddress Address of the wrapped native token
   * @param swapRouterAddress Address of the swap router
   * @param lpRouterAddress Address of the lp router
   */
  constructor(
    address assetAddress,
    address governanceAddress,
    address strategistAddress,
    address controllerAddress,
    address timelockAddress,
    address wrappedNativeAddress,
    address bgtAddress,
    address swapRouterAddress,
    address lpRouterAddress,
    address zapperAddress,
    address gaugeAddress,
    address stakingAddress
  )
    StrategyBase(
      assetAddress,
      governanceAddress,
      strategistAddress,
      controllerAddress,
      timelockAddress,
      wrappedNativeAddress,
      bgtAddress,
      swapRouterAddress,
      lpRouterAddress,
      zapperAddress
    )
  {
    _revertAddressZero(gaugeAddress);
    _revertAddressZero(stakingAddress);

    gauge = IBeradromeGauge(gaugeAddress);
    staking = IBeradromeStaking(stakingAddress);
  }

  function setGuage(address gaugeAddress) external onlyGovernance sphereXGuardExternal(0x1735ff36) {
    _revertAddressZero(gaugeAddress);
    gauge = IBeradromeGauge(gaugeAddress);
  }

  function setStaking(address stakingAddress) external onlyGovernance sphereXGuardExternal(0xaea0e38b) {
    _revertAddressZero(stakingAddress);
    staking = IBeradromeStaking(stakingAddress);
  }

  function setRewardTokensLength(uint256 rewardTokensCount) external onlyGovernance sphereXGuardExternal(0x58dcc3db) {
    if (rewardTokensCount == 0) revert ZeroRewardTokens();
    rewardTokensLength = rewardTokensCount;
  }

  /// @notice Deposits tokens into the strategy
  function deposit() public override nonReentrant sphereXGuardPublic(0xf0bb7ac9, 0xd0e30db0) {
    uint256 balance = IERC20(asset).balanceOf(address(this));
    IERC20(asset).forceApprove(address(staking), balance);
    staking.depositFor(address(this), balance);
  }

  /// @notice Returns the harvestable rewards
  /// @return rewards Addresses of reward tokens
  ///@return amounts Amounts of reward tokens available
  function getHarvestable() external view override returns (address[] memory rewards, uint256[] memory amounts) {
    rewards = new address[](rewardTokensLength + 1);
    amounts = new uint256[](rewardTokensLength + 1);
    for (uint256 i = 0; i < rewardTokensLength; i++) {
      rewards[i] = gauge.rewardTokens(i);
      amounts[i] = gauge.earned(address(this), rewards[i]);
    }
    rewards[rewardTokensLength] = address(bgt);
    amounts[rewardTokensLength] = bgt.balanceOf(address(this));
  }

  /// @notice Harvest rewards and convert to asset
  function harvest() public override onlyBenevolent sphereXGuardPublic(0x768b1519, 0x4641257d) {
    uint256 newAssets = _swapBGTToAsset();
    gauge.getReward(address(this));
    for (uint256 i = 0; i < rewardTokensLength; i++) {
      address rewardToken = gauge.rewardTokens(i);
      uint256 rewardAmount = IERC20(rewardToken).balanceOf(address(this));
      if (rewardAmount > 0) {
        IERC20(rewardToken).safeTransfer(address(swapRouter), rewardAmount);
        // reward token is oBERO here
        swapRouter.swapWithDefaultDex(rewardToken, wrappedNative, rewardAmount, 0, address(this));
      }
    }
    uint256 balance = IERC20(wrappedNative).balanceOf(address(this));
    if (balance > 0) {
      IERC20(wrappedNative).forceApprove(address(zapper), balance);
      (uint256 amount, ) = zapper.swapToAssets(address(asset), address(wrappedNative), balance, address(this));
      newAssets += amount;
    }

    _distributePerformanceFeesBasedAmountAndDeposit(newAssets);
    emit Harvest(block.timestamp, newAssets);
  }

  /// @notice Returns the balance of tokens in the strategy's staking pool
  /// @return Amount of tokens in the pool (always 0)
  function balanceOfPool() public view virtual override returns (uint256) {
    return staking.balanceOf(address(this));
  }

  /// @notice Internal function to withdraw tokens from the strategy
  /// @param amount Amount of tokens to withdraw
  /// @return The amount of tokens withdrawn
  function _withdrawSome(uint256 amount) internal virtual override sphereXGuardInternal(0x757cb910) returns (uint256) {
    uint256 balanceBefore = IERC20(asset).balanceOf(address(this));
    staking.withdrawTo(address(this), amount);
    uint256 balanceAfter = IERC20(asset).balanceOf(address(this));
    return balanceAfter - balanceBefore;
  }
}
