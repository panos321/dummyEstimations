// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICrocSwapDex, ICropSwapLp} from "../interfaces/exchange/Crocswap.sol";
import {ILpRouter} from "../interfaces/ILpRouter.sol";
import {SphereXProtected} from "@spherex-xyz/contracts/src/SphereXProtected.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title LpRouter
/// @notice This contract facilitates adding and removing liquidity on various decentralized exchanges (DEXes).
/// @dev The contract currently supports the BEX DEX type and uses SafeERC20 for safe token transfers.
contract LpRouter is SphereXProtected, ReentrancyGuard, ILpRouter {
  using SafeERC20 for IERC20;

  /// @notice Mapping of DEX index to router address
  mapping(uint8 => address) public routers;

  /// @notice Default DEX type used for liquidity operations
  DexType public defaultDex;

  /// @notice Address with the highest privilege level (can change other roles)
  address public governance;

  /// @notice Initializes the LpRouter contract
  /// @param governanceAddress The address with governance privileges
  /// @param dexType The default DEX type
  /// @param dexIndices Array of DEX indices
  /// @param routerAddresses Array of router addresses corresponding to the DEX indices
  constructor(address governanceAddress, DexType dexType, uint8[] memory dexIndices, address[] memory routerAddresses) {
    if (dexIndices.length != routerAddresses.length) revert InvalidRouterLength();
    _revertAddressZero(governanceAddress);

    governance = governanceAddress;
    defaultDex = dexType;

    for (uint8 i = 0; i < dexIndices.length; i++) {
      if (routerAddresses[i] == address(0)) revert ZeroRouterAddress();
      routers[dexIndices[i]] = routerAddresses[i];
      emit SetRouter(dexIndices[i], routerAddresses[i]);
    }
  }

  // **** Modifiers **** //

  /// @notice Ensures that only the governance address can call the function
  /// @dev Reverts with NotGovernance if caller is not the governance address
  modifier onlyGovernance() {
    if (msg.sender != governance) revert NotGovernance();
    _;
  }

  // **** External Functions **** //

  /// @notice Sets a new governance address
  /// @param governanceAddress The new governance address
  function setGovernance(address governanceAddress) public onlyGovernance sphereXGuardPublic(0x1c56918f, 0xab033ea9) {
    _revertAddressZero(governanceAddress);
    emit GovernanceUpdated(governance, governanceAddress);
    governance = governanceAddress;
  }

  /// @notice Sets the default DEX to use for swaps
  /// @param dex The DEX index
  function setDefaultDex(uint8 dex) external onlyGovernance sphereXGuardExternal(0xa3c17b0c) {
    defaultDex = DexType(dex);
    emit SetDefaultDex(dex);
  }

  /// @notice Sets a router address for a DEX
  /// @param dex The DEX index
  /// @param router The router address
  function setRouter(uint8 dex, address router) external onlyGovernance sphereXGuardExternal(0xa3f6b48c) {
    _revertAddressZero(router);
    routers[dex] = router;
    emit SetRouter(dex, router);
  }

  /// @notice Adds liquidity to a pool
  /// @param params The parameters for adding liquidity
  /// @return lpAmountOut The amount of LP tokens received
  function addLiquidityWithDefaultDex(
    AddLiquidityParams calldata params
  ) external nonReentrant sphereXGuardExternal(0x39fcd530) returns (uint256 lpAmountOut) {
    return addLiquidity(params, defaultDex);
  }

  /// @notice Adds liquidity to a pool using a specified DEX type
  /// @param params The parameters for adding liquidity
  /// @param dexType The DEX type to use
  /// @return lpAmountOut The amount of LP tokens received
  function addLiquidity(
    AddLiquidityParams calldata params,
    DexType dexType
  ) public nonReentrant sphereXGuardPublic(0xed92e336, 0xee52e659) returns (uint256 lpAmountOut) {
    address router = routers[uint8(dexType)];
    if (router == address(0)) revert ZeroRouterAddress();
    if (dexType == DexType.BEX) {
      return _addLiquidityCrocSwap(params, router);
    } else {
      revert UnsupportedDexType();
    }
  }

  /// @notice Removes liquidity from a pool
  /// @param params The parameters for removing liquidity
  /// @return baseAmount The amount of base tokens received
  /// @return quoteAmount The amount of quote tokens received
  function removeLiquidityWithDefaultDex(
    RemoveLiquidityParams calldata params
  ) external nonReentrant sphereXGuardExternal(0x3cad6fce) returns (uint256 baseAmount, uint256 quoteAmount) {
    return removeLiquidity(params, defaultDex);
  }

  /// @notice Removes liquidity from a pool using a specified DEX type
  /// @param params The parameters for removing liquidity
  /// @param dexType The DEX type to use
  /// @return baseAmount The amount of base tokens received
  /// @return quoteAmount The amount of quote tokens received
  function removeLiquidity(
    RemoveLiquidityParams calldata params,
    DexType dexType
  ) public nonReentrant sphereXGuardPublic(0xd04d32ff, 0x31512b67) returns (uint256 baseAmount, uint256 quoteAmount) {
    address router = routers[uint8(dexType)];
    if (router == address(0)) revert ZeroRouterAddress();
    if (dexType == DexType.BEX) {
      return _removeLiquidityCrocSwap(params, router);
    } else {
      revert UnsupportedDexType();
    }
  }

  /** Internal Functions **/

  /// @notice Reverts if the address is zero
  /// @param _address The address to check
  function _revertAddressZero(address _address) internal pure {
    if (_address == address(0)) revert ZeroAddress();
  }

  /// @notice Encodes data for adding liquidity
  /// @param arg1 The first argument
  /// @param arg7 The seventh argument
  /// @param params The parameters for adding liquidity
  /// @return The encoded data
  function _encodeDataForAddition(
    uint8 arg1,
    uint128 arg7,
    AddLiquidityParams calldata params
  ) private pure returns (bytes memory) {
    return
      abi.encode(
        arg1, // Fixed in base tokens
        params.base, // address
        params.quote, // address
        params.poolIdx, // uint256
        int24(0), // bidTick 0
        int24(0), // askTick 0
        arg7, // uint128
        uint128(params.limitLower), // uint128
        uint128(params.limitHigher), // uint128
        uint8(0), // settleFlags 0
        params.lp // lpConduit
      );
  }

  function _encodeDataForRemoval(
    ICropSwapLp lp,
    RemoveLiquidityParams calldata params
  ) private view returns (bytes memory) {
    return
      abi.encode(
        uint8(4), // Fixed in liquidity tokens
        lp.baseToken(), // address
        lp.quoteToken(), // address
        lp.poolType(), // uint256
        int24(0), // bidTick 0
        int24(0), // askTick 0
        uint128(params.lpAmount), // uint128
        params.limitLower, // uint128
        params.limitHigher, // uint128
        uint8(0), // settleFlags 0
        address(lp) // lpConduit
      );
  }

  /// @notice Internal function to add liquidity using CrocSwap
  /// @param params The parameters for adding liquidity
  /// @param router The router address
  /// @return lpAmountOut The amount of LP tokens received
  function _addLiquidityCrocSwap(
    AddLiquidityParams calldata params,
    address router
  ) internal sphereXGuardInternal(0x6a9e79f4) returns (uint256 lpAmountOut) {
    IERC20(params.base).forceApprove(router, params.baseAmount);
    IERC20(params.quote).forceApprove(router, params.quoteAmount);

    // We don't know the exact ratio of base and quote, so we try with base first, if it fails, we try with quote
    // try with base
    try
      ICrocSwapDex(router).userCmd(
        128, // LP_PROXY_IDX
        _encodeDataForAddition(uint8(31), uint128(params.baseAmount), params)
      )
    {} catch {
      // try with quote
      ICrocSwapDex(router).userCmd(
        128, // LP_PROXY_IDX
        _encodeDataForAddition(uint8(32), uint128(params.quoteAmount), params)
      );
    }
    lpAmountOut = IERC20(params.lp).balanceOf(address(this));
    IERC20(params.lp).safeTransfer(params.recipient, lpAmountOut);

    uint256 quoteBalance = IERC20(params.quote).balanceOf(address(this));
    if (quoteBalance > 0) {
      IERC20(params.quote).safeTransfer(params.recipient, quoteBalance);
    }
    uint256 baseBalance = IERC20(params.base).balanceOf(address(this));
    if (baseBalance > 0) {
      IERC20(params.base).safeTransfer(params.recipient, baseBalance);
    }
  }

  /// @notice Internal function to remove liquidity using CrocSwap
  /// @param params The parameters for removing liquidity
  /// @param router The router address
  /// @return baseAmount The amount of base tokens received
  /// @return quoteAmount The amount of quote tokens received
  function _removeLiquidityCrocSwap(
    RemoveLiquidityParams calldata params,
    address router
  ) internal sphereXGuardInternal(0x4f207669) returns (uint256 baseAmount, uint256 quoteAmount) {
    ICropSwapLp lp = ICropSwapLp(params.lp);
    lp.approve(router, params.lpAmount);
    ICrocSwapDex(router).userCmd(
      128, // LP_PROXY_IDX
      _encodeDataForRemoval(lp, params)
    );

    // return assets
    baseAmount = IERC20(lp.baseToken()).balanceOf(address(this));
    quoteAmount = IERC20(lp.quoteToken()).balanceOf(address(this));
    IERC20(lp.baseToken()).safeTransfer(params.recipient, baseAmount);
    IERC20(lp.quoteToken()).safeTransfer(params.recipient, quoteAmount);
  }
}
