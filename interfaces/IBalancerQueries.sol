// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IBeraVault} from "./exchange/Beraswap.sol";

interface IBalancerQueries {
  function querySwap(
    IBeraVault.SingleSwap memory singleSwap,
    IBeraVault.FundManagement memory funds
  ) external returns (uint256);
}
