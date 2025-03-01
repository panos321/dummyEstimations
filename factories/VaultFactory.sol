// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Vault} from "../vaults/Vault.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IVaultFactory} from "../interfaces/IVaultFactory.sol";
import {SphereXConfiguration} from "@spherex-xyz/contracts/src/SphereXConfiguration.sol";
import {SphereXProtectedBase} from "@spherex-xyz/contracts/src/SphereXProtectedBase.sol";

/**
 * @title VaultFactory
 * @notice Factory contract for creating Vaults
 */
contract VaultFactory is SphereXProtectedBase, IVaultFactory {
  /// @notice Address of the strategy factory that is authorized to create vaults
  /// @dev Only this address can call createVault
  mapping(address strategyFactory => bool isWhitelisted) public whitelistedStrategyFactories;

  /// @notice Address of the developer/admin who can update factory settings
  /// @dev Has permissions to change dev address and set strategy factory
  address public dev;

  /**
   * @notice Initializes the factory with the developer address
   * @param devAddress Address of the developer/admin
   */
  constructor(address devAddress, address spherexEngine) SphereXProtectedBase(devAddress, devAddress, spherexEngine) {
    _revertAddressZero(devAddress);
    dev = devAddress;
  }

  /**
   * @notice Restricts function access to only the dev address
   */
  modifier onlyDev() {
    if (msg.sender != dev) revert NotDev();
    _;
  }

  /**
   * @notice Restricts function access to only the strategy factory
   */
  modifier onlyWhitelistedStrategyFactory() {
    if (!whitelistedStrategyFactories[msg.sender]) revert NotWhitelistedStrategyFactory();
    _;
  }

  function _revertAddressZero(address addressToCheck) internal pure {
    if (addressToCheck == address(0)) revert ZeroAddress();
  }

  /**
   * @notice Updates the dev address
   * @param devAddress New developer address
   * @dev Can only be called by current dev
   */
  function setDev(address devAddress) external onlyDev sphereXGuardExternal(0x60c8216a) {
    _revertAddressZero(devAddress);
    address old = dev;
    dev = devAddress;
    emit DevChanged(old, devAddress);
  }

  /**
   * @notice Sets the strategy factory address
   * @param factoryAddress Address of the strategy factory contract
   * @dev Can only be called by dev
   */
  function setWhitelistedStrategyFactory(
    address factoryAddress,
    bool isWhitelisted
  ) external onlyDev sphereXGuardExternal(0xaebf9f75) {
    _revertAddressZero(factoryAddress);
    whitelistedStrategyFactories[factoryAddress] = isWhitelisted;
    emit WhitelistedStrategyFactoryChanged(factoryAddress, isWhitelisted);
  }

  /**
   * @notice Sets the SphereX protected settings for a given address
   * @param protected Address to be protected
   * @param sphereXAdmin Admin address for SphereX
   * @param sphereXOperator Operator address for SphereX
   * @param sphereXEngine Engine address for SphereX
   */
  function setSphereXProtected(
    address protected,
    address sphereXAdmin,
    address sphereXOperator,
    address sphereXEngine
  ) private sphereXGuardInternal(0x82107f29) {
    SphereXConfiguration(protected).changeSphereXOperator(address(this));
    SphereXConfiguration(protected).changeSphereXEngine(sphereXEngine);
    SphereXConfiguration(protected).changeSphereXOperator(sphereXOperator);
    SphereXConfiguration(protected).transferSphereXAdminRole(sphereXAdmin);
  }

  /**
   * @notice Creates a new vault and controller pair
   * @param asset The underlying asset that the vault will accept
   * @param governanceAddress Address that will have governance rights over the vault
   * @param strategistAddress Address that will manage strategies
   * @param timelockAddress Timelock contract address for the vault
   * @param devfundAddress Address that receives dev fees
   * @param treasuryAddress Address that receives treasury fees
   * @param controllerAddress Address of the controller to be used for the vault
   * @param sphereXAdmin Address of the SphereX admin
   * @param sphereXOperator Address of the SphereX operator
   * @param sphereXEngine Address of the SphereX engine
   * @return vault The newly created vault
   * @dev Can only be called by the strategy factory
   */
  function createVault(
    address asset,
    address governanceAddress,
    address strategistAddress,
    address timelockAddress,
    address devfundAddress,
    address treasuryAddress,
    address controllerAddress,
    address sphereXAdmin,
    address sphereXOperator,
    address sphereXEngine,
    uint16 initialDepositFee,
    uint16 initialWithdrawFee
  ) external onlyWhitelistedStrategyFactory sphereXGuardExternal(0x23b79b09) returns (IVault vault) {
    if (
      asset == address(0) ||
      governanceAddress == address(0) ||
      strategistAddress == address(0) ||
      timelockAddress == address(0) ||
      devfundAddress == address(0) ||
      treasuryAddress == address(0) ||
      controllerAddress == address(0) ||
      sphereXAdmin == address(0) ||
      sphereXOperator == address(0) ||
      sphereXEngine == address(0)
    ) revert ZeroAddress();
    vault = new Vault(
      asset,
      governanceAddress,
      timelockAddress,
      controllerAddress,
      initialDepositFee,
      initialWithdrawFee
    );
    setSphereXProtected(address(vault), sphereXAdmin, sphereXOperator, sphereXEngine);
    emit VaultCreated(address(vault));
  }
}
