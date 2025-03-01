// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IVault} from "./IVault.sol";
import {IStrategy} from "./IStrategy.sol";
import {IController} from "./IController.sol";

/**
 * @title IStrategyFactory
 * @notice Interface for the StrategyFactory contract that manages the creation and setup of Vaults and Strategies
 */
interface IStrategyFactory {
  // Errors
  /// @notice Thrown when a zero address is provided
  error ZeroAddress();
  /// @notice Thrown when a non-dev address attempts to call a dev-only function
  error NotDev();
  /// @notice Thrown when attempting to create a vault for an asset that already has one
  error VaultAlreadyExists();
  /// @notice Thrown when strategy bytecode deployment fails validation for asset
  error InvalidAssetInStrategy();

  // Events
  /// @notice Emitted when a new vault is created
  /// @param asset The address of the VaultCreated the vault is for
  /// @param vault The address of the newly created vault
  /// @param strategy The address of the newly created strategy
  /// @param controller The address of the newly created controller
  event VaultCreated(address indexed asset, address indexed vault, address indexed strategy, address controller);
  /// @notice Emitted when the developer address is updated
  /// @param oldDev The old developer address
  /// @param newDev The new developer address
  event DevChanged(address indexed oldDev, address indexed newDev);
  /// @notice Emitted when the vault factory address is updated
  /// @param oldFactory The old factory address
  /// @param newFactory The new factory address
  event VaultFactoryChanged(address indexed oldFactory, address indexed newFactory);
  /// @notice Emitted when the controller factory address is updated
  /// @param oldFactory The old factory address
  /// @param newFactory The new factory address
  event ControllerFactoryChanged(address indexed oldFactory, address indexed newFactory);
  /// @notice Emitted when vault data is manually set
  /// @param asset The asset address
  /// @param vault The vault address
  /// @param controller The controller address
  /// @param strategy The strategy address
  event VaultDataChanged(address indexed asset, address indexed vault, address indexed controller, address strategy);
  /// @notice Emitted when the spherex engine address is changed
  /// @param oldEngineAddress The old engine address
  /// @param newEngineAddress The new engine address
  event ChangedSpherexEngineAddress(address oldEngineAddress, address newEngineAddress);
  // Structs
  /**
   * @notice Struct to hold parameters for creating a vault
   * @param asset The Asset address for the vault
   * @param governance Address of the governance
   * @param strategist Address of the strategist
   * @param timelock Address of the timelock
   * @param devfund Address of the dev fund
   * @param treasury Address of the treasury
   * @param wrappedNative Address of the wrapped native token
   * @param swapRouter Address of the swap router
   * @param lpRouter Address of the lp router
   * @param strategyContractCode The bytecode of the strategy contract
   * @param strategyExtraParams Additional parameters for strategy initialization
   */
  struct VaultCreateParams {
    address asset;
    address governance;
    address strategist;
    address timelock;
    address devfund;
    address treasury;
    address wrappedNative;
    address bgt;
    address swapRouter;
    address lpRouter;
    address zapper;
    uint16 initialDepositFee;
    uint16 initialWithdrawFee;
    bytes strategyContractCode;
    bytes strategyExtraParams;
  }

  // Functions
  /// @notice Maps asset addresses to their corresponding vault addresses
  function vaults(address asset) external view returns (address);

  /// @notice Maps vault addresses to their corresponding controller addresses
  function controllers(address vault) external view returns (address);

  /// @notice Maps vault addresses to their corresponding strategy addresses
  function strategies(address vault) external view returns (address);

  /// @notice Creates a new vault with corresponding controller and strategy
  function createVault(
    VaultCreateParams calldata params
  ) external returns (IVault vault, IController controller, IStrategy strategy);
}
