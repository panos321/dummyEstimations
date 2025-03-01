// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {StrategyBase} from "./StrategyBase.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";
import {ILpRouter} from "../interfaces/ILpRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SphereXProtected} from "@spherex-xyz/contracts/src/SphereXProtected.sol";
import {IStakingPoolToken, IStakingRewardsDistributor} from "../interfaces/arbera/IArbera.sol";

/**
 * @title ArberaStrategy
 * @notice A strategy contract for managing Arbera LP positions
 * @dev This strategy is a basic implementation that holds Arbera LP tokens without additional staking
 * It inherits from StrategyBase and overrides the required functions
 */
contract ArberaStrategy is StrategyBase {
  using SafeERC20 for IERC20;

  address public rewardToken;

  event RewardTokenChanged(address rewardToken);

  /**
   * @notice Initializes the Arbera strategy
   * @param assetAddress Address of the LP token this strategy manages
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
    address rewardTokenAddress
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
    _revertAddressZero(rewardTokenAddress);
    rewardToken = rewardTokenAddress;
  }

  /**
   * @notice Deposits tokens into the strategy
   */
  function deposit() public override sphereXGuardPublic(0xeefb5ffd, 0xd0e30db0) {
    // zapper already deposits and recieve reciept tokens
  }

  /// @notice Returns the harvestable rewards
  /// @return rewards Addresses of reward tokens
  ///@return amounts Amounts of reward tokens available
  function getHarvestable() external view override returns (address[] memory rewards, uint256[] memory amounts) {
    rewards = new address[](2);
    amounts = new uint256[](2);
    rewards[0] = address(bgt);
    amounts[0] = bgt.balanceOf(address(this));
    rewards[1] = address(asset);
    amounts[1] = IStakingRewardsDistributor(IStakingPoolToken(address(asset)).rewardsDistributor()).getUnpaid(
      rewardToken,
      address(this)
    );
  }

  /// @notice Harvest rewards and convert to asset
  function harvest() public override onlyBenevolent sphereXGuardPublic(0x768b1519, 0x4641257d) {
    uint256 newAssets = _swapBGTToAsset();
    IStakingRewardsDistributor(IStakingPoolToken(address(asset)).rewardsDistributor()).claimReward(address(this));
    uint256 rewardAmount = IERC20(rewardToken).balanceOf(address(this));
    if (rewardAmount > 0) {
      IERC20(rewardToken).safeTransfer(address(swapRouter), rewardAmount);
      // reward token is Arbera here
      swapRouter.swapWithDefaultDex(rewardToken, wrappedNative, rewardAmount, 0, address(this));
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

  /**
   * @notice Returns the balance of tokens in the strategy's staking pool
   * @return Amount of tokens in the pool
   */
  function balanceOfPool() public view virtual override returns (uint256) {
    // no need to track any balance in the pool
    return 0;
  }

  /**
   * @notice Internal function to withdraw tokens from the strategy
   * @param amount Amount of tokens to withdraw
   * @return The amount of tokens withdrawn
   */
  function _withdrawSome(uint256 amount) internal virtual override sphereXGuardInternal(0x84545b2b) returns (uint256) {
    // no need to withdraw anything because we are not staking
    return amount;
  }

  function setRewardToken(address _rewardToken) external onlyGovernance {
    _revertAddressZero(_rewardToken);
    rewardToken = _rewardToken;
    emit RewardTokenChanged(_rewardToken);
  }
}
