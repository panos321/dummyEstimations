// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IVault} from "../interfaces/IVault.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IController} from "../interfaces/IController.sol";
import {IStrategyFactory} from "../interfaces/IStrategyFactory.sol";
import {IVaultFactory} from "../interfaces/IVaultFactory.sol";
import {IControllerFactory} from "../interfaces/IControllerFactory.sol";
import {SphereXConfiguration} from "@spherex-xyz/contracts/src/SphereXConfiguration.sol";
import {ISphereXEngine} from "@spherex-xyz/contracts/src/ISphereXEngine.sol";

/**
 * @title StrategyFactoryBase
 * @notice Base contract for creating protocol-specific strategy factories
 */
abstract contract StrategyFactoryBase is IStrategyFactory {
  /// @notice Mapping from asset address to its corresponding vault
  mapping(address asset => address vault) public vaults;

  /// @notice Mapping from vault address to its corresponding controller
  mapping(address vault => address controller) public controllers;

  /// @notice Mapping from vault address to its corresponding strategy
  mapping(address vault => address strategy) public strategies;

  /// @notice Address of the developer/admin who can create vaults and update settings
  address public dev;

  /// @notice Factory contract for creating vaults
  IVaultFactory public vaultFactory;

  /// @notice Factory contract for creating controllers
  IControllerFactory public controllerFactory;

  address public sphereXEngine;

  constructor(
    address devAddress,
    address vaultFactoryAddress,
    address controllerFactoryAddress,
    address sphereXEngineAddress
  ) {
    _revertAddressZero(devAddress);
    _revertAddressZero(vaultFactoryAddress);
    _revertAddressZero(controllerFactoryAddress);
    _revertAddressZero(sphereXEngineAddress);
    dev = devAddress;
    vaultFactory = IVaultFactory(vaultFactoryAddress);
    controllerFactory = IControllerFactory(controllerFactoryAddress);
    sphereXEngine = sphereXEngineAddress;
  }

  function revertOnlyDev() private view {
    if (msg.sender != dev) revert NotDev();
  }

  /// @notice Restricts function access to only the dev address
  modifier onlyDev() {
    revertOnlyDev();
    _;
  }

  /// @notice Ensures vault doesn't already exist for the given asset
  modifier onlyNewAsset(address asset) {
    if (vaults[asset] != address(0)) revert VaultAlreadyExists();
    _;
  }

  function _revertAddressZero(address addressToCheck) internal pure {
    if (addressToCheck == address(0)) revert ZeroAddress();
  }

  /// @notice Updates the dev address
  /// @param devAddress New dev address
  function setDev(address devAddress) external onlyDev {
    _revertAddressZero(devAddress);
    address old = dev;
    dev = devAddress;
    emit DevChanged(old, devAddress);
  }

  /// @notice Updates the spherex engine address
  /// @param sphereXEngineAddress The new engine address
  function setSphereXEngine(address sphereXEngineAddress) external onlyDev {
    _revertAddressZero(sphereXEngineAddress);
    address old = sphereXEngine;
    sphereXEngine = sphereXEngineAddress;
    emit ChangedSpherexEngineAddress(old, sphereXEngineAddress);
  }

  /// @notice Updates the vault and controller factory address
  /// @param factoryAddress New factory address
  function setVaultFactory(address factoryAddress) external onlyDev {
    _revertAddressZero(factoryAddress);
    address old = address(vaultFactory);
    vaultFactory = IVaultFactory(factoryAddress);
    emit VaultFactoryChanged(old, factoryAddress);
  }

  /// @notice Updates the controller factory address
  /// @param factoryAddress New factory address
  function setControllerFactory(address factoryAddress) external onlyDev {
    _revertAddressZero(factoryAddress);
    address old = address(controllerFactory);
    controllerFactory = IControllerFactory(factoryAddress);
    emit ControllerFactoryChanged(old, factoryAddress);
  }

  /**
   * @notice Sets an address as SphereX protected
   * @param protected The address to be protected
   */
  function _setAddressAsSpherexProtected(address protected) internal {
    ISphereXEngine(sphereXEngine).addAllowedSenderOnChain(protected);
    SphereXConfiguration(protected).changeSphereXOperator(address(this));
    SphereXConfiguration(protected).changeSphereXEngine(sphereXEngine);
    SphereXConfiguration(protected).changeSphereXOperator(dev);
    SphereXConfiguration(protected).transferSphereXAdminRole(dev);
  }

  /**
   * @notice Internal function to create a new controller and vault
   * @param asset The token address for the vault
   * @param governanceAddress Address of the governance
   * @param strategistAddress Address of the strategist
   * @param timelockAddress Address of the timelock
   * @param devfundAddress Address of the dev fund
   * @param treasuryAddress Address of the treasury
   * @return controller The newly created controller
   * @return vault The newly created vault
   */
  function _createControllerAndVault(
    address asset,
    address governanceAddress,
    address strategistAddress,
    address timelockAddress,
    address devfundAddress,
    address treasuryAddress,
    uint16 initialDepositFee,
    uint16 initialWithdrawFee
  ) internal returns (IController controller, IVault vault) {
    controller = controllerFactory.createController(
      asset,
      governanceAddress,
      strategistAddress,
      timelockAddress,
      devfundAddress,
      treasuryAddress,
      dev,
      dev,
      sphereXEngine
    );
    vault = vaultFactory.createVault(
      asset,
      governanceAddress,
      strategistAddress,
      timelockAddress,
      devfundAddress,
      treasuryAddress,
      address(controller),
      dev,
      dev,
      sphereXEngine,
      initialDepositFee,
      initialWithdrawFee
    );
    ISphereXEngine(sphereXEngine).addAllowedSenderOnChain(address(controller));
    ISphereXEngine(sphereXEngine).addAllowedSenderOnChain(address(vault));
  }

  /**
   * @notice Internal function to set up vault relationships and permissions
   * @param asset The asset address for the vault
   * @param vault The vault instance
   * @param strategy The strategy instance
   * @param controller The controller instance
   * @param governanceAddress Address of the governance
   * @param timelockAddress Address of the timelock
   */
  function _setupVault(
    address asset,
    IVault vault,
    IStrategy strategy,
    IController controller,
    address governanceAddress,
    address timelockAddress
  ) internal {
    if (
      asset == address(0) ||
      address(vault) == address(0) ||
      address(strategy) == address(0) ||
      address(controller) == address(0) ||
      governanceAddress == address(0) ||
      timelockAddress == address(0)
    ) revert ZeroAddress();

    vaults[asset] = address(vault);
    controllers[address(vault)] = address(controller);
    strategies[address(vault)] = address(strategy);

    // set vault and strategy in controller
    controller.setVault(asset, address(vault));
    controller.approveStrategy(asset, address(strategy));
    controller.setStrategy(asset, address(strategy));

    // set back the governance and timelock in controller
    controller.setGovernance(governanceAddress);
    controller.setTimelock(timelockAddress);
  }

  /**
   * @notice Reverts if any of the parameters are zero
   * @param params The parameters to check
   */
  function revertIfNonInitializedParams(VaultCreateParams calldata params) private pure {
    if (
      params.asset == address(0) ||
      params.governance == address(0) ||
      params.strategist == address(0) ||
      params.timelock == address(0) ||
      params.devfund == address(0) ||
      params.treasury == address(0) ||
      params.wrappedNative == address(0) ||
      params.swapRouter == address(0) ||
      params.lpRouter == address(0) ||
      params.zapper == address(0) ||
      params.bgt == address(0)
    ) revert ZeroAddress();
  }

  /**
   * @notice Encodes the parameters and controller address into a bytes array
   * @param params The parameters to encode
   * @param controller The controller address
   * @return The encoded bytes array
   */
  function _encodeParamsAndController(
    VaultCreateParams calldata params,
    address controller
  ) private pure returns (bytes memory) {
    return
      abi.encode(
        params.asset,
        params.governance,
        params.strategist,
        controller,
        params.timelock,
        params.wrappedNative,
        params.bgt,
        params.swapRouter,
        params.lpRouter,
        params.zapper
      );
  }

  /**
   * @notice Creates a new vault with associated controller and strategy
   * @param params The parameters for creating the vault
   * @return vault The newly created vault
   * @return controller The newly created controller
   * @return strategy The newly created strategy
   */
  function createVault(
    VaultCreateParams calldata params
  ) external onlyDev onlyNewAsset(params.asset) returns (IVault vault, IController controller, IStrategy strategy) {
    revertIfNonInitializedParams(params);

    (controller, vault) = _createControllerAndVault(
      params.asset,
      params.governance,
      params.strategist,
      params.timelock,
      params.devfund,
      params.treasury,
      params.initialDepositFee,
      params.initialWithdrawFee
    );
    strategy = _deployStrategyByteCode(
      params.strategyContractCode,
      _encodeParamsAndController(params, address(controller)),
      params.strategyExtraParams,
      params.asset
    );
    _setupVault(params.asset, vault, strategy, controller, params.governance, params.timelock);
    emit VaultCreated(params.asset, address(vault), address(strategy), address(controller));
  }

  /**
   * @notice Deploys a new strategy contract using provided bytecode
   * @param strategyCode The bytecode of the strategy contract
   * @param encodedParams Encoded constructor parameters
   * @param strategyParams Additional parameters for strategy initialization
   * @param asset The asset address the strategy will manage
   * @return strategy The newly created strategy instance
   */
  function _deployStrategyByteCode(
    bytes memory strategyCode,
    bytes memory encodedParams,
    bytes memory strategyParams,
    address asset
  ) internal returns (IStrategy strategy) {
    address strategyAddress;
    bytes memory bytecode = bytes.concat(
      strategyCode,
      encodedParams,
      strategyParams // Additional arbitrary parameters
    );
    assembly {
      strategyAddress := create(0, add(bytecode, 0x20), mload(bytecode))

      if iszero(extcodesize(strategyAddress)) {
        revert(0, 0)
      }
    }
    strategy = IStrategy(strategyAddress);
    _setAddressAsSpherexProtected(address(strategy));
    if (address(strategy.asset()) != asset) revert InvalidAssetInStrategy();
  }
}
