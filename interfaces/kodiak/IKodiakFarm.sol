// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

interface IKodiakFarm {
  /* ========== STRUCTS ========== */

  struct LockedStake {
    bytes32 kek_id;
    uint256 start_timestamp;
    uint256 liquidity;
    uint256 ending_timestamp;
    uint256 lock_multiplier; // 6 decimals of precision. 1x = 1000000
  }

  function stakeLocked(uint256 liquidity, uint256 secs) external;

  function withdrawLocked(bytes32 kek_id) external;

  function withdrawLockedAll() external;

  function getReward() external returns (uint256[] memory);

  function lockedStakesOf(address account) external view returns (LockedStake[] memory);

  function lockedLiquidityOf(address account) external view returns (uint256);

  function xKdk() external view returns (address);

  function kdk() external view returns (address);
}
