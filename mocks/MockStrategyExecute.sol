// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockStrategyExecute {
  function write(address token, uint256 amount) public {
    IERC20(token).transfer(msg.sender, amount);
  }
}
