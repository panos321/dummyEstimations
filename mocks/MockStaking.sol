// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IMockStaking} from "./IMockStaking.sol";

interface IRewardToken is IERC20 {
  function mint(address to, uint256 amount) external;
}

contract MockStaking is IMockStaking, ERC4626, ReentrancyGuard {
  using SafeERC20 for IERC20;

  // Reward token
  address public immutable rewardToken;

  // Mock reward rate (tokens per second)
  uint256 public rewardRate = 1e18;

  // Last update time
  uint256 public lastUpdateTime;

  // Reward per token stored
  uint256 public rewardPerTokenStored;

  // User reward per token paid
  mapping(address => uint256) public userRewardPerTokenPaid;

  // User rewards
  mapping(address => uint256) public rewards;

  constructor(IERC20 asset, address rewardTokenAddress) ERC4626(asset) ERC20("Mock Staking Shares", "mSTK") {
    rewardToken = rewardTokenAddress;
    lastUpdateTime = block.timestamp;
  }

  // Function to fund the contract with rewards
  function fundRewards(uint256 amount) external {
    require(amount > 0, "Cannot fund 0");
    IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), amount);
  }

  // Mock function to set reward rate
  function setRewardRate(uint256 newRewardRate) external {
    rewardRate = newRewardRate;
    _updateReward(msg.sender);
  }

  function _updateReward(address account) internal {
    rewardPerTokenStored = rewardPerToken();
    lastUpdateTime = block.timestamp;

    if (account != address(0)) {
      rewards[account] = earned(account);
      userRewardPerTokenPaid[account] = rewardPerTokenStored;
    }
  }

  function rewardPerToken() public view returns (uint256) {
    if (totalSupply() == 0) {
      return rewardPerTokenStored;
    }
    return rewardPerTokenStored + (((block.timestamp - lastUpdateTime) * rewardRate * 1e18) / totalSupply());
  }

  function earned(address account) public view returns (uint256) {
    return ((balanceOf(account) * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) + rewards[account];
  }

  // Override deposit function to update rewards
  function deposit(uint256 assets, address receiver) public virtual override(ERC4626, IMockStaking) returns (uint256) {
    _updateReward(receiver);
    return super.deposit(assets, receiver);
  }

  // Override withdraw function to update rewards
  function withdraw(
    uint256 assets,
    address receiver,
    address owner
  ) public virtual override(ERC4626, IMockStaking) returns (uint256) {
    _updateReward(owner);
    return super.withdraw(assets, receiver, owner);
  }

  // Override mint function to update rewards
  function mint(uint256 shares, address receiver) public virtual override returns (uint256) {
    _updateReward(receiver);
    return super.mint(shares, receiver);
  }

  // Override redeem function to update rewards
  function redeem(
    uint256 shares,
    address receiver,
    address owner
  ) public virtual override(ERC4626, IMockStaking) returns (uint256) {
    _updateReward(owner);
    return super.redeem(shares, receiver, owner);
  }

  // Updated getReward function to actually transfer rewards
  function getReward() external nonReentrant returns (uint256 reward) {
    _updateReward(msg.sender);
    reward = rewards[msg.sender];
    if (reward > 0) {
      rewards[msg.sender] = 0;
      IRewardToken(rewardToken).mint(msg.sender, reward);
    }
    return reward;
  }

  // View function to check reward token balance
  function rewardTokenBalance() external view returns (uint256) {
    return IERC20(rewardToken).balanceOf(address(this));
  }
}
