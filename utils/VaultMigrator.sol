// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "../localdeps/Ownable.sol";
import {IVault} from "../interfaces/IVault.sol";
import {SphereXProtected} from "@spherex-xyz/contracts/src/SphereXProtected.sol";

contract VaultMigrator is Ownable {
    using SafeERC20 for IERC20;

    constructor(address _owner) Ownable(_owner) {}

    function migrate(address owner, IVault oldVault, IVault newVault, uint256 amount)
        external
        onlyOwner
        sphereXGuardExternal(0xe6e91616)
    {
        uint256 assets = oldVault.redeem(amount, address(this), owner);
        IERC20(oldVault.asset()).forceApprove(address(newVault), assets);
        newVault.deposit(assets, owner);
    }

    function rescueTokens(IERC20 token, address recipient, uint256 amount)
        external
        onlyOwner
        sphereXGuardExternal(0x9e8aed1b)
    {
        token.safeTransfer(recipient, amount);
    }

    function rescueEth(address payable recipient, uint256 amount) external onlyOwner sphereXGuardExternal(0x8ef639dd) {
        recipient.transfer(amount);
    }
}
