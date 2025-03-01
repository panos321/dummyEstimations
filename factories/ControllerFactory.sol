// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Controller} from "../controllers/Controller.sol";
import {IController} from "../interfaces/IController.sol";
import {IControllerFactory} from "../interfaces/IControllerFactory.sol";
import {SphereXConfiguration} from "@spherex-xyz/contracts/src/SphereXConfiguration.sol";
import {SphereXProtectedBase} from "@spherex-xyz/contracts/src/SphereXProtectedBase.sol";

/**
 * @title ControllerFactory
 * @notice Factory contract for creating Controllers
 */
contract ControllerFactory is SphereXProtectedBase, IControllerFactory {
  /// @notice Address of the strategy factory that is authorized to create controllers
  /// @dev Only this address can call createController
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

  /**
   * @notice Reverts if the address is zero
   * @param addressToCheck Address to check
   */
  function _revertAddressZero(address addressToCheck) internal pure {
    if (addressToCheck == address(0)) revert ZeroAddress();
  }

  /**
   * @notice Updates the dev address
   * @param devAddress New developer address
   * @dev Can only be called by current dev
   */
  function setDev(address devAddress) external onlyDev sphereXGuardExternal(0x759d6186) {
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
  ) external onlyDev sphereXGuardExternal(0xdbd566cf) {
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
  ) private sphereXGuardInternal(0x7a1c4185) {
    SphereXConfiguration(protected).changeSphereXOperator(address(this));
    SphereXConfiguration(protected).changeSphereXEngine(sphereXEngine);
    SphereXConfiguration(protected).changeSphereXOperator(sphereXOperator);
    SphereXConfiguration(protected).transferSphereXAdminRole(sphereXAdmin);
  }

  /**
   * @notice Creates a new controller
   * @param asset The underlying asset that the vault will accept
   * @param governanceAddress Address that will have governance rights over the vault
   * @param strategistAddress Address that will manage strategies
   * @param timelockAddress Timelock contract address for the vault
   * @param devfundAddress Address that receives dev fees
   * @param treasuryAddress Address that receives treasury fees
   * @return controller The newly created controller
   * @dev Can only be called by the strategy factory
   */
  function createController(
    address asset,
    address governanceAddress,
    address strategistAddress,
    address timelockAddress,
    address devfundAddress,
    address treasuryAddress,
    address sphereXAdmin,
    address sphereXOperator,
    address sphereXEngine
  ) external onlyWhitelistedStrategyFactory sphereXGuardExternal(0x7db7ad94) returns (IController controller) {
    if (
      asset == address(0) ||
      governanceAddress == address(0) ||
      strategistAddress == address(0) ||
      timelockAddress == address(0) ||
      devfundAddress == address(0) ||
      treasuryAddress == address(0) ||
      sphereXAdmin == address(0) ||
      sphereXOperator == address(0) ||
      sphereXEngine == address(0)
    ) revert ZeroAddress();
    // ?? should we just use one controller for all vaults? but setting up the vault needs governance and timelock
    // maybe factory becomes controller to manage all the vaults?
    controller = new Controller(
      msg.sender, // use msg.sender (strategyFactory) as governance so we can set it later
      strategistAddress,
      msg.sender,
      devfundAddress,
      treasuryAddress
    );
    setSphereXProtected(address(controller), sphereXAdmin, sphereXOperator, sphereXEngine);
    emit ControllerCreated(address(controller));
  }
}
