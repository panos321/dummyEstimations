// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IController} from "./IController.sol";

/**
 * @title IControllerFactory
 * @notice Interface for the ControllerFactory contract that creates Controllers
 */
interface IControllerFactory {
  // Errors
  /// @notice Thrown when a non-dev address attempts to call a dev-only function
  error NotDev();
  /// @notice Thrown when a non-whitelisted-strategy-factory address attempts to create a controller
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
  /// @notice Emitted when a controller is created
  /// @param controller The address of the newly created controller
  event ControllerCreated(address indexed controller);

  // Functions
  /// @notice Creates a new controller
  /// @param asset The asset address for the controller
  /// @param governance The governance address
  /// @param strategist The strategist address
  /// @param timelock The timelock address
  /// @param devfund The dev fund address
  /// @param treasury The treasury address
  /// @return controller The newly created controller
  function createController(
    address asset,
    address governance,
    address strategist,
    address timelock,
    address devfund,
    address treasury,
    address sphereXAdmin,
    address sphereXOperator,
    address sphereXEngine
  ) external returns (IController controller);
}
