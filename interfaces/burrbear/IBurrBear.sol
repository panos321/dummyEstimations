// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRewarder {
  function onRewardTokenReward(
    uint256 pid,
    address user,
    address recipient,
    uint256 rewardTokenAmount,
    uint256 newLpAmount
  ) external;

  function viewPendingTokens(
    uint256 pid,
    address user,
    uint256 rewardTokenAmount
  ) external view returns (IERC20[] memory, uint256[] memory);
}

interface IBurrBear {
  // Struct definitions matching the contract
  struct PoolInfo {
    uint256 accRewardTokenPerShare;
    uint256 lastRewardTime;
    uint256 allocPoint;
  }

  struct UserInfo {
    uint256 amount;
    int256 rewardDebt;
  }

  // Public variable getters
  function REWARD_TOKEN() external view returns (IERC20);

  function poolInfo(
    uint256
  ) external view returns (uint256 accRewardTokenPerShare, uint256 lastRewardTime, uint256 allocPoint);

  function lpToken(uint256) external view returns (IERC20);

  function rewarder(uint256) external view returns (IRewarder);

  function totalAllocPoint() external view returns (uint256);

  function rewardTokenPerSecond() external view returns (uint256);

  function rewardsManager() external view returns (address);

  function userInfo(uint256, address) external view returns (uint256 amount, int256 rewardDebt);

  // Function declarations
  function poolLength() external view returns (uint256);

  function add(uint256 allocPoint, IERC20 _lpToken, IRewarder _rewarder) external;

  function set(uint256 _pid, uint256 _allocPoint, IRewarder _rewarder, bool overwrite) external;

  function setRewardTokenPerSecond(uint256 rewardTokenPerSecond_) external;

  function pendingRewardToken(uint256 _pid, address _user) external view returns (uint256 pending);

  function massUpdatePools(uint256[] calldata pids) external;

  function updatePool(uint256 pid) external returns (PoolInfo memory pool);

  function deposit(uint256 pid, uint256 amount, address to) external;

  function withdraw(uint256 pid, uint256 amount, address to) external;

  function harvest(uint256 pid, address to) external;

  function withdrawAndHarvest(uint256 pid, uint256 amount, address to) external;

  function emergencyWithdraw(uint256 pid, address to) external;

  function setRewardsManager(address _rewardsManager) external;

  // (Optional) Event declarations, if needed by external indexing services.
  event Deposit(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
  event Withdraw(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
  event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
  event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
  event LogPoolAddition(uint256 indexed pid, uint256 allocPoint, IERC20 indexed lpToken, IRewarder indexed rewarder);
  event LogSetPool(uint256 indexed pid, uint256 allocPoint, IRewarder indexed rewarder, bool overwrite);
  event LogUpdatePool(uint256 indexed pid, uint256 lastRewardTime, uint256 lpSupply, uint256 accRewardTokenPerShare);
  event LogRewardTokenPerSecond(uint256 rewardTokenPerSecond);
}
