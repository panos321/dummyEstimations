// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {StrategyFactoryBase} from "./StrategyFactoryBase.sol";
import {BeradromeStrategy} from "../strategies/BeradromeStrategy.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IController} from "../interfaces/IController.sol";
import {SphereXConfiguration} from "@spherex-xyz/contracts/src/SphereXConfiguration.sol";

/**
 * @title BeradromeFactory
 * @notice Factory contract for deploying Beradrome strategy vaults
 * @dev Inherits from StrategyFactoryBase and handles the creation of Beradrome-specific vaults,
 * controllers and strategies
 */
contract BeradromeFactory is StrategyFactoryBase {
  /// @notice Vault params for creating a vault
  struct BeradromeVaultParams {
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
    address gauge;
    address staking;
    uint16 initialDepositFee;
    uint16 initialWithdrawFee;
  }

  /**
   * @notice Constructs the SteerFactory contract
   * @param devAddress Address of the developer/admin
   * @param controllerFactoryAddress Address of the VaultAndControllerFactory contract
   * @param vaultFactoryAddress Address of the VaultFactory contract
   * @param spherexEngineAddress Address of the SphereXEngine contract
   */
  constructor(
    address devAddress,
    address controllerFactoryAddress,
    address vaultFactoryAddress,
    address spherexEngineAddress
  ) StrategyFactoryBase(devAddress, controllerFactoryAddress, vaultFactoryAddress, spherexEngineAddress) {}

  /**
   * @notice Creates a new vault with a Infrared strategy
   * @param params The parameters for creating a vault
   * @return vault The newly created vault
   * @return controller The newly created controller
   * @return strategy The newly created Infrared strategy
   * @dev Only callable by dev address and only for tokens that don't already have a vault
   */
  function createVaultWithParams(
    BeradromeVaultParams calldata params
  )
    external
    virtual
    onlyDev
    onlyNewAsset(params.asset)
    returns (IVault vault, IController controller, IStrategy strategy)
  {
    if (
      params.asset == address(0) ||
      params.governance == address(0) ||
      params.strategist == address(0) ||
      params.timelock == address(0) ||
      params.devfund == address(0) ||
      params.treasury == address(0) ||
      params.gauge == address(0) ||
      params.staking == address(0) ||
      params.swapRouter == address(0) ||
      params.lpRouter == address(0) ||
      params.wrappedNative == address(0) ||
      params.bgt == address(0) ||
      params.zapper == address(0)
    ) revert ZeroAddress();

    // 1. create controller and vault
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

    // 2. create strategy
    strategy = new BeradromeStrategy(
      params.asset,
      params.governance,
      params.strategist,
      address(controller),
      params.timelock,
      params.wrappedNative,
      params.bgt,
      params.swapRouter,
      params.lpRouter,
      params.zapper,
      params.gauge,
      params.staking
    );
    _setAddressAsSpherexProtected(address(strategy));
    // 3. setup vault
    _setupVault(params.asset, vault, strategy, controller, params.governance, params.timelock);

    emit VaultCreated(params.asset, address(vault), address(strategy), address(controller));
  }
}
