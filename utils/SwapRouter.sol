// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IWETH} from "../interfaces/exchange/IWETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {UniswapRouterV2} from "../interfaces/exchange/UniswapV2.sol";
import {ICamelotRouterV3} from "../interfaces/exchange/UniswapV3.sol";
import {IUniswapV3Router} from "../interfaces/exchange/UniswapV3.sol";
import {IUniswapV3Factory} from "../interfaces/exchange/UniswapV3.sol";
import {IUniswapV3Pool, IUniswapV3PoolWithUint32FeeProtocol} from "../interfaces/exchange/UniswapV3.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";
import {ICrocMultiSwap, ICrocQuery} from "../interfaces/exchange/Crocswap.sol";
import {OracleLibrary} from "../libraries/UniswapV3Oracle.sol";
import {SphereXProtected} from "@spherex-xyz/contracts/src/SphereXProtected.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title SwapRouter
/// @notice Handles token swaps across different decentralized exchanges (DEXes)
/// @dev Currently supports Uniswap V2/V3, Sushiswap V2/V3, Camelot V3, and BEX
contract SwapRouter is SphereXProtected, ReentrancyGuard, ISwapRouter {
  using SafeERC20 for IERC20;
  using Address for address;

  /// @notice Maximum path length for swapRoutes
  uint8 public constant MAX_PATH_LENGTH = 20;

  /// @notice Address of the wrapped native token (e.g. WBERA/WETH)
  address public immutable wrappedNative;

  /// @notice Mapping of DEX index to Swap router address
  mapping(uint8 => address) public routers;

  /// @notice Mapping of DEX index to Swap factory address
  mapping(uint8 => address) public factories;

  /// @notice CrocQuery contract to query croc pools
  mapping(uint8 => address) public crocQueries;

  /// @notice Mapping of tokenIn to tokenOut to swap routes
  mapping(address tokenIn => mapping(address tokenOut => SwapRoutePath[])) public swapRoutes;

  /// @notice The path length of the current swap
  uint8 internal currentPathLength;

  /// @notice Default DEX to use for swaps
  DexType public defaultDex;

  /// @notice Address with highest privilege level (can change other roles)
  address public governance;

  constructor(
    address governanceAddress,
    address wrappedNativeAddress,
    DexType defaultDexType,
    uint8[] memory dexIndex,
    address[] memory routerAddresses,
    address[] memory factoryAddresses,
    address[] memory crocQueryAddresses
  ) {
    _revertAddressZero(governanceAddress);
    _revertAddressZero(wrappedNativeAddress);
    governance = governanceAddress;
    wrappedNative = wrappedNativeAddress;
    defaultDex = defaultDexType;

    if (dexIndex.length != routerAddresses.length) revert InvalidRouterLength();
    if (dexIndex.length != factoryAddresses.length) revert InvalidFactoryLength();
    if (dexIndex.length != crocQueryAddresses.length) revert InvalidCrocQueryLength();

    for (uint8 i = 0; i < dexIndex.length; i++) {
      if (routerAddresses[i] == address(0)) revert ZeroRouterAddress();
      routers[dexIndex[i]] = routerAddresses[i];
      emit SetRouter(dexIndex[i], routerAddresses[i]);
    }
    for (uint8 i = 0; i < dexIndex.length; i++) {
      if (factoryAddresses[i] == address(0)) continue; // ignore if no factory is set
      factories[dexIndex[i]] = factoryAddresses[i];
      emit SetFactory(dexIndex[i], factoryAddresses[i]);
    }
    for (uint8 i = 0; i < dexIndex.length; i++) {
      if (crocQueryAddresses[i] == address(0)) continue; // ignore if no crocQuery is set
      crocQueries[dexIndex[i]] = crocQueryAddresses[i];
      emit SetCrocQuery(dexIndex[i], crocQueryAddresses[i]);
    }
  }

  // **** Modifiers **** //

  /// @notice Ensures that only the governance address can call the function
  /// @dev Reverts with NotGovernance if caller is not the governance address
  modifier onlyGovernance() {
    if (msg.sender != governance) revert NotGovernance();
    _;
  }

  modifier resetPathLength() {
    _;
    currentPathLength = 0;
  }

  function validateSwapParams(address tokenIn, address tokenOut, uint256 amountIn, address recipient) internal pure {
    _revertAddressZero(tokenIn);
    _revertAddressZero(tokenOut);
    _revertAddressZero(recipient);
    _revertZeroAmount(amountIn);
  }

  function validateSwapWithPathParams(address[] memory path, uint256 amountIn, address recipient) internal pure {
    _revertAddressZero(recipient);
    _revertZeroAmount(amountIn);
    _revertInvalidPathLength(path.length);
  }

  // **** External Functions **** //

  /// @notice Sets a new governance address
  /// @param governanceAddress The new governance address
  function setGovernance(address governanceAddress) public onlyGovernance sphereXGuardPublic(0xdf1b95a8, 0xab033ea9) {
    _revertAddressZero(governanceAddress);
    emit GovernanceUpdated(governance, governanceAddress);
    governance = governanceAddress;
  }

  /// @notice Sets the default DEX to use for swaps
  /// @param dex The DEX index
  function setDefaultDex(uint8 dex) external onlyGovernance sphereXGuardExternal(0x76f61bc5) {
    defaultDex = DexType(dex);
    emit SetDefaultDex(dex);
  }

  /// @notice Sets a V2 router address for a DEX
  /// @param dex The DEX index
  /// @param router The router address
  function setRouter(uint8 dex, address router) external onlyGovernance sphereXGuardExternal(0x74b0d871) {
    _revertAddressZero(router);
    routers[dex] = router;
    emit SetRouter(dex, router);
  }

  /// @notice Sets a factory address for a DEX
  /// @param dex The DEX index
  /// @param factory The factory address
  function setFactory(uint8 dex, address factory) external onlyGovernance sphereXGuardExternal(0x93b83854) {
    _revertAddressZero(factory);
    factories[dex] = factory;
    emit SetFactory(dex, factory);
  }

  /// @notice Sets the crocQuery contract
  /// @param dex The DEX index
  /// @param crocQuery The crocQuery address
  function setCrocQuery(uint8 dex, address crocQuery) external onlyGovernance sphereXGuardExternal(0xb1e6fca3) {
    _revertAddressZero(crocQuery);
    crocQueries[dex] = crocQuery;
    emit SetCrocQuery(dex, crocQuery);
  }

  /// @notice Sets a swap route for a token pair
  /// @param tokenIn Address of input token
  /// @param tokenOut Address of output token
  /// @param path Array of SwapRoutePath structs
  /// @param reversePath Whether to set the reverse swap route
  function setSwapRoute(
    address tokenIn,
    address tokenOut,
    SwapRoutePath[] memory path,
    bool reversePath
  ) external onlyGovernance sphereXGuardExternal(0x1a19f525) {
    SwapRoutePath[] storage swapRouteForward = swapRoutes[tokenIn][tokenOut];
    if (swapRouteForward.length > 0) delete swapRoutes[tokenIn][tokenOut];
    for (uint256 i = 0; i < path.length; i++) {
      swapRouteForward.push(path[i]);
    }

    if (reversePath) {
      SwapRoutePath[] storage swapRouteReverse = swapRoutes[tokenOut][tokenIn];
      if (swapRouteReverse.length > 0) delete swapRoutes[tokenOut][tokenIn];
      for (uint256 i = 0; i < path.length; i++) {
        SwapRoutePath memory inversePath = path[path.length - i - 1];
        swapRouteReverse.push(
          SwapRoutePath({
            tokenIn: inversePath.tokenOut,
            tokenOut: inversePath.tokenIn,
            dex: inversePath.dex,
            isMultiPath: inversePath.isMultiPath
          })
        );
      }
    }
    emit SetSwapRoute(tokenIn, tokenOut, path, reversePath);
  }

  /// @notice Swaps tokens using Uniswap V3 by default
  /// @param tokenIn Address of input token
  /// @param tokenOut Address of output token
  /// @param amountIn Amount of input tokens
  /// @param amountOutMinimum Minimum amount of output tokens
  /// @param recipient Address to receive output tokens
  /// @return amountOut Amount of output tokens received
  function swapWithDefaultDex(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMinimum,
    address recipient
  ) external resetPathLength sphereXGuardExternal(0x6085bf05) returns (uint256 amountOut) {
    validateSwapParams(tokenIn, tokenOut, amountIn, recipient);
    return _swapWithRoute(tokenIn, tokenOut, amountIn, amountOutMinimum, recipient);
  }

  /// @notice Swaps tokens using specified DEX
  /// @param tokenIn Address of input token
  /// @param tokenOut Address of output token
  /// @param amountIn Amount of input tokens
  /// @param amountOutMinimum Minimum amount of output tokens
  /// @param recipient Address to receive output tokens
  /// @param dex The DEX to use for swapping
  /// @return amountOut Amount of output tokens received
  function swap(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMinimum,
    address recipient,
    DexType dex
  ) public nonReentrant sphereXGuardPublic(0x789bf729, 0x60a14780) returns (uint256 amountOut) {
    validateSwapParams(tokenIn, tokenOut, amountIn, recipient);
    address router = routers[uint8(dex)];
    if (router == address(0)) revert RouterNotSupported();

    if (dex == DexType.UNISWAP_V3 || dex == DexType.SUSHISWAP_V3 || dex == DexType.KODIAK_V3) {
      address factory = factories[uint8(dex)];
      if (factory == address(0)) revert FactoryNotSupported();
      return _swapV3(tokenIn, tokenOut, amountIn, amountOutMinimum, recipient, router, factory);
    } else if (dex == DexType.UNISWAP_V2 || dex == DexType.SUSHISWAP_V2 || dex == DexType.KODIAK_V2) {
      if (router == address(0)) revert RouterNotSupported();
      return _swapV2(tokenIn, tokenOut, amountIn, amountOutMinimum, recipient, router);
    } else if (dex == DexType.CAMELOT_V3) {
      return _swapCamelotV3(tokenIn, tokenOut, amountIn, amountOutMinimum, recipient, router);
    } else if (dex == DexType.BEX) {
      address crocQuery = crocQueries[uint8(dex)];
      if (crocQuery == address(0)) revert CrocQueryNotSupported();
      return _swapCroc(tokenIn, tokenOut, amountIn, amountOutMinimum, recipient, router, crocQuery);
    }

    revert UnsupportedDexType();
  }

  /// @notice Swaps tokens using a specified path with Uniswap V3 by default
  /// @param path Array of token addresses in swap path
  /// @param amountIn Amount of input tokens
  /// @param amountOutMinimum Minimum amount of output tokens
  /// @param recipient Address to receive output tokens
  /// @return amountOut Amount of output tokens received
  function swapWithPathWithDefaultDex(
    address[] calldata path,
    uint256 amountIn,
    uint256 amountOutMinimum,
    address recipient
  ) public nonReentrant sphereXGuardPublic(0x44451493, 0x2eab94fb) returns (uint256 amountOut) {
    return swapWithPath(path, amountIn, amountOutMinimum, recipient, defaultDex);
  }

  /// @notice Swaps tokens using a specified path and DEX
  /// @param path Array of token addresses in swap path
  /// @param amountIn Amount of input tokens
  /// @param amountOutMinimum Minimum amount of output tokens
  /// @param recipient Address to receive output tokens
  /// @param dex The DEX to use for swapping
  /// @return amountOut Amount of output tokens received
  function swapWithPath(
    address[] calldata path,
    uint256 amountIn,
    uint256 amountOutMinimum,
    address recipient,
    DexType dex
  ) public nonReentrant sphereXGuardPublic(0x6cc09310, 0x36760864) returns (uint256 amountOut) {
    validateSwapWithPathParams(path, amountIn, recipient);
    if (dex == DexType.UNISWAP_V3 || dex == DexType.SUSHISWAP_V3 || dex == DexType.KODIAK_V3) {
      return _swapV3WithPath(path, amountIn, amountOutMinimum, recipient, routers[uint8(dex)], factories[uint8(dex)]);
    } else if (dex == DexType.UNISWAP_V2 || dex == DexType.SUSHISWAP_V2 || dex == DexType.KODIAK_V2) {
      return _swapV2WithPath(path, amountIn, amountOutMinimum, recipient, routers[uint8(dex)]);
    } else if (dex == DexType.BEX) {
      return
        _swapCrocWithPath(path, amountIn, amountOutMinimum, recipient, routers[uint8(dex)], crocQueries[uint8(dex)]);
    }

    revert UnsupportedDexType();
  }

  /// @notice Gets quote for token swap using default DEX (BEX)
  /// @param tokenIn Address of input token
  /// @param tokenOut Address of output token
  /// @param amountIn Amount of input tokens
  /// @return amountOut Expected amount of output tokens
  function getQuoteWithDefaultDex(
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  ) external view returns (uint256 amountOut) {
    return getQuote(tokenIn, tokenOut, amountIn, defaultDex);
  }

  /// @notice Gets quote for token swap using specified DEX
  /// @param tokenIn Address of input token
  /// @param tokenOut Address of output token
  /// @param amountIn Amount of input tokens
  /// @param dex The DEX to get quote from
  /// @return amountOut Expected amount of output tokens
  function getQuote(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    DexType dex
  ) public view returns (uint256 amountOut) {
    _revertAddressZero(tokenIn);
    _revertAddressZero(tokenOut);
    _revertZeroAmount(amountIn);

    address router = routers[uint8(dex)];
    address factory = factories[uint8(dex)];
    address crocQuery = crocQueries[uint8(dex)];

    if (dex == DexType.KODIAK_V3) {
      if (factory == address(0)) revert FactoryNotSupported();
      return _getQuoteV3(tokenIn, tokenOut, amountIn, factory, true);
    } else if (dex == DexType.UNISWAP_V3 || dex == DexType.SUSHISWAP_V3) {
      if (factory == address(0)) revert FactoryNotSupported();
      return _getQuoteV3(tokenIn, tokenOut, amountIn, factory, false);
    } else if (dex == DexType.UNISWAP_V2 || dex == DexType.SUSHISWAP_V2 || dex == DexType.KODIAK_V2) {
      if (router == address(0)) revert RouterNotSupported();
      return _getQuoteV2(tokenIn, tokenOut, amountIn, router);
    } else if (dex == DexType.BEX) {
      if (crocQuery == address(0)) revert CrocQueryNotSupported();
      if (router == address(0)) revert RouterNotSupported();
      return _getQuoteCroc(tokenIn, tokenOut, amountIn, router, crocQuery);
    }

    revert UnsupportedDexType();
  }

  /// @notice Gets quote for token swap with path using default DEX (BEX)
  /// @param path Array of token addresses in swap path
  /// @param amountIn Amount of input tokens
  /// @return amountOut Expected amount of output tokens
  function getQuoteWithPathWithDefaultDex(
    address[] memory path,
    uint256 amountIn
  ) external view returns (uint256 amountOut) {
    return getQuoteWithPath(path, amountIn, defaultDex);
  }

  /// @notice Gets quote for token swap with path using specified DEX
  /// @param path Array of token addresses in swap path
  /// @param amountIn Amount of input tokens
  /// @param dex The DEX to get quote from
  /// @return amountOut Expected amount of output tokens
  function getQuoteWithPath(
    address[] memory path,
    uint256 amountIn,
    DexType dex
  ) public view returns (uint256 amountOut) {
    _revertInvalidPathLength(path.length);
    _revertZeroAmount(amountIn);

    address factory = factories[uint8(dex)];
    address router = routers[uint8(dex)];
    address crocQuery = crocQueries[uint8(dex)];

    if (dex == DexType.KODIAK_V3) {
      if (factory == address(0)) revert FactoryNotSupported();
      return _getQuoteV3WithPath(path, amountIn, factory, true);
    } else if (dex == DexType.UNISWAP_V3 || dex == DexType.SUSHISWAP_V3) {
      if (factory == address(0)) revert FactoryNotSupported();
      return _getQuoteV3WithPath(path, amountIn, factory, false);
    } else if (dex == DexType.UNISWAP_V2 || dex == DexType.SUSHISWAP_V2 || dex == DexType.KODIAK_V2) {
      if (router == address(0)) revert RouterNotSupported();
      return _getQuoteV2WithPath(path, amountIn, router);
    } else if (dex == DexType.BEX) {
      if (crocQuery == address(0)) revert CrocQueryNotSupported();
      if (router == address(0)) revert RouterNotSupported();
      return _getQuoteCrocWithPath(path, amountIn, router, crocQuery);
    }

    revert UnsupportedDexType();
  }

  // **** Internal Functions **** //

  /// @notice Reverts if the address is zero
  /// @param _address The address to check
  function _revertAddressZero(address _address) internal pure {
    if (_address == address(0)) revert ZeroAddress();
  }

  /// @notice Reverts if the amount is zero
  /// @param amountIn The amount to check
  function _revertZeroAmount(uint256 amountIn) internal pure {
    if (amountIn == 0) revert ZeroAmount();
  }

  /// @notice Reverts if the path length is less than 2
  /// @param pathLength The length of the path to check
  function _revertInvalidPathLength(uint256 pathLength) internal pure {
    if (pathLength < 2) revert InvalidPathLength();
  }

  /// @notice Finds the most liquid V3 pool for a token pair
  /// @param tokenIn Address of input token
  /// @param tokenOut Address of output token
  /// @param factory Address of V3 factory
  /// @return bestPool Address of most liquid pool
  /// @return highestLiquidity Liquidity amount of best pool
  function _findMostLiquidV3Pool(
    address tokenIn,
    address tokenOut,
    address factory
  ) internal view returns (address bestPool, uint128 highestLiquidity) {
    uint24[4] memory fees = [uint24(500), uint24(3000), uint24(1000), uint24(10000)];

    for (uint256 i = 0; i < fees.length; i++) {
      address poolAddress = IUniswapV3Factory(factory).getPool(tokenIn, tokenOut, fees[i]);
      if (poolAddress != address(0)) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        uint128 liquidity = pool.liquidity();
        if (liquidity > highestLiquidity) {
          highestLiquidity = liquidity;
          bestPool = poolAddress;
        }
      }
    }
  }

  /// @notice Finds the most liquid Croc pool for a token pair
  /// @param tokenIn Address of input token
  /// @param tokenOut Address of output token
  /// @param crocQuery Address of CrocQuery contract
  /// @return bestPoolIdx Index of best pool
  /// @return highestLiquidity Liquidity amount of best pool
  function _findMostLiquidCrocPool(
    address tokenIn,
    address tokenOut,
    address crocQuery
  ) internal view returns (uint256 bestPoolIdx, uint128 highestLiquidity) {
    uint256[3] memory poolIdx = [uint256(36000), uint256(36001), uint256(36002)];
    for (uint256 i = 0; i < poolIdx.length; i++) {
      // base-side token in the pool's pair is always the smaller address
      (address base, address quote) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);
      uint128 liquidity = ICrocQuery(crocQuery).queryLiquidity(base, quote, poolIdx[i]);
      if (liquidity > highestLiquidity) {
        highestLiquidity = liquidity;
        bestPoolIdx = poolIdx[i];
      }
    }
  }

  function _swapWithRoute(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMinimum,
    address recipient
  ) internal sphereXGuardInternal(0xf01e8b19) returns (uint256 amountOut) {
    currentPathLength++;
    if (currentPathLength >= MAX_PATH_LENGTH) revert PathLengthExceeded();

    SwapRoutePath[] memory route = swapRoutes[tokenIn][tokenOut];
    if (route.length == 0) revert NoSwapRouteFound();

    for (uint256 i = 0; i < route.length; i++) {
      SwapRoutePath memory path = route[i];
      if (path.isMultiPath) {
        // recursive call, be careful here
        amountOut = _swapWithRoute(path.tokenIn, path.tokenOut, amountIn, 0, address(this));
      } else {
        amountOut = swap(path.tokenIn, path.tokenOut, amountIn, 0, address(this), path.dex);
      }
      amountIn = amountOut;
    }
    if (amountOut < amountOutMinimum) revert InsufficientOutputAmount(amountOut, amountOutMinimum);
    IERC20(tokenOut).safeTransfer(recipient, amountOut);
    return amountOut;
  }

  /// @notice Performs a swap using Uniswap V3 or compatible DEX
  /// @dev Attempts direct swap first, falls back to path through wrapped native token
  /// @param tokenIn Address of input token
  /// @param tokenOut Address of output token
  /// @param amountIn Amount of input tokens
  /// @param amountOutMinimum Minimum amount of output tokens
  /// @param recipient Address to receive output tokens
  /// @param router V3 router address
  /// @param factory V3 factory address
  /// @return amountOut Amount of output tokens received
  function _swapV3(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMinimum,
    address recipient,
    address router,
    address factory
  ) internal sphereXGuardInternal(0xd2c5d247) returns (uint256 amountOut) {
    // first try to find the direct pool between tokenIn and tokenOut
    (address poolAddress, ) = _findMostLiquidV3Pool(tokenIn, tokenOut, factory);
    IERC20(tokenIn).forceApprove(router, amountIn);
    if (poolAddress == address(0)) {
      // if no direct pool is found, try to find a pool between tokenIn and WETH and then between WETH and tokenOut
      address[] memory path = new address[](3);
      path[0] = tokenIn;
      path[1] = wrappedNative;
      path[2] = tokenOut;
      return _swapV3WithPath(path, amountIn, amountOutMinimum, recipient, router, factory);
    } else {
      IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router.ExactInputSingleParams({
        tokenIn: tokenIn,
        tokenOut: tokenOut,
        fee: IUniswapV3Pool(poolAddress).fee(),
        recipient: recipient,
        deadline: block.timestamp,
        amountIn: amountIn,
        amountOutMinimum: amountOutMinimum,
        sqrtPriceLimitX96: 0
      });

      return IUniswapV3Router(router).exactInputSingle(params);
    }
  }

  /// @notice Performs a swap using Uniswap V3 with a specified path
  /// @param path Array of token addresses in swap path
  /// @param amountIn Amount of input tokens
  /// @param amountOutMinimum Minimum amount of output tokens
  /// @param recipient Address to receive output tokens
  /// @param router V3 router address
  /// @param factory V3 factory address
  /// @return amountOut Amount of output tokens received
  function _swapV3WithPath(
    address[] memory path,
    uint256 amountIn,
    uint256 amountOutMinimum,
    address recipient,
    address router,
    address factory
  ) internal sphereXGuardInternal(0x7d29fbe4) returns (uint256 amountOut) {
    bytes memory pathBytes = abi.encodePacked(path[0]);
    for (uint256 i = 0; i < path.length - 1; i++) {
      (address poolAddress, ) = _findMostLiquidV3Pool(path[i], path[i + 1], factory);
      if (poolAddress == address(0)) revert NoPoolFoundForMultihopSwap();
      pathBytes = abi.encodePacked(pathBytes, IUniswapV3Pool(poolAddress).fee(), path[i + 1]);
    }
    IERC20(path[0]).forceApprove(router, amountIn);
    IUniswapV3Router.ExactInputParams memory params = IUniswapV3Router.ExactInputParams({
      path: pathBytes,
      recipient: recipient,
      deadline: block.timestamp,
      amountIn: amountIn,
      amountOutMinimum: amountOutMinimum
    });

    return IUniswapV3Router(router).exactInput(params);
  }

  /// @notice Performs a swap using Uniswap V2 or compatible DEX
  /// @param tokenIn Address of input token
  /// @param tokenOut Address of output token
  /// @param amountIn Amount of input tokens
  /// @param amountOutMinimum Minimum amount of output tokens
  /// @param recipient Address to receive output tokens
  /// @param router V2 router address
  /// @return amountOut Amount of output tokens received
  function _swapV2(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMinimum,
    address recipient,
    address router
  ) internal sphereXGuardInternal(0xd8b71976) returns (uint256 amountOut) {
    address[] memory path;

    if (tokenIn == wrappedNative || tokenOut == wrappedNative) {
      path = new address[](2);
      path[0] = tokenIn;
      path[1] = tokenOut;
    } else {
      path = new address[](3);
      path[0] = tokenIn;
      path[1] = wrappedNative;
      path[2] = tokenOut;
    }

    IERC20(tokenIn).forceApprove(router, amountIn);
    uint256 balanceBefore = IERC20(tokenOut).balanceOf(recipient);
    UniswapRouterV2(router).swapExactTokensForTokens(amountIn, 0, path, recipient, block.timestamp);
    amountOut = IERC20(tokenOut).balanceOf(recipient) - balanceBefore;
    if (amountOut < amountOutMinimum) revert InsufficientOutputAmount(amountOut, amountOutMinimum);
  }

  /// @notice Performs a swap using Uniswap V2 with a specified path
  /// @param path Array of token addresses in swap path
  /// @param amountIn Amount of input tokens
  /// @param amountOutMinimum Minimum amount of output tokens
  /// @param recipient Address to receive output tokens
  /// @param router V2 router address
  /// @return amountOut Amount of output tokens received
  function _swapV2WithPath(
    address[] memory path,
    uint256 amountIn,
    uint256 amountOutMinimum,
    address recipient,
    address router
  ) internal sphereXGuardInternal(0x0de072e7) returns (uint256 amountOut) {
    IERC20(path[0]).forceApprove(router, amountIn);
    uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(recipient);
    UniswapRouterV2(router).swapExactTokensForTokens(amountIn, 0, path, recipient, block.timestamp);
    amountOut = IERC20(path[path.length - 1]).balanceOf(recipient) - balanceBefore;
    if (amountOut < amountOutMinimum) revert InsufficientOutputAmount(amountOut, amountOutMinimum);
  }

  /// @notice Performs a swap using Camelot V3
  /// @param tokenIn Address of input token
  /// @param tokenOut Address of output token
  /// @param amountIn Amount of input tokens
  /// @param amountOutMinimum Minimum amount of output tokens
  /// @param recipient Address to receive output tokens
  /// @return amountOut Amount of output tokens received
  function _swapCamelotV3(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMinimum,
    address recipient,
    address router
  ) internal sphereXGuardInternal(0x43ac8f1c) returns (uint256 amountOut) {
    IERC20(tokenIn).forceApprove(router, amountIn);
    ICamelotRouterV3.ExactInputSingleParams memory params = ICamelotRouterV3.ExactInputSingleParams({
      tokenIn: tokenIn,
      tokenOut: tokenOut,
      recipient: recipient,
      deadline: block.timestamp,
      amountIn: amountIn,
      amountOutMinimum: amountOutMinimum,
      sqrtPriceLimitX96: 0
    });
    return ICamelotRouterV3(router).exactInputSingle(params);
  }

  /// @notice Performs a swap using Croc Multi Swap
  /// @param tokenIn Address of input token
  /// @param tokenOut Address of output token
  /// @param amountIn Amount of input tokens
  /// @param amountOutMinimum Minimum amount of output tokens
  /// @param recipient Address to receive output tokens
  /// @param router Croc Multi Swap router address
  /// @param crocQuery CrocQuery contract address
  /// @return amountOut Amount of output tokens received
  function _swapCroc(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMinimum,
    address recipient,
    address router,
    address crocQuery
  ) internal sphereXGuardInternal(0xeecfdaae) returns (uint256 amountOut) {
    IERC20(tokenIn).forceApprove(router, amountIn);
    (, uint128 liquidity) = _findMostLiquidCrocPool(tokenIn, tokenOut, crocQuery);
    address[] memory path;
    if (liquidity != 0) {
      path = new address[](2);
      path[0] = tokenIn;
      path[1] = tokenOut;
    } else {
      path = new address[](3);
      path[0] = tokenIn;
      path[1] = wrappedNative;
      path[2] = tokenOut;
    }
    return _swapCrocWithPath(path, amountIn, amountOutMinimum, recipient, router, crocQuery);
  }

  /// @notice Performs a swap using Croc Multi Swap with a specified path
  /// @param path Array of token addresses in swap path
  /// @param amountIn Amount of input tokens
  /// @param amountOutMinimum Minimum amount of output tokens
  /// @param recipient Address to receive output tokens
  /// @param router Croc Multi Swap router address
  /// @param crocQuery CrocQuery contract address
  /// @return amountOut Amount of output tokens received
  function _swapCrocWithPath(
    address[] memory path,
    uint256 amountIn,
    uint256 amountOutMinimum,
    address recipient,
    address router,
    address crocQuery
  ) internal sphereXGuardInternal(0x5ecdcc7d) returns (uint256 amountOut) {
    ICrocMultiSwap.SwapStep[] memory swapStep = new ICrocMultiSwap.SwapStep[](path.length - 1);
    IERC20(path[0]).approve(router, amountIn);
    for (uint i = 0; i < path.length - 1; i++) {
      (uint256 poolIdx, uint128 liquidity) = _findMostLiquidCrocPool(path[i], path[i + 1], crocQuery);
      if (liquidity == 0) revert NoPoolFoundForMultihopSwap();
      // base token should always be less then quote token
      if (path[i] < path[i + 1]) {
        swapStep[i] = ICrocMultiSwap.SwapStep(poolIdx, path[i], path[i + 1], true);
      } else {
        swapStep[i] = ICrocMultiSwap.SwapStep(poolIdx, path[i + 1], path[i], false);
      }
    }
    amountOut = ICrocMultiSwap(payable(router)).multiSwap(swapStep, uint128(amountIn), uint128(amountOutMinimum));
    IERC20(path[path.length - 1]).safeTransfer(recipient, amountOut);
  }

  /// @notice Gets a quote for Croc swap
  /// @dev Internal function used by getQuoteCroc
  /// @param tokenIn Address of input token
  /// @param tokenOut Address of output token
  /// @param amountIn Amount of input tokens
  /// @param router Croc Multi Swap router address
  /// @param crocQuery CrocQuery contract address
  /// @return amountOut Expected amount of output tokens
  function _getQuoteCroc(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    address router,
    address crocQuery
  ) internal view returns (uint256 amountOut) {
    (, uint128 liquidity) = _findMostLiquidCrocPool(tokenIn, tokenOut, crocQuery);

    address[] memory path;
    if (liquidity == 0) {
      // if no direct pool is found, try to find a pool between tokenIn and WrappedNative and then between WrappedNative and tokenOut
      path = new address[](3);
      path[0] = tokenIn;
      path[1] = wrappedNative;
      path[2] = tokenOut;
    } else {
      path = new address[](2);
      path[0] = tokenIn;
      path[1] = tokenOut;
    }

    return _getQuoteCrocWithPath(path, amountIn, router, crocQuery);
  }

  /// @notice Gets a quote for Croc swap with path
  /// @dev Internal function used by getQuoteCrocWithPath
  /// @param path Array of token addresses in swap path
  /// @param amountIn Amount of input tokens
  /// @param router Croc Multi Swap router address
  /// @param crocQuery CrocQuery contract address
  /// @return amountOut Expected amount of output tokens
  function _getQuoteCrocWithPath(
    address[] memory path,
    uint256 amountIn,
    address router,
    address crocQuery
  ) internal view returns (uint256 amountOut) {
    ICrocMultiSwap.SwapStep[] memory swapStep = new ICrocMultiSwap.SwapStep[](path.length - 1);
    for (uint i = 0; i < path.length - 1; i++) {
      (uint256 poolIdx, uint128 liquidity) = _findMostLiquidCrocPool(path[i], path[i + 1], crocQuery);
      if (liquidity == 0) revert NoPoolFoundForMultihopSwap();
      if (path[i] < path[i + 1]) {
        // base token should always be less then quote token
        swapStep[i] = ICrocMultiSwap.SwapStep(poolIdx, path[i], path[i + 1], true);
      } else {
        swapStep[i] = ICrocMultiSwap.SwapStep(poolIdx, path[i + 1], path[i], false);
      }
    }
    (amountOut, ) = ICrocMultiSwap(payable(router)).previewMultiSwap(swapStep, uint128(amountIn));
  }

  /// @notice Gets a quote for V3 swap
  /// @dev Internal function used by getQuoteV3
  /// @param tokenIn Address of input token
  /// @param tokenOut Address of output token
  /// @param amountIn Amount of input tokens
  /// @param factory V3 factory address
  /// @return amountOut Expected amount of output tokens
  function _getQuoteV3(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    address factory,
    bool isFeeProtocolTypeUint32
  ) internal view returns (uint256 amountOut) {
    (address poolAddress, ) = _findMostLiquidV3Pool(tokenIn, tokenOut, factory);

    if (poolAddress == address(0)) {
      // if no direct pool is found, try to find a pool between tokenIn and WETH and then between WETH and tokenOut
      address[] memory path = new address[](3);
      path[0] = tokenIn;
      path[1] = wrappedNative;
      path[2] = tokenOut;
      return _getQuoteV3WithPath(path, amountIn, factory, isFeeProtocolTypeUint32);
    }

    int24 tick;
    // some uniswap v3 forks use uint32 for fee protocol type, so we need to use a different interface to fetch the tick
    if (isFeeProtocolTypeUint32) {
      IUniswapV3PoolWithUint32FeeProtocol pool = IUniswapV3PoolWithUint32FeeProtocol(poolAddress);
      (, tick, , , , , ) = pool.slot0();
    } else {
      IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
      (, tick, , , , , ) = pool.slot0();
    }

    // Call Oracle to get the price at the given tick
    amountOut = OracleLibrary.getQuoteAtTick(
      tick,
      uint128(amountIn), // Casting to uint128 since the library expects this type
      tokenIn,
      tokenOut
    );
  }

  /// @notice Gets a quote for V3 swap with path
  /// @dev Internal function used by getQuoteV3WithPath
  /// @param path Array of token addresses in swap path
  /// @param amountIn Amount of input tokens
  /// @param factory V3 factory address
  /// @return amountOut Expected amount of output tokens
  function _getQuoteV3WithPath(
    address[] memory path,
    uint256 amountIn,
    address factory,
    bool isFeeProtocolTypeUint32
  ) internal view returns (uint256 amountOut) {
    for (uint256 i = 0; i < path.length - 1; i++) {
      (address poolAddress, ) = _findMostLiquidV3Pool(path[i], path[i + 1], factory);
      if (poolAddress == address(0)) revert NoPoolFoundForMultihopQuote();

      int24 tick;
      // some uniswap v3 forks use uint32 for fee protocol type, so we need to use a different interface to fetch the tick
      if (isFeeProtocolTypeUint32) {
        IUniswapV3PoolWithUint32FeeProtocol pool = IUniswapV3PoolWithUint32FeeProtocol(poolAddress);
        (, tick, , , , , ) = pool.slot0();
      } else {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (, tick, , , , , ) = pool.slot0();
      }

      // Call Oracle to get the price at the given tick
      amountOut = OracleLibrary.getQuoteAtTick(
        tick,
        uint128(amountIn), // Casting to uint128 since the library expects this type
        path[i],
        path[i + 1]
      );
      // amount in is now the amount out of the last pool
      amountIn = amountOut;
    }
  }

  /// @notice Gets quote for V2 swap
  /// @param tokenIn Address of input token
  /// @param tokenOut Address of output token
  /// @param amountIn Amount of input tokens
  /// @param router Router address
  /// @return amountOut Expected amount of output tokens
  function _getQuoteV2(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    address router
  ) internal view returns (uint256 amountOut) {
    address[] memory path;
    if (tokenIn == wrappedNative || tokenOut == wrappedNative) {
      path = new address[](2);
      path[0] = tokenIn;
      path[1] = tokenOut;
    } else {
      path = new address[](3);
      path[0] = tokenIn;
      path[1] = wrappedNative;
      path[2] = tokenOut;
    }

    return _getQuoteV2WithPath(path, amountIn, router);
  }

  /// @notice Gets quote for V2 swap with path
  /// @param path Array of token addresses in swap path
  /// @param amountIn Amount of input tokens
  /// @param router Router address
  /// @return amountOut Expected amount of output tokens
  function _getQuoteV2WithPath(
    address[] memory path,
    uint256 amountIn,
    address router
  ) internal view returns (uint256 amountOut) {
    uint256[] memory amounts = UniswapRouterV2(router).getAmountsOut(amountIn, path);
    return amounts[amounts.length - 1];
  }
}
