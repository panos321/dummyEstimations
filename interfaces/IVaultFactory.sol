// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IVault} from "./IVault.sol";

/**
 * @title IVaultFactory
 * @notice Interface for the VaultFactory contract that creates Vaults
 */
interface IVaultFactory {
  // Errors
  /// @notice Thrown when a non-dev address attempts to call a dev-only function
  error NotDev();
  /// @notice Thrown when a non-whitelisted-strategy-factory address attempts to create a vault
  error NotWhitelistedStrategyFactory();
  /// @notice Thrown when attempting to set a zero address
  error ZeroAddress();

  // Events
  /// @notice Emitted when the developer address is updated
  /// @param oldDev The old developer address
  /// @param newDev The new developer address
  event DevChanged(address indexed oldDev, address indexed newDev);
  /// @notice Emitted when the strategy factory address is updated
  /// @param factory The strategy factory address
  /// @param isWhitelisted Whether the strategy factory is whitelisted
  event WhitelistedStrategyFactoryChanged(address indexed factory, bool isWhitelisted);
  /// @notice Emitted when a vault is created
  /// @param vault The address of the newly created vault
  event VaultCreated(address indexed vault);

  // Functions
  /// @notice Creates a new vault and controller pair
  /// @param asset The asset address for the vault
  /// @param governance The governance address
  /// @param strategist The strategist address
  /// @param timelock The timelock address
  /// @param devfund The dev fund address
  /// @param treasury The treasury address
  /// @param controller The controller address
  /// @param sphereXAdmin The SphereX admin address
  /// @param sphereXOperator The SphereX operator address
  /// @param sphereXEngine The SphereX engine address
  /// @param initialDepositFee The initial deposit fee
  /// @param initialWithdrawFee The initial withdraw fee
  /// @return vault The newly created vault
  function createVault(
    address asset,
    address governance,
    address strategist,
    address timelock,
    address devfund,
    address treasury,
    address controller,
    address sphereXAdmin,
    address sphereXOperator,
    address sphereXEngine,
    uint16 initialDepositFee,
    uint16 initialWithdrawFee
  ) external returns (IVault vault);
}
