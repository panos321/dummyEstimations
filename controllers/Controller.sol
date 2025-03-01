// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IController} from "../interfaces/IController.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SphereXProtected} from "@spherex-xyz/contracts/src/SphereXProtected.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Controller Contract
/// @notice Manages the relationship between vaults and their investment strategies
/// @dev Controls the flow of funds between vaults and strategies, and handles administrative functions
contract Controller is SphereXProtected, ReentrancyGuard, IController {
  using SafeERC20 for IERC20;
  using Address for address;

  /// @notice Maps asset addresses to their associated vault addresses
  mapping(address => address) public vaults;

  /// @notice Maps asset addresses to their associated strategy addresses
  mapping(address => address) public strategies;

  /// @notice Maps asset addresses to approved strategies for that asset
  mapping(address => mapping(address => bool)) public approvedStrategies;

  /// @notice Address with highest privilege level (can change other roles)
  address public governance;

  /// @notice Address that can manage strategies and vaults
  address public strategist;

  /// @notice Address that receives development fees
  address public devfund;

  /// @notice Address that receives treasury fees
  address public treasury;

  /// @notice Address that can approve strategies and execute time-sensitive operations
  address public timelock;

  /// @notice Initializes the controller with all required addresses
  /// @param governanceAddress Address that will have governance rights
  /// @param strategistAddress Address that will have strategist rights
  /// @param timelockAddress Address that will have timelock rights
  /// @param devfundAddress Address that will receive dev fees
  /// @param treasuryAddress Address that will receive treasury fees
  constructor(
    address governanceAddress,
    address strategistAddress,
    address timelockAddress,
    address devfundAddress,
    address treasuryAddress
  ) {
    if (
      governanceAddress == address(0) ||
      strategistAddress == address(0) ||
      timelockAddress == address(0) ||
      devfundAddress == address(0) ||
      treasuryAddress == address(0)
    ) revert ZeroAddress();

    governance = governanceAddress;
    strategist = strategistAddress;
    timelock = timelockAddress;
    devfund = devfundAddress;
    treasury = treasuryAddress;
  }

  // **** Modifiers **** //

  /// @notice Ensures that only the governance address can call the function
  /// @dev Reverts with NotGovernance if caller is not the governance address
  modifier onlyGovernance() {
    _revertOnlyGovernance();
    _;
  }

  /// @notice Ensures that only the strategist or governance address can call the function
  /// @dev Reverts with NotStrategist if caller is neither strategist nor governance
  modifier onlyStrategist() {
    _revertOnlyStrategist();
    _;
  }

  /// @notice Ensures that only the timelock address can call the function
  /// @dev Reverts with NotTimelock if caller is not the timelock address
  modifier onlyTimelock() {
    _revertOnlyTimelock();
    _;
  }

  /// @notice Ensures that only the vault associated with the given asset can call the function
  /// @dev Reverts with NotVault if caller is not the vault address for the asset
  /// @param asset The address of the asset whose vault is authorized
  modifier onlyVault(address asset) {
    if (msg.sender != vaults[asset]) revert NotVault();
    _;
  }

  // **** Internal Functions **** //
  /// @notice Reverts if the address is zero
  /// @param _address The address to check
  function _revertAddressZero(address _address) internal pure {
    if (_address == address(0)) revert ZeroAddress();
  }

  /// @notice Reverts if either of the addresses is zero
  /// @param _address The first address to check
  /// @param _address2 The second address to check
  function _revertOneAddressZero(address _address, address _address2) internal pure {
    if (_address == address(0) || _address2 == address(0)) revert ZeroAddress();
  }

  /// @notice Reverts if the caller is not the governance address
  /// @dev Reverts with NotGovernance if caller is not the governance address
  function _revertOnlyGovernance() internal view {
    if (msg.sender != governance) revert NotGovernance();
  }

  /// @notice Reverts if the caller is not the strategist or governance address
  /// @dev Reverts with NotStrategist if caller is neither strategist nor governance
  function _revertOnlyStrategist() internal view {
    if (msg.sender != strategist && msg.sender != governance) revert NotStrategist();
  }

  /// @notice Reverts if the caller is not the timelock address
  /// @dev Reverts with NotTimelock if caller is not the timelock address
  function _revertOnlyTimelock() internal view {
    if (msg.sender != timelock) revert NotTimelock();
  }

  /// @notice Sets a new developer fund address
  /// @param devfundAddress The new developer fund address
  function setDevFund(address devfundAddress) public onlyGovernance sphereXGuardPublic(0x52c095ea, 0xae4db919) {
    _revertAddressZero(devfundAddress);
    address old = devfund;
    devfund = devfundAddress;
    emit DevFundChanged(old, devfundAddress);
  }

  /// @notice Sets a new treasury address
  /// @param treasuryAddress The new treasury address
  function setTreasury(address treasuryAddress) public onlyGovernance sphereXGuardPublic(0x66c5557d, 0xf0f44260) {
    _revertAddressZero(treasuryAddress);
    address old = treasury;
    treasury = treasuryAddress;
    emit TreasuryChanged(old, treasuryAddress);
  }

  /// @notice Sets a new strategist address
  /// @param strategistAddress The new strategist address
  function setStrategist(address strategistAddress) public onlyGovernance sphereXGuardPublic(0x15f23c15, 0xc7b9d530) {
    _revertAddressZero(strategistAddress);
    address old = strategist;
    strategist = strategistAddress;
    emit StrategistChanged(old, strategistAddress);
  }

  /// @notice Sets a new governance address
  /// @param governanceAddress The new governance address
  function setGovernance(address governanceAddress) public onlyGovernance sphereXGuardPublic(0xefc74f14, 0xab033ea9) {
    _revertAddressZero(governanceAddress);
    address old = governance;
    governance = governanceAddress;
    emit GovernanceChanged(old, governanceAddress);
  }

  /// @notice Sets a new timelock address
  /// @param timelockAddress The new timelock address
  function setTimelock(address timelockAddress) public onlyTimelock sphereXGuardPublic(0xdecf35e6, 0xbdacb303) {
    _revertAddressZero(timelockAddress);
    address old = timelock;
    timelock = timelockAddress;
    emit TimelockChanged(old, timelockAddress);
  }

  /// @notice Associates a vault with a asset
  /// @param asset The asset address
  /// @param vault The vault address to be associated
  function setVault(address asset, address vault) public onlyStrategist sphereXGuardPublic(0xcaa9945a, 0x714ccf7b) {
    _revertOneAddressZero(asset, vault);
    if (vaults[asset] != address(0)) revert VaultAlreadySet();
    vaults[asset] = vault;
    emit VaultSet(asset, vault);
  }

  /// @notice Approves a strategy for a asset
  /// @param asset The asset address
  /// @param strategy The strategy address to approve
  function approveStrategy(
    address asset,
    address strategy
  ) public onlyTimelock sphereXGuardPublic(0x473786e1, 0xc494448e) {
    _revertOneAddressZero(asset, strategy);
    approvedStrategies[asset][strategy] = true;
    emit StrategyApproved(asset, strategy);
  }

  /// @notice Revokes approval for a strategy
  /// @param asset The asset address
  /// @param strategy The strategy address to revoke
  function revokeStrategy(
    address asset,
    address strategy
  ) public onlyGovernance sphereXGuardPublic(0x5aad83eb, 0x590bbb60) {
    _revertOneAddressZero(asset, strategy);
    if (strategies[asset] == strategy) revert CannotRevokeActiveStrategy();
    approvedStrategies[asset][strategy] = false;
    emit StrategyRevoked(asset, strategy);
  }

  /// @notice Sets the active strategy for a asset
  /// @param asset The asset address
  /// @param strategy The strategy address to set
  function setStrategy(
    address asset,
    address strategy
  ) public nonReentrant onlyStrategist sphereXGuardPublic(0x632853be, 0x72cb5d97) {
    _revertOneAddressZero(asset, strategy);
    if (!approvedStrategies[asset][strategy]) revert StrategyNotApproved();

    address current = strategies[asset];
    strategies[asset] = strategy;
    if (current != address(0)) {
      IStrategy(current).withdrawAll();
    }
    emit StrategySet(asset, strategy);
  }

  /// @notice Moves assets from the controller to the strategy
  /// @param asset The asset address
  /// @param amount The amount to move
  function earn(address asset, uint256 amount) public nonReentrant sphereXGuardPublic(0x95d37ef9, 0xb02bf4b9) {
    _revertAddressZero(asset);
    if (amount > 0) {
      address strategy = strategies[asset];
      if (strategy == address(0)) revert StrategyNotFound();
      IERC20(asset).safeTransfer(strategy, amount);
      IStrategy(strategy).deposit();
      emit Earned(asset, amount);
    }
  }

  /// @notice Gets the balance of a asset in its strategy
  /// @param asset The asset address
  /// @return The balance amount
  function balanceOf(address asset) external view returns (uint256) {
    return IStrategy(strategies[asset]).balanceOf();
  }

  /// @notice Withdraws all assets from a strategy to the vault
  /// @param asset The asset address
  function withdrawAll(address asset) public nonReentrant onlyStrategist sphereXGuardPublic(0x1ff9f9b6, 0xfa09e630) {
    IStrategy(strategies[asset]).withdrawAll();
    emit WithdrawnAll(asset);
  }

  /// @notice Emergency function to recover stuck assets
  /// @param asset The asset address
  /// @param amount The amount to recover
  function inCaseTokensGetStuck(
    address asset,
    uint256 amount
  ) public onlyGovernance sphereXGuardPublic(0x2e0969b5, 0xc6d758cb) {
    IERC20(asset).safeTransfer(msg.sender, amount);
    emit TokensRecovered(asset, amount);
  }

  /// @notice Emergency function to recover assets stuck in a strategy
  /// @param strategy The strategy address
  /// @param asset The asset address
  function inCaseStrategyTokenGetStuck(
    address strategy,
    address asset
  ) public onlyGovernance sphereXGuardPublic(0x8908950d, 0x197baa6d) {
    IStrategy(strategy).withdraw(asset);
    emit StrategyTokensRecovered(strategy, asset);
  }

  /// @notice Withdraws assets from a strategy to the vault
  /// @param asset The asset address
  /// @param amount The amount to withdraw
  function withdraw(
    address asset,
    uint256 amount
  ) public nonReentrant onlyVault(asset) sphereXGuardPublic(0xc9d9b7a1, 0xf3fef3a3) {
    IStrategy(strategies[asset]).withdraw(amount);
    emit Withdrawn(asset, amount);
  }
}
