// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICrocMultiSwap {
  struct SwapStep {
    uint256 poolIdx;
    address base;
    address quote;
    bool isBuy;
  }

  /**
   * @notice Preview a series of swaps between multiple pools.
   * @param _steps The series of swap steps to be performed in sequence.
   * @param _amount The input amount for the swap
   * @return out The amount to be received from the multiswap.
   * @return predictedQty The predicted amount to be received from the multiswap if
   *         there is no price impact.
   */
  function previewMultiSwap(
    SwapStep[] calldata _steps,
    uint128 _amount
  ) external view returns (uint128 out, uint256 predictedQty);

  /**
   * @notice Performs a series of swaps between multiple pools.
   * @param _steps The series of swap steps to be performed in sequence.
   * @param _amount The input amount for the swap
   * @param _minOut The minimum output amount acceptable
   * @return out The amount received from the multiswap
   */
  function multiSwap(SwapStep[] memory _steps, uint128 _amount, uint128 _minOut) external payable returns (uint128 out);

  /**
   * @notice Allows the deployer to retire the contract and recover funds
   */
  function retire() external;

  /**
   * @notice Allows the contract to receive ETH
   */
  receive() external payable;
}

library CurveMath {
  struct CurveState {
    uint128 priceRoot_;
    uint128 ambientSeeds_;
    uint128 concLiq_;
    uint64 seedDeflator_;
    uint64 concGrowth_;
  }
}

library PoolSpecs {
  struct Pool {
    uint8 schema_;
    uint16 feeRate_;
    uint8 protocolTake_;
    uint16 tickSize_;
    uint8 jitThresh_;
    uint8 knockoutBits_;
    uint8 oracleFlags_;
  }
}

/* @notice Interface for reading and parsing the internal state of a CrocSwapDex contract. */
interface ICrocQuery {
  function dex_() external view returns (address);

  function queryCurve(
    address base,
    address quote,
    uint256 poolIdx
  ) external view returns (CurveMath.CurveState memory curve);

  function queryPoolParams(
    address base,
    address quote,
    uint256 poolIdx
  ) external view returns (PoolSpecs.Pool memory pool);

  function queryPoolTemplate(uint256 poolIdx) external view returns (PoolSpecs.Pool memory pool);

  function queryCurveTick(address base, address quote, uint256 poolIdx) external view returns (int24);

  function queryLiquidity(address base, address quote, uint256 poolIdx) external view returns (uint128);

  function queryPrice(address base, address quote, uint256 poolIdx) external view returns (uint128);

  function querySurplus(address owner, address token) external view returns (uint128 surplus);

  function queryVirtual(address owner, address tracker, uint256 salt) external view returns (uint128 surplus);

  function queryProtocolAccum(address token) external view returns (uint128);

  function queryLevel(
    address base,
    address quote,
    uint256 poolIdx,
    int24 tick
  ) external view returns (uint96 bidLots, uint96 askLots, uint64 odometer);

  function queryKnockoutPivot(
    address base,
    address quote,
    uint256 poolIdx,
    bool isBid,
    int24 tick
  ) external view returns (uint96 lots, uint32 pivot, uint16 range);

  function queryKnockoutMerkle(
    address base,
    address quote,
    uint256 poolIdx,
    bool isBid,
    int24 tick
  ) external view returns (uint160 root, uint32 pivot, uint64 fee);

  function queryKnockoutPos(
    address owner,
    address base,
    address quote,
    uint256 poolIdx,
    uint32 pivot,
    bool isBid,
    int24 lowerTick,
    int24 upperTick
  ) external view returns (uint96 lots, uint64 mileage, uint32 timestamp);

  function queryRangePosition(
    address owner,
    address base,
    address quote,
    uint256 poolIdx,
    int24 lowerTick,
    int24 upperTick
  ) external view returns (uint128 liq, uint64 fee, uint32 timestamp, bool atomic);

  function queryAmbientPosition(
    address owner,
    address base,
    address quote,
    uint256 poolIdx
  ) external view returns (uint128 seeds, uint32 timestamp);

  function queryConcRewards(
    address owner,
    address base,
    address quote,
    uint256 poolIdx,
    int24 lowerTick,
    int24 upperTick
  ) external view returns (uint128 liqRewards, uint128 baseRewards, uint128 quoteRewards);

  function queryAmbientTokens(
    address owner,
    address base,
    address quote,
    uint256 poolIdx
  ) external view returns (uint128 liq, uint128 baseQty, uint128 quoteQty);

  function queryRangeTokens(
    address owner,
    address base,
    address quote,
    uint256 poolIdx,
    int24 lowerTick,
    int24 upperTick
  ) external view returns (uint128 liq, uint128 baseQty, uint128 quoteQty);

  function queryKnockoutTokens(
    address owner,
    address base,
    address quote,
    uint256 poolIdx,
    uint32 pivot,
    bool isBid,
    int24 lowerTick,
    int24 upperTick
  ) external view returns (uint128 liq, uint128 baseQty, uint128 quoteQty, bool knockedOut);

  function queryPoolAmbientTokens(
    address base,
    address quote,
    uint256 poolIdx
  ) external view returns (uint128 liq, uint128 baseQty, uint128 quoteQty);
}

interface ICrocImpact {
  function calcImpact(
    address base,
    address quote,
    uint256 poolIdx,
    bool isBuy,
    bool inBaseQty,
    uint128 qty,
    uint16 tip,
    uint128 limitPrice
  ) external view returns (int128 baseFlow, int128 quoteFlow, uint128 finalPrice);
}

interface ICrocSwapDex {
  function userCmd(uint16 callpath, bytes calldata cmd) external payable returns (bytes memory);
}

interface ICropSwapLp is IERC20 {
  function baseToken() external view returns (address);

  function quoteToken() external view returns (address);

  function poolType() external view returns (uint256);
}
