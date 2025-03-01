// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILpRouter} from "../interfaces/ILpRouter.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";
import {SphereXProtected} from "@spherex-xyz/contracts/src/SphereXProtected.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IKodiakVaultV1, IKodiakV1RouterStaking} from "../interfaces/kodiak/IKodiak.sol";
import {ISteerPeriphery, ISushiMultiPositionLiquidityManager} from "../interfaces/steer/ISteer.sol";
import {IUniProxy, IHypervisor} from "../interfaces/gamma/IGamma.sol";
import {IBeraPool, IBeraVault, IAsset} from "../interfaces/exchange/Beraswap.sol";
import {WeightedPoolUserData} from "../libraries/WeightedPoolUserData.sol";
import {StablePoolUserData} from "../libraries/StablePoolUserData.sol";

/// @title LpRouter
/// @notice This contract facilitates adding and removing liquidity on various decentralized exchanges (DEXes).
/// @dev The contract currently supports the BEX DEX type and uses SafeERC20 for safe token transfers.
contract LpRouter is SphereXProtected, ReentrancyGuard, ILpRouter {
  using SafeERC20 for IERC20;

  /// @notice Mapping of DEX index to router address
  mapping(uint8 => address) public routers;

  /// @notice Swap router for the DEX
  ISwapRouter public swapRouter;

  /// @notice Address with the highest privilege level (can change other roles)
  address public governance;

  /// @notice Initializes the LpRouter contract
  /// @param governanceAddress The address with governance privileges
  /// @param dexIndices Array of DEX indices
  /// @param routerAddresses Array of router addresses corresponding to the DEX indices
  constructor(
    address governanceAddress,
    ISwapRouter swapRouterAddress,
    uint8[] memory dexIndices,
    address[] memory routerAddresses
  ) {
    if (dexIndices.length != routerAddresses.length) revert InvalidRouterLength();
    _revertAddressZero(governanceAddress);
    _revertAddressZero(address(swapRouterAddress));

    governance = governanceAddress;
    swapRouter = swapRouterAddress;

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

  /// @notice Sets a swap router address
  /// @param swapRouterAddress The swap router address
  function setSwapRouter(ISwapRouter swapRouterAddress) external onlyGovernance sphereXGuardExternal(0x11111111) {
    _revertAddressZero(address(swapRouterAddress));
    emit SetSwapRouter(address(swapRouter), address(swapRouterAddress));
    swapRouter = swapRouterAddress;
  }

  /// @notice Sets a router address for a DEX
  /// @param dex The DEX index
  /// @param router The router address
  function setRouter(uint8 dex, address router) external onlyGovernance sphereXGuardExternal(0xa3f6b48c) {
    _revertAddressZero(router);
    routers[dex] = router;
    emit SetRouter(dex, router);
  }

  function addLiquidity(
    address lp,
    address tokenIn,
    uint256 amountIn,
    address recipient,
    DexType dexType
  ) public nonReentrant sphereXGuardPublic(0xed92e336, 0xee52e659) returns (uint256 lpAmountOut) {
    address router = routers[uint8(dexType)];

    // if (router == address(0)) revert ZeroRouterAddress();
    // IERC20(tokenIn).safeTransferFrom(address(msg.sender), address(this), amountIn);

    if (dexType == DexType.BEX) {
      return _addLiquidityBex(IBeraPool(lp), tokenIn, amountIn, recipient);
    } else if (dexType == DexType.GAMMA) {
      return _addLiquidityGamma(IHypervisor(lp), tokenIn, amountIn, recipient, router);
    } else if (dexType == DexType.STEER) {
      return _addLiquiditySteer(ISushiMultiPositionLiquidityManager(lp), tokenIn, amountIn, recipient, router);
    } else if (dexType == DexType.KODIAK_V3) {
      return _addLiquidityKodiak(IKodiakVaultV1(lp), tokenIn, amountIn, recipient, router);
    } else {
      revert UnsupportedDexType();
    }
  }

  function removeLiquidity(
    address lp,
    uint256 lpAmount,
    address recipient,
    address tokenOut,
    DexType dexType
  ) public override nonReentrant sphereXGuardPublic(0xd04d32ff, 0x31512b67) returns (uint256 tokenOutAmount) {
    address router = routers[uint8(dexType)];

    // IERC20(lp).safeTransferFrom(address(msg.sender), address(this), lpAmount);
    // if (router == address(0)) revert ZeroRouterAddress();

    if (dexType == DexType.BEX) {
      return _removeLiquidityBex(IBeraPool(lp), lpAmount, recipient, tokenOut);
    } else if (dexType == DexType.STEER) {
      return _removeLiquiditySteer(ISushiMultiPositionLiquidityManager(lp), lpAmount, recipient, tokenOut);
    } else if (dexType == DexType.KODIAK_V3) {
      return _removeLiquidityKodiak(IKodiakVaultV1(lp), lpAmount, recipient, router, tokenOut);
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

  function _returnAssets(address[] memory tokens) internal {
    uint256 balance;
    for (uint256 i = 0; i < tokens.length; i++) {
      if (tokens[i] == address(0)) continue;
      balance = IERC20(tokens[i]).balanceOf(address(this));
      if (balance > 0) {
        IERC20(tokens[i]).safeTransfer(msg.sender, balance);
      }
    }
  }

  /**
   * @notice Approves spending of a token if not already approved
   * @param tokenAddress Token to approve
   * @param spenderAddress Address to approve spending for
   */
  function _approveTokenIfNeeded(
    address tokenAddress,
    address spenderAddress
  ) internal sphereXGuardInternal(0x367a5b5d) {
    if (IERC20(tokenAddress).allowance(address(this), spenderAddress) == 0) {
      IERC20(tokenAddress).approve(spenderAddress, type(uint256).max);
    }
  }

  /**
   * @notice Divides an amount between two tokens based on their ratio
   * @dev Used to split a single token amount into two token amounts while maintaining their ratio
   * @param amount The total amount to divide
   * @param ratio0 The ratio for the first token
   * @param ratio1 The ratio for the second token
   * @return amount0 The amount allocated to the first token
   * @return amount1 The amount allocated to the second token
   */
  function _divideAmountInRatio(
    uint256 amount,
    uint256 ratio0,
    uint256 ratio1
  ) internal pure returns (uint256, uint256) {
    uint256 totalRatio = ratio0 + ratio1;
    if (totalRatio == 0) revert TotalRatioZero();
    uint256 amount0 = (amount * ratio0) / totalRatio;
    uint256 amount1 = amount - amount0;
    return (amount0, amount1);
  }

  /**
   * @notice Convert token0 and token1 into single base unit (tokenIn), divide the amountIn in same ratio as amount0Liquidity and amount1Liquidity
   * @param tokenIn The token being deposited
   * @param token0 The address of the token0
   * @param token1 The address of the token1
   * @param amountIn The amount of tokenIn being converted
   * @param amount0Liquidity The amount of token0 in the liquidity pool
   * @param amount1Liquidity The amount of token1 in the liquidity pool
   * @return amount0 The amount of token0 to be deposited
   * @return amount1 The amount of token1 to be deposited
   */
  function _getAmountsForLiquidityInRatio(
    address tokenIn,
    address token0,
    address token1,
    uint256 amountIn,
    uint256 amount0Liquidity,
    uint256 amount1Liquidity,
    DexType dexType
  ) internal returns (uint256, uint256) {
    if (token0 != tokenIn) {
      uint256 oneUnit = 10 ** IERC20Metadata(token0).decimals();
      uint256 price0 = swapRouter.getQuote(token0, tokenIn, oneUnit, dexType);
      amount0Liquidity = (amount0Liquidity * price0) / oneUnit;
    }
    if (token1 != tokenIn) {
      uint256 oneUnit = 10 ** IERC20Metadata(token1).decimals();
      uint256 price1 = swapRouter.getQuote(token1, tokenIn, oneUnit, dexType);
      amount1Liquidity = (amount1Liquidity * price1) / oneUnit;
    }

    return _divideAmountInRatio(amountIn, amount0Liquidity, amount1Liquidity);
  }

  // handle remaining tokens and swap them to tokenIn and return accumlated tokenIn amount
  function _handleRemainingTokens(
    address tokenIn,
    address token0,
    address token1,
    address recipient
  ) internal returns (uint256 tokenAmount) {
    // get token0 and token1 amount
    uint256 token0Amount = IERC20(token0).balanceOf(address(this));
    uint256 token1Amount = IERC20(token1).balanceOf(address(this));

    // If token0 matches tokenIn, add it directly to tokenAmount
    if (address(tokenIn) == address(token0)) {
      tokenAmount += token0Amount;
    }
    // Otherwise swap if there's a balance
    else if (token0Amount > 0) {
      IERC20(token0).safeTransfer(address(swapRouter), token0Amount);
      tokenAmount += swapRouter.swapWithDefaultDex(token0, tokenIn, token0Amount, 0, address(this));
    }

    // If token1 matches tokenIn, add it directly to tokenAmount
    if (address(tokenIn) == address(token1)) {
      tokenAmount += token1Amount;
    }
    // Otherwise swap if there's a balance
    else if (token1Amount > 0) {
      IERC20(token1).safeTransfer(address(swapRouter), token1Amount);
      tokenAmount += swapRouter.swapWithDefaultDex(token1, tokenIn, token1Amount, 0, address(this));
    }

    IERC20(tokenIn).safeTransfer(recipient, tokenAmount);
  }

  function _handleTokenSwaps(
    address tokenIn,
    IERC20[] memory tokens,
    uint256 amount0,
    uint256 amount1
  ) internal returns (uint256 swappedAmount0, uint256 swappedAmount1) {
    // Get first and last token addresses, ignoring middle tokens if any
    address firstToken = address(tokens[0]);
    address lastToken = address(tokens[tokens.length - 1]);

    if (amount0 > 0 && amount1 > 0) {
      // Handle first token
      if (address(tokenIn) != firstToken) {
        IERC20(tokenIn).safeTransfer(address(swapRouter), amount0);
        swappedAmount0 = swapRouter.swapWithDefaultDex(tokenIn, firstToken, amount0, 0, address(this));
      } else {
        swappedAmount0 = amount0;
      }

      // Handle last token
      if (address(tokenIn) != lastToken) {
        IERC20(tokenIn).safeTransfer(address(swapRouter), amount1);
        swappedAmount1 = swapRouter.swapWithDefaultDex(tokenIn, lastToken, amount1, 0, address(this));
      } else {
        swappedAmount1 = amount1;
      }
    } else {
      //get balance of tokenIn
      uint256 tokenInBalance = IERC20(tokenIn).balanceOf(address(this));

      // Handle last token
      if (address(tokenIn) != lastToken) {
        IERC20(tokenIn).safeTransfer(address(swapRouter), tokenInBalance);
        swappedAmount1 = swapRouter.swapWithDefaultDex(tokenIn, lastToken, tokenInBalance, 0, address(this));
      } else {
        swappedAmount1 = tokenInBalance;
      }
    }
  }

  function _prepareJoinPoolRequest(
    address lpAddress,
    IERC20[] memory tokens,
    uint256 amount0,
    uint256 amount1
  ) internal pure returns (IBeraVault.JoinPoolRequest memory request) {
    request.assets = new IAsset[](tokens.length >= 2 ? tokens.length : 2);
    request.maxAmountsIn = new uint256[](tokens.length >= 2 ? tokens.length : 2);

    // Always set first token
    request.assets[0] = IAsset(address(tokens[0]));
    request.maxAmountsIn[0] = amount0;

    if (tokens.length == 2) {
      // For 2 tokens, use standard setup
      request.assets[1] = IAsset(address(tokens[1]));
      request.maxAmountsIn[1] = amount1;

      request.userData = abi.encode(StablePoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, request.maxAmountsIn, 0);
      request.fromInternalBalance = false;
    } else if (tokens.length > 2) {
      // For more than 2 tokens, add middle tokens with 0 amounts
      for (uint256 i = 1; i < tokens.length - 1; i++) {
        request.assets[i] = IAsset(address(tokens[i]));
        request.maxAmountsIn[i] = 0;
      }

      // Add last token
      request.assets[tokens.length - 1] = IAsset(address(tokens[tokens.length - 1]));
      request.maxAmountsIn[tokens.length - 1] = amount1;

      // Count valid assets (excluding lpAddress)
      uint256 validAssetCount = 0;
      for (uint256 i = 0; i < tokens.length; i++) {
        if (address(tokens[i]) != lpAddress) {
          validAssetCount++;
        }
      }

      // Create array with size of valid assets
      uint256[] memory newMaxAmountsIn = new uint256[](validAssetCount);

      // Fill newMaxAmountsIn array, skipping lpAddress
      uint256 newArrayIndex = 0;
      for (uint256 i = 0; i < tokens.length; i++) {
        if (address(tokens[i]) != lpAddress) {
          newMaxAmountsIn[newArrayIndex] = request.maxAmountsIn[i];
          newArrayIndex++;
        }
      }

      request.userData = abi.encode(StablePoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, newMaxAmountsIn, 0);
      request.fromInternalBalance = false;
    }
  }

  function _addLiquidityBex(
    IBeraPool lp,
    address tokenIn,
    uint256 amountIn,
    address recipient
  ) internal sphereXGuardInternal(0x6a9e79f4) returns (uint256 lpAmountOut) {
    // Get pool info
    bytes32 poolId = lp.getPoolId();
    address beraVault = lp.getVault();
    (IERC20[] memory tokens, , ) = IBeraVault(beraVault).getPoolTokens(poolId);

    uint256 amount0;
    uint256 amount1;

    if (tokens.length == 2) {
      // Split amounts and swap if needed
      amount0 = amountIn / 2;
      amount1 = amountIn - amount0;
    }

    // Handle token swaps
    (amount0, amount1) = _handleTokenSwaps(tokenIn, tokens, amount0, amount1);

    // Approve tokens
    IERC20(address(tokens[0])).forceApprove(beraVault, amount0);
    IERC20(address(tokens[tokens.length - 1])).forceApprove(beraVault, amount1);

    // Prepare and execute join pool request
    IBeraVault.JoinPoolRequest memory request = _prepareJoinPoolRequest(address(lp), tokens, amount0, amount1);
    IBeraVault(beraVault).joinPool(poolId, address(this), address(this), request);

    lpAmountOut = lp.balanceOf(address(this));
    IERC20(address(lp)).safeTransfer(recipient, lpAmountOut);

    // Return any remaining tokens
    _handleRemainingTokens(address(tokenIn), address(tokens[0]), address(tokens[tokens.length - 1]), recipient);
  }

  function _addLiquidityKodiak(
    IKodiakVaultV1 lp,
    address tokenIn,
    uint256 amountIn,
    address recipient,
    address router
  ) internal returns (uint256 tokenOutAmount) {
    LiquidityAddInfo memory liquidityInfo;
    // get both tokens and their liquidity amounts
    (liquidityInfo.amount0, liquidityInfo.amount1) = lp.getUnderlyingBalances();
    (liquidityInfo.token0, liquidityInfo.token1) = (lp.token0(), lp.token1());

    // divide the tokenIn in optimal amounts for liquidity based on the current vault's ratio
    (liquidityInfo.amount0, liquidityInfo.amount1) = _getAmountsForLiquidityInRatio(
      tokenIn,
      liquidityInfo.token0,
      liquidityInfo.token1,
      amountIn,
      liquidityInfo.amount0,
      liquidityInfo.amount1,
      DexType.KODIAK_V3
    );

    // Swap tokenIn to token0 if needed
    if (liquidityInfo.token0 != address(tokenIn)) {
      IERC20(tokenIn).safeTransfer(address(swapRouter), liquidityInfo.amount0);
      liquidityInfo.amount0 = swapRouter.swapWithDefaultDex(
        address(tokenIn),
        liquidityInfo.token0,
        liquidityInfo.amount0,
        0,
        address(this)
      );
    }

    // Swap tokenIn to token1 if needed
    if (liquidityInfo.token1 != address(tokenIn)) {
      IERC20(tokenIn).safeTransfer(address(swapRouter), liquidityInfo.amount1);
      liquidityInfo.amount1 = swapRouter.swapWithDefaultDex(
        address(tokenIn),
        liquidityInfo.token1,
        liquidityInfo.amount1,
        0,
        address(this)
      );
    }

    (uint256 token0AmountMin, uint256 token1AmountMin, uint256 mintAmountMin) = lp.getMintAmounts(
      liquidityInfo.amount0,
      liquidityInfo.amount1
    );

    IERC20(liquidityInfo.token0).forceApprove(router, liquidityInfo.amount0);
    IERC20(liquidityInfo.token1).forceApprove(router, liquidityInfo.amount1);

    uint256 balanceBefore = lp.balanceOf(address(this));
    (, , tokenOutAmount) = IKodiakV1RouterStaking(router).addLiquidity(
      lp,
      liquidityInfo.amount0,
      liquidityInfo.amount1,
      token0AmountMin,
      token1AmountMin,
      mintAmountMin,
      address(this)
    );
    tokenOutAmount = lp.balanceOf(address(this)) - balanceBefore;
    IERC20(address(lp)).safeTransfer(recipient, tokenOutAmount);

    address[] memory tokens = new address[](2);
    tokens[0] = liquidityInfo.token0;
    tokens[1] = liquidityInfo.token1;
    _returnAssets(tokens);
  }

  function _addLiquiditySteer(
    ISushiMultiPositionLiquidityManager lp,
    address tokenIn,
    uint256 amountIn,
    address recipient,
    address router
  ) internal returns (uint256 tokenOutAmount) {
    LiquidityAddInfo memory liquidityInfo;
    // get both tokens and their liquidity amounts
    (liquidityInfo.amount0, liquidityInfo.amount1) = lp.getTotalAmounts();
    (liquidityInfo.token0, liquidityInfo.token1) = (lp.token0(), lp.token1());

    // divide the tokenIn in optimal amounts for liquidity based on the current vault's ratio
    (liquidityInfo.amount0, liquidityInfo.amount1) = _getAmountsForLiquidityInRatio(
      tokenIn,
      liquidityInfo.token0,
      liquidityInfo.token1,
      amountIn,
      liquidityInfo.amount0,
      liquidityInfo.amount1,
      DexType.KODIAK_V3
    );

    // Swap tokenIn to token0 if needed
    if (liquidityInfo.token0 != address(tokenIn)) {
      IERC20(tokenIn).safeTransfer(address(swapRouter), liquidityInfo.amount0);
      liquidityInfo.amount0 = swapRouter.swapWithDefaultDex(
        address(tokenIn),
        liquidityInfo.token0,
        liquidityInfo.amount0,
        0,
        address(this)
      );
    }

    // Swap tokenIn to token1 if needed
    if (liquidityInfo.token1 != address(tokenIn)) {
      IERC20(tokenIn).safeTransfer(address(swapRouter), liquidityInfo.amount1);
      liquidityInfo.amount1 = swapRouter.swapWithDefaultDex(
        address(tokenIn),
        liquidityInfo.token1,
        liquidityInfo.amount1,
        0,
        address(this)
      );
    }

    IERC20(liquidityInfo.token0).forceApprove(router, liquidityInfo.amount0);
    IERC20(liquidityInfo.token1).forceApprove(router, liquidityInfo.amount1);

    uint256 balanceBefore = IERC20(lp).balanceOf(address(this));
    ISteerPeriphery(router).deposit(address(lp), liquidityInfo.amount0, liquidityInfo.amount1, 0, 0, address(this));
    tokenOutAmount = IERC20(lp).balanceOf(address(this)) - balanceBefore;
    IERC20(lp).safeTransfer(recipient, tokenOutAmount);

    address[] memory tokens = new address[](2);
    tokens[0] = liquidityInfo.token0;
    tokens[1] = liquidityInfo.token1;
    _returnAssets(tokens);
  }

  function _addLiquidityGamma(
    IHypervisor lp,
    address tokenIn,
    uint256 amountIn,
    address recipient,
    address router
  ) internal returns (uint256 tokenOutAmount) {
    LiquidityAddInfo memory liquidityInfo;
    // get both tokens and their liquidity amounts
    // TODO: tokenIn is not the token0 or token1 , so we cannot actually just divide the amountIn in half
    (liquidityInfo.token0, liquidityInfo.token1) = (lp.token0(), lp.token1());
    liquidityInfo.amount0 = amountIn / 2;
    (, liquidityInfo.amount1) = IUniProxy(router).getDepositAmount(
      address(lp),
      liquidityInfo.token0,
      liquidityInfo.amount0
    );

    // divide the tokenIn in optimal amounts for liquidity based on the current vault's ratio
    (liquidityInfo.amount0, liquidityInfo.amount1) = _getAmountsForLiquidityInRatio(
      tokenIn,
      liquidityInfo.token0,
      liquidityInfo.token1,
      amountIn,
      liquidityInfo.amount0,
      liquidityInfo.amount1,
      DexType.UNISWAP_V3
    );

    // Swap tokenIn to token0 if needed
    if (liquidityInfo.token0 != address(tokenIn)) {
      IERC20(tokenIn).safeTransfer(address(swapRouter), liquidityInfo.amount0);
      liquidityInfo.amount0 = swapRouter.swapWithDefaultDex(
        address(tokenIn),
        liquidityInfo.token0,
        liquidityInfo.amount0,
        0,
        address(this)
      );
    }

    // Swap tokenIn to token1 if needed
    if (liquidityInfo.token1 != address(tokenIn)) {
      IERC20(tokenIn).safeTransfer(address(swapRouter), liquidityInfo.amount1);
      liquidityInfo.amount1 = swapRouter.swapWithDefaultDex(
        address(tokenIn),
        liquidityInfo.token1,
        liquidityInfo.amount1,
        0,
        address(this)
      );
    }

    IERC20(liquidityInfo.token0).forceApprove(router, liquidityInfo.amount0);
    IERC20(liquidityInfo.token1).forceApprove(router, liquidityInfo.amount1);

    uint256 balanceBefore = IERC20(lp).balanceOf(address(this));
    ISteerPeriphery(router).deposit(address(lp), liquidityInfo.amount0, liquidityInfo.amount1, 0, 0, address(this));
    tokenOutAmount = IERC20(lp).balanceOf(address(this)) - balanceBefore;
    IERC20(lp).safeTransfer(recipient, tokenOutAmount);

    address[] memory tokens = new address[](2);
    tokens[0] = liquidityInfo.token0;
    tokens[1] = liquidityInfo.token1;
    _returnAssets(tokens);
  }

  function _removeLiquiditySteer(
    ISushiMultiPositionLiquidityManager lp,
    uint256 lpAmount,
    address recipient,
    address tokenOut
  ) internal returns (uint256 tokenOutAmount) {
    LiquidityRemoveInfo memory liquidityInfo;
    liquidityInfo.lp = address(lp);
    liquidityInfo.lpAmount = lpAmount;
    (liquidityInfo.token0, liquidityInfo.token1) = (lp.token0(), lp.token1());
    // withdraw lp from steer vault
    lp.withdraw(lpAmount, 0, 0, address(this));
    tokenOutAmount = _handleRemainingTokens(tokenOut, liquidityInfo.token0, liquidityInfo.token1, recipient);
  }

  function _removeLiquidityKodiak(
    IKodiakVaultV1 lp,
    uint256 lpAmount,
    address recipient,
    address router,
    address tokenOut
  ) internal returns (uint256 tokenOutAmount) {
    LiquidityRemoveInfo memory liquidityInfo;
    liquidityInfo.lp = address(lp);
    liquidityInfo.lpAmount = lpAmount;
    (liquidityInfo.token0, liquidityInfo.token1) = (lp.token0(), lp.token1());

    _approveTokenIfNeeded(address(lp), address(router));
    IKodiakV1RouterStaking(router).removeLiquidity(lp, lpAmount, 0, 0, address(this));
    tokenOutAmount = _handleRemainingTokens(tokenOut, liquidityInfo.token0, liquidityInfo.token1, recipient);
  }

  function _prepareExitPoolRequest(
    IERC20[] memory tokens,
    uint256 lpAmount
  ) internal pure returns (IBeraVault.ExitPoolRequest memory request) {
    request.assets = new IAsset[](tokens.length >= 2 ? tokens.length : 2);
    request.minAmountsOut = new uint256[](tokens.length >= 2 ? tokens.length : 2);

    // Set all assets and initialize minAmountsOut with 0
    for (uint256 i = 0; i < tokens.length; i++) {
      request.assets[i] = IAsset(address(tokens[i]));
      request.minAmountsOut[i] = 0;
    }

    request.userData = tokens.length == 2
      ? abi.encode(WeightedPoolUserData.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT, lpAmount)
      : abi.encode(
        StablePoolUserData.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
        lpAmount,
        tokens.length - 2 // Dynamic index based on array length
      );

    request.toInternalBalance = false;
  }

  function _removeLiquidityBex(
    IBeraPool lp,
    uint256 lpAmount,
    address recipient,
    address tokenOut
  ) internal sphereXGuardInternal(0x4f207669) returns (uint256 tokenOutAmount) {
    bytes32 poolId = lp.getPoolId();
    address beraVault = lp.getVault();

    (IERC20[] memory tokens, , ) = IBeraVault(beraVault).getPoolTokens(poolId);

    IERC20(address(lp)).forceApprove(beraVault, lpAmount);

    // Prepare and execute exit pool request
    IBeraVault.ExitPoolRequest memory request = _prepareExitPoolRequest(tokens, lpAmount);
    IBeraVault(beraVault).exitPool(poolId, address(this), payable(address(this)), request);

    // Return any remaining tokens, using first and last token
    tokenOutAmount = _handleRemainingTokens(
      tokenOut,
      address(tokens[0]),
      address(tokens[tokens.length - 1]),
      recipient
    );
  }
}
