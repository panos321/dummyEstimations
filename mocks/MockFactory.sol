// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {StrategyFactoryBase} from "../factories/StrategyFactoryBase.sol";
import {MockStrategy} from "./MockStrategy.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IController} from "../interfaces/IController.sol";

contract MockFactory is StrategyFactoryBase {
  constructor(
    address devAddress,
    address controllerFactoryAddress,
    address vaultFactoryAddress,
    address spherexEngine
  ) StrategyFactoryBase(devAddress, controllerFactoryAddress, vaultFactoryAddress, spherexEngine) {}

  struct MockFactoryParams {
    address asset;
    address governance;
    address strategist;
    address timelock;
    address devfund;
    address treasury;
    address harvester;
    address wrappedNative;
    address bgtAddress;
    address swapRouter;
    address lpRouter;
    address zapper;
    address staking;
    uint16 initialDepositFee;
    uint16 initialWithdrawFee;
  }

  function createVaultWithParams(
    MockFactoryParams calldata params
  )
    external
    virtual
    onlyDev
    onlyNewAsset(params.asset)
    returns (IVault vault, IController controller, IStrategy strategy)
  {
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
    strategy = new MockStrategy(
      params.asset,
      params.governance,
      params.harvester,
      address(controller),
      params.timelock,
      params.wrappedNative,
      params.bgtAddress,
      params.swapRouter,
      params.lpRouter,
      params.zapper,
      params.staking
    );

    // 3. setup vault
    _setupVault(params.asset, vault, strategy, controller, params.governance, params.timelock);
    emit VaultCreated(params.asset, address(vault), address(strategy), address(controller));
  }
}
