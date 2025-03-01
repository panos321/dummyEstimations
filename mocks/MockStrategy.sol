// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StrategyBase} from "../strategies/StrategyBase.sol";
import {IMockStaking} from "./IMockStaking.sol";

contract MockStrategy is StrategyBase {
  IMockStaking public staking;

  constructor(
    address asset,
    address governance,
    address strategist,
    address controller,
    address timelock,
    address wrappedNative,
    address bgtAddress,
    address swapRouter,
    address lpRouter,
    address zapperAddress,
    address stakingAddress
  )
    StrategyBase(
      asset,
      governance,
      strategist,
      controller,
      timelock,
      wrappedNative,
      bgtAddress,
      swapRouter,
      lpRouter,
      zapperAddress
    )
  {
    staking = IMockStaking(stakingAddress);
  }

  function deposit() public override {
    uint256 amount = asset.balanceOf(address(this));
    asset.approve(address(staking), amount);
    staking.deposit(amount, address(this));
  }

  function getHarvestable() external view override returns (address[] memory rewards, uint256[] memory amounts) {
    uint256 rewardAmount = staking.earned(address(this));
    rewards = new address[](1);
    amounts = new uint256[](1);
    rewards[0] = address(staking.rewardToken());
    amounts[0] = rewardAmount;
  }

  function harvest() public override {
    uint256 reward = staking.getReward();
    _distributePerformanceFeesBasedAmountAndDeposit(reward);
    emit Harvest(block.timestamp, reward);
  }

  function balanceOfPool() public view virtual override returns (uint256) {
    return IERC20(address(asset)).balanceOf(address(staking));
  }

  function _withdrawSome(uint256 amount) internal virtual override returns (uint256) {
    return staking.redeem(amount, address(this), address(this));
  }
}
