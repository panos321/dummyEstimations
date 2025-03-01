// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBeradromeStaking {
  function depositFor(address account, uint256 amount) external;

  function withdrawTo(address account, uint256 amount) external;

  function balanceOf(address account) external view returns (uint256);
}

interface IBeradromeGauge {
  function getReward(address account) external;

  function rewardTokens(uint256 index) external view returns (address);

  function earned(address account, address _rewardsToken) external view returns (uint256);
}
