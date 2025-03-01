// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {StrategyBase} from "./StrategyBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SphereXProtected} from "@spherex-xyz/contracts/src/SphereXProtected.sol";

/**
 * @title GammaStrategy
 * @notice A strategy contract for managing Gamma LP positions
 * @dev This strategy is a basic implementation that holds Gamma LP tokens without additional staking
 * It inherits from StrategyBase and overrides the required functions
 */
contract GammaStrategy is StrategyBase {
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
    address zapperAddress
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
  {}

  /// @notice Deposits tokens into the strategy
  /// @dev This strategy doesn't stake tokens, so this function is a no-op
  function deposit() public override sphereXGuardPublic(0x2d4b1d23, 0xd0e30db0) {
    // no need to deposit anything because we are not staking
  }

  /// @notice Returns the balance of tokens in the strategy's staking pool
  /// @dev This strategy doesn't use a staking pool
  /// @return Amount of tokens in the pool (always 0)
  function balanceOfPool() public view virtual override returns (uint256) {
    // no need to track any balance in the pool
    return 0;
  }

  /// @notice Internal function to withdraw tokens from the strategy
  /// @dev Since there's no staking, this simply returns the requested amount
  /// @param amount Amount of tokens to withdraw
  /// @return The amount of tokens withdrawn
  function _withdrawSome(uint256 amount) internal virtual override sphereXGuardInternal(0x1cf884d7) returns (uint256) {
    // no need to withdraw anything because we are not staking
    return amount;
  }
}
