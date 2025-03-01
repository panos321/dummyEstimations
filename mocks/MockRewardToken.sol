// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockRewardToken is ERC20 {
  constructor() ERC20("Mock Reward Token", "MRT") {
    _mint(msg.sender, 1000000 * 10 ** decimals());
  }

  // Function to mint more tokens if needed
  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}
