// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BTX is ERC20 {
  constructor(address governance) ERC20("BeraTrax", "BTX") {
    _mint(governance, 2_000_000_000 ether);
  }
}
