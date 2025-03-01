// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ZapperBase} from "./ZapperBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IDexType} from "../interfaces/IDexType.sol";
import {ILpRouter} from "../interfaces/ILpRouter.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";
import {IIndexUtils, IDecentralizedIndex, IStakingPoolToken} from "../interfaces/arbera/IArbera.sol";
import {UniswapRouterV2, IUniswapV2Pair, IUniswapV2Factory} from "../interfaces/exchange/UniswapV2.sol";
import {SphereXProtected} from "@spherex-xyz/contracts/src/SphereXProtected.sol";

/**
 * @title ArberaZapper
 * @notice A zapper contract that enables single-token deposits and withdrawals for Arbera Strategy
 */
contract ArberaZapper is ZapperBase {
  using SafeERC20 for IERC20;

  IIndexUtils public immutable indexUtils;

  constructor(
    address devAddress,
    address wrappedNative,
    address stablecoin,
    address swapRouter,
    address lpRouter,
    address feeRecipient,
    uint16 zapInFee,
    uint16 zapOutFee,
    address indexUtilsAddress
  ) ZapperBase(devAddress, wrappedNative, stablecoin, swapRouter, lpRouter, feeRecipient, zapInFee, zapOutFee) {
    indexUtils = IIndexUtils(indexUtilsAddress);
  }

  /**
   * @notice Converts input token amount to vault's asset
   * @param asset The vault's asset
   * @param tokenIn The token being deposited
   * @param tokenInAmount The amount of tokens being deposited
   * @param recipient The address to receive the asset
   * @return tokenOutAmount Amount of asset received
   * @return returnedAssets Array of remaining token balances to be returned to the user
   */
  function swapToAssets(
    address asset,
    address tokenIn,
    uint256 tokenInAmount,
    address recipient
  )
    public
    override
    sphereXGuardPublic(0xfa35917e, 0x3218e83a)
    returns (uint256 tokenOutAmount, ReturnedAsset[] memory returnedAssets)
  {
    if (recipient != address(this)) {
      tokenInAmount = _safeTransferFromTokens(tokenIn, tokenInAmount);
    }
    IDecentralizedIndex indexToken = IDecentralizedIndex(IStakingPoolToken(asset).indexFund()); //brHoney
    address pairedToken = indexToken.PAIRED_LP_TOKEN(); // Honey
    if (address(tokenIn) != pairedToken) {
      IERC20(tokenIn).safeTransfer(address(swapRouter), tokenInAmount);
      tokenInAmount = swapRouter.swapWithDefaultDex(address(tokenIn), pairedToken, tokenInAmount, 0, address(this));
    }

    uint256 pairedTokenAmount = tokenInAmount / 2;
    uint256 indexTokenAmount = tokenInAmount - pairedTokenAmount;

    // go with the swap route, we have another function for the bonding route
    IERC20(pairedToken).safeTransfer(address(swapRouter), indexTokenAmount);
    indexTokenAmount = swapRouter.swap(
      pairedToken,
      address(indexToken),
      indexTokenAmount,
      0,
      address(this),
      IDexType.DexType.KODIAK_V2
    );

    // Approve to add lp and stake
    IERC20(indexToken).forceApprove(address(indexUtils), indexTokenAmount);
    IERC20(pairedToken).forceApprove(address(indexUtils), pairedTokenAmount);

    // Add LP and stake
    indexUtils.addLPAndStake(indexToken, indexTokenAmount, pairedToken, pairedTokenAmount, 0, 1000, block.timestamp);
    tokenOutAmount = IERC20(asset).balanceOf(address(this));
    if (recipient != address(this)) {
      IERC20(asset).safeTransfer(recipient, tokenOutAmount);
    }

    address[] memory tokens = new address[](3);
    tokens[0] = pairedToken;
    tokens[1] = address(indexToken);
    tokens[2] = address(tokenIn);
    returnedAssets = _returnAssets(tokens);
  }

  /**
   * @notice Converts vault's asset to output token
   * @param asset The vault's asset
   * @param tokenOut The token the user wants to receive
   * @param assetsInAmount The amount of LP tokens being withdrawn
   * @param recipient The address to receive the output token
   * @return tokenOutAmount The amount of desired tokens received
   * @return returnedAssets Array of remaining token balances to be returned to the user
   */
  function swapFromAssets(
    address asset,
    address tokenOut,
    uint256 assetsInAmount,
    address recipient
  )
    public
    override
    sphereXGuardPublic(0xac974bee, 0xf99e6387)
    returns (uint256 tokenOutAmount, ReturnedAsset[] memory returnedAssets)
  {
    if (recipient != address(this)) {
      assetsInAmount = _safeTransferFromTokens(asset, assetsInAmount);
    }
    IStakingPoolToken stakingPoolToken = IStakingPoolToken(asset); // sbrHoney
    IDecentralizedIndex indexToken = IDecentralizedIndex(stakingPoolToken.indexFund()); //brHoney
    address pairedToken = indexToken.PAIRED_LP_TOKEN(); // Honey

    // Unstake and remove LP
    IERC20(stakingPoolToken).forceApprove(address(indexUtils), assetsInAmount);
    indexUtils.unstakeAndRemoveLP(indexToken, assetsInAmount, 0, 0, block.timestamp);

    // go with the swap route, we have another function for the bonding route
    tokenOutAmount = indexToken.balanceOf(address(this));
    IERC20(address(indexToken)).safeTransfer(address(swapRouter), tokenOutAmount);
    swapRouter.swap(address(indexToken), pairedToken, tokenOutAmount, 0, address(this), IDexType.DexType.KODIAK_V2);

    tokenOutAmount = IERC20(pairedToken).balanceOf(address(this));

    // swap paired token to desired token
    if (address(tokenOut) != pairedToken) {
      IERC20(pairedToken).safeTransfer(address(swapRouter), tokenOutAmount);
      tokenOutAmount = swapRouter.swapWithDefaultDex(
        address(pairedToken),
        address(tokenOut),
        tokenOutAmount,
        0,
        address(this)
      );
    }

    if (recipient != address(this)) {
      _returnAsset(tokenOut, recipient);
    }

    address[] memory tokens = new address[](2);
    tokens[0] = tokenOut == pairedToken ? address(0) : pairedToken;
    tokens[1] = tokenOut == address(indexToken) ? address(0) : address(indexToken);
    returnedAssets = _returnAssets(tokens);
  }

  /**
   * @notice Converts input token amount to vault's asset
   * @param asset The vault's asset
   * @param tokenIn The token being deposited
   * @param tokenInAmount The amount of tokens being deposited
   * @param recipient The address to receive the asset
   * @return tokenOutAmount Amount of asset received
   * @return returnedAssets Array of remaining token balances to be returned to the user
   */
  function swapToAssetsWithBond(
    address asset,
    address tokenIn,
    uint256 tokenInAmount,
    address recipient
  )
    public
    sphereXGuardPublic(0x5bfe9fc2, 0xd2dd8d50)
    returns (uint256 tokenOutAmount, ReturnedAsset[] memory returnedAssets)
  {
    if (recipient != address(this)) {
      tokenInAmount = _safeTransferFromTokens(tokenIn, tokenInAmount);
    }
    IDecentralizedIndex indexToken = IDecentralizedIndex(IStakingPoolToken(asset).indexFund()); //brHoney
    address pairedToken = indexToken.PAIRED_LP_TOKEN(); // Honey
    if (address(tokenIn) != pairedToken) {
      IERC20(tokenIn).safeTransfer(address(swapRouter), tokenInAmount);
      tokenInAmount = swapRouter.swapWithDefaultDex(address(tokenIn), pairedToken, tokenInAmount, 0, address(this));
    }

    (uint256 pairedTokenAmount, uint256 indexTokenAmount) = _getAmounts(
      tokenInAmount,
      pairedToken,
      address(indexToken)
    );

    // bond here instead of swap
    IERC20(pairedToken).forceApprove(address(indexUtils), indexTokenAmount);
    indexUtils.bond(indexToken, pairedToken, indexTokenAmount, 0);
    indexTokenAmount = indexToken.balanceOf(address(this));

    // Approve to add lp and stake
    IERC20(indexToken).forceApprove(address(indexUtils), indexTokenAmount);
    IERC20(pairedToken).forceApprove(address(indexUtils), pairedTokenAmount);

    // Add LP and stake
    indexUtils.addLPAndStake(indexToken, indexTokenAmount, pairedToken, pairedTokenAmount, 0, 1000, block.timestamp);
    tokenOutAmount = IERC20(asset).balanceOf(address(this));
    if (recipient != address(this)) {
      IERC20(asset).safeTransfer(recipient, tokenOutAmount);
    }

    address[] memory tokens = new address[](3);
    tokens[0] = pairedToken;
    tokens[1] = address(indexToken);
    tokens[2] = address(tokenIn);
    returnedAssets = _returnAssets(tokens);
  }

  /**
   * @notice Converts vault's asset to output token
   * @param asset The vault's asset
   * @param tokenOut The token the user wants to receive
   * @param assetsInAmount The amount of LP tokens being withdrawn
   * @param recipient The address to receive the output token
   * @return tokenOutAmount The amount of desired tokens received
   * @return returnedAssets Array of remaining token balances to be returned to the user
   */
  function swapFromAssetsWithBond(
    address asset,
    address tokenOut,
    uint256 assetsInAmount,
    address recipient
  )
    public
    sphereXGuardPublic(0xa65bb9c9, 0xa877b4af)
    returns (uint256 tokenOutAmount, ReturnedAsset[] memory returnedAssets)
  {
    if (recipient != address(this)) {
      assetsInAmount = _safeTransferFromTokens(asset, assetsInAmount);
    }
    IStakingPoolToken stakingPoolToken = IStakingPoolToken(asset); // sbrHoney
    IDecentralizedIndex indexToken = IDecentralizedIndex(stakingPoolToken.indexFund()); //brHoney
    address pairedToken = indexToken.PAIRED_LP_TOKEN(); // Honey

    // Unstake and remove LP
    IERC20(stakingPoolToken).forceApprove(address(indexUtils), assetsInAmount);
    indexUtils.unstakeAndRemoveLP(indexToken, assetsInAmount, 0, 0, block.timestamp);

    uint256 indexTokenAmount = indexToken.balanceOf(address(this));
    // unbound here instead of swap
    indexToken.debond(indexTokenAmount, new address[](0), new uint8[](0));

    tokenOutAmount = IERC20(pairedToken).balanceOf(address(this));
    // swap paired token to desired token
    if (address(tokenOut) != pairedToken) {
      IERC20(pairedToken).safeTransfer(address(swapRouter), tokenOutAmount);
      tokenOutAmount = swapRouter.swapWithDefaultDex(
        address(pairedToken),
        address(tokenOut),
        tokenOutAmount,
        0,
        address(this)
      );
    }

    if (recipient != address(this)) {
      _returnAsset(tokenOut, recipient);
    }

    address[] memory tokens = new address[](2);
    tokens[0] = tokenOut == pairedToken ? address(0) : pairedToken;
    tokens[1] = tokenOut == address(indexToken) ? address(0) : address(indexToken);
    returnedAssets = _returnAssets(tokens);
  }

  /**
   * @dev Given a total amount of a base token (e.g., Honey), we want to split this
   * amount into two portions:
   *
   *  - `pairedTokenAmount`: The portion that remains as the paired token (e.g., Honey).
   *  - `indexTokenAmount`: The portion that will be wrapped into the index token (e.g., brHoney),
   *    which applies a fee.
   *
   * Our goal is to add liquidity to a Uniswap V2 pair consisting of `pairedToken` and `indexToken`.
   * To do this correctly, the amounts we add must reflect the ratio present in the liquidity pool.
   * Additionally, because `indexToken` is a wrapped version of the token and has a fee when wrapping,
   * we must choose `pairedTokenAmount` and `indexTokenAmount` such that after fees, the ratio still
   * matches the pool ratio.
   *
   * ---------------------------
   * Understanding the Problem:
   * ---------------------------
   * We have:
   *
   *   - Total amount of base token: `totalAmount`.
   *   - Two tokens in the pool: `pairedToken` and `indexToken`.
   *   - The current reserves in the pool: `pairedTokenReserves` and `indexTokenReserves`.
   *
   * The ratio of the pool is given by:
   *
   *   ratio = indexTokenReserves / pairedTokenReserves
   *
   * When we wrap the `indexTokenAmount`, it is reduced by certain fees:
   *
   *   totalFees = fees.bond + fees.partner
   *
   * These fees are expressed in parts per 10,000. For example, if totalFees = 1500, that's 15%.
   *
   * After wrapping `indexTokenAmount`, the effective amount of `indexToken` we end up with is:
   *
   *   indexTokenAfterFees = indexTokenAmount * (10000 - totalFees) / 10000
   *
   * For the pool ratio to remain correct after adding these tokens, we need:
   *
   *   indexTokenAfterFees / pairedTokenAmount = ratioNum / ratioDen
   *
   * where:
   *   ratioNum = indexTokenReserves
   *   ratioDen = pairedTokenReserves
   *
   * ----------------------------
   * Deriving the Formula:
   * ----------------------------
   * We know:
   *
   *   pairedTokenAmount + indexTokenAmount = totalAmount   ...(1)
   *
   * And from the ratio requirement:
   *
   *   (indexTokenAmount * (10000 - totalFees) / 10000) / pairedTokenAmount = ratioNum / ratioDen
   *
   * Rearranging this ratio equation:
   *
   *   (indexTokenAmount * (10000 - totalFees)) / (10000 * pairedTokenAmount) = ratioNum / ratioDen
   *
   * Substitute indexTokenAmount from (1): indexTokenAmount = totalAmount - pairedTokenAmount
   *
   *   ((totalAmount - pairedTokenAmount) * (10000 - totalFees)) / (10000 * pairedTokenAmount) = ratioNum / ratioDen
   *
   * Multiply both sides by (10000 * pairedTokenAmount):
   *
   *   (totalAmount - pairedTokenAmount) * (10000 - totalFees) = ratioNum * (pairedTokenAmount * 10000 / ratioDen)
   *
   * Expand the left side:
   *
   *   totalAmount * (10000 - totalFees) - pairedTokenAmount * (10000 - totalFees) = ratioNum * (pairedTokenAmount * 10000 / ratioDen)
   *
   * Move the term involving pairedTokenAmount to one side:
   *
   *   totalAmount * (10000 - totalFees) = pairedTokenAmount * ( (10000 - totalFees) + (ratioNum * (10000 / ratioDen)) )
   *
   * Factor out pairedTokenAmount:
   *
   *   pairedTokenAmount = [ totalAmount * (10000 - totalFees) ] / [ (10000 - totalFees) + (ratioNum * 10000 / ratioDen) ]
   *
   * Multiply numerator and denominator by ratioDen to clear the fraction:
   *
   *   pairedTokenAmount = ( totalAmount * (10000 - totalFees) * ratioDen )
   *                       / ( (10000 - totalFees)*ratioDen + ratioNum*10000 )
   *
   * Once pairedTokenAmount is known:
   *
   *   indexTokenAmount = totalAmount - pairedTokenAmount
   *
   * With these amounts, after the fee deduction on indexTokenAmount, the ratio matches the pool's ratio.
   *
   * ----------------------------------------
   * Implementation Details in Solidity:
   * ----------------------------------------
   * Since we're dealing with integer math, we must carefully maintain the order of operations.
   * All multiplications are done before divisions to minimize truncation errors.
   *
   * This function:
   * - Fetches the pair reserves to determine ratioNum and ratioDen.
   * - Retrieves the fees to determine totalFees.
   * - Uses the derived formula to compute the correct pairedTokenAmount and indexTokenAmount.
   *
   * By following this approach, when we add these amounts to the pool,
   * the resulting ratio (after wrapping and fees on the index token) is correct.
   */

  function _getAmounts(
    uint256 totalAmount,
    address pairedToken,
    address indexToken
  ) internal view returns (uint256 pairedTokenAmount, uint256 indexTokenAmount) {
    address factory = UniswapRouterV2(swapRouter.routers(uint8(IDexType.DexType.KODIAK_V2))).factory();
    // Get the Uniswap V2 pair for the two tokens
    IUniswapV2Pair pair = IUniswapV2Pair(IUniswapV2Factory(factory).getPair(pairedToken, indexToken));
    (uint256 pairedTokenReserves, uint256 indexTokenReserves, ) = pair.getReserves();

    // Ensure the reserves are aligned such that:
    // pairedTokenReserves correspond to the 'pairedToken'
    // indexTokenReserves correspond to the 'indexToken'
    if (pair.token0() != pairedToken) {
      uint256 temp = pairedTokenReserves;
      pairedTokenReserves = indexTokenReserves;
      indexTokenReserves = temp;
    }

    // Calculate the ratio components from the pool
    uint256 ratioNum = indexTokenReserves; // numerator of the ratio (indexToken side)
    uint256 ratioDen = pairedTokenReserves; // denominator of the ratio (pairedToken side)

    // Retrieve fee information from the index token
    IDecentralizedIndex.Fees memory fees = IDecentralizedIndex(indexToken).fees();
    uint16 totalFees = fees.bond + fees.partner;

    /*
      Formula derived:

      pairedTokenAmount = ( totalAmount * (10000 - totalFees) * ratioDen )
                          / ( (10000 - totalFees)*ratioDen + ratioNum*10000 )

      indexTokenAmount = totalAmount - pairedTokenAmount
    */

    pairedTokenAmount =
      (totalAmount * (10000 - totalFees) * ratioDen) /
      (((10000 - totalFees) * ratioDen) + (ratioNum * 10000));

    indexTokenAmount = totalAmount - pairedTokenAmount;
  }

  /**
   * @notice Deposits tokens into a vault after converting them if necessary
   * @param vault Target vault
   * @param tokenIn Input token address
   * @param tokenInAmount Amount of input tokens
   * @param minShares Minimum amount of vault shares to receive
   * @return shares Number of vault shares received
   * @return returnedAssets Array of any remaining tokens returned to caller
   */
  function zapIn(
    IVault vault,
    address tokenIn,
    uint256 tokenInAmount,
    uint256 minShares
  )
    external
    payable
    override
    nonReentrant
    sphereXGuardExternal(0x621b094a)
    returns (uint256 shares, ReturnedAsset[] memory returnedAssets)
  {
    // if eth is the tokenIn, we need to convert it to the wrappedNative
    if (tokenIn == address(0)) {
      if (msg.value < MINIMUM_AMOUNT) revert InsufficientInputAmount(address(0), msg.value, MINIMUM_AMOUNT);
      wrappedNative.deposit{value: msg.value}();
      tokenIn = address(wrappedNative);
      tokenInAmount = msg.value;
    } else {
      if (tokenInAmount < MINIMUM_AMOUNT) revert InsufficientInputAmount(tokenIn, tokenInAmount, MINIMUM_AMOUNT);
      tokenInAmount = _safeTransferFromTokens(tokenIn, tokenInAmount);
    }

    // transfer the fee
    uint256 feeAmount;
    (tokenInAmount, feeAmount) = _transferFee(tokenIn, zapInFee, tokenInAmount);

    // convert the input token to the vault's asset if needed
    uint256 assetsIn;
    if (vault.asset() != tokenIn) {
      (assetsIn, returnedAssets) = swapToAssets(vault.asset(), tokenIn, tokenInAmount, address(this));
    }

    // approve the asset to the vault
    IERC20(vault.asset()).forceApprove(address(vault), assetsIn);

    // deposit the asset to the vault
    shares = vault.deposit(assetsIn, msg.sender, minShares);
    vault.earn();
    emit ZapIn(msg.sender, address(vault), tokenIn, tokenInAmount, assetsIn, shares, feeAmount, returnedAssets);
  }

  /**
   * @notice Deposits tokens into a vault after converting them if necessary
   * @param vault Target vault
   * @param tokenIn Input token address
   * @param tokenInAmount Amount of input tokens
   * @param minShares Minimum amount of vault tokens to receive
   * @return shares Number of vault shares received
   * @return returnedAssets Array of any remaining tokens returned to caller
   */
  function zapInWithBond(
    IVault vault,
    address tokenIn,
    uint256 tokenInAmount,
    uint256 minShares
  )
    external
    payable
    nonReentrant
    sphereXGuardExternal(0x4828dc7a)
    returns (uint256 shares, ReturnedAsset[] memory returnedAssets)
  {
    // if eth is the tokenIn, we need to convert it to the wrappedNative
    if (address(tokenIn) == address(0)) {
      if (msg.value < MINIMUM_AMOUNT) revert InsufficientInputAmount(address(0), msg.value, MINIMUM_AMOUNT);
      wrappedNative.deposit{value: msg.value}();
      tokenIn = address(wrappedNative);
      tokenInAmount = msg.value;
    } else {
      if (tokenInAmount < MINIMUM_AMOUNT)
        revert InsufficientInputAmount(address(tokenIn), tokenInAmount, MINIMUM_AMOUNT);
      tokenInAmount = _safeTransferFromTokens(address(tokenIn), tokenInAmount);
    }

    // transfer the fee
    uint256 feeAmount;
    (tokenInAmount, feeAmount) = _transferFee(tokenIn, zapInFee, tokenInAmount);

    // convert the input token to the vault's asset if needed
    uint256 assetsIn;
    if (vault.asset() != address(tokenIn)) {
      (assetsIn, returnedAssets) = swapToAssetsWithBond(vault.asset(), address(tokenIn), tokenInAmount, address(this));
    }

    // approve the vault's asset to the vault to deposit
    IERC20(vault.asset()).forceApprove(address(vault), assetsIn);

    // deposit the converted token to the vault
    shares = vault.deposit(assetsIn, msg.sender, minShares);
    vault.earn();
    emit ZapIn(msg.sender, address(vault), tokenIn, tokenInAmount, assetsIn, shares, feeAmount, returnedAssets);
  }

  /**
   * @notice Withdraws from vault and converts to desired token
   * @param vault Source vault
   * @param sharesAmount Amount of vault shares to withdraw
   * @param tokenOut Desired output token
   * @param minTokenOutAmount Minimum amount of desired tokens to receive
   * @return tokenOutAmount Amount of output tokens received
   * @return returnedAssets Array of any remaining tokens returned to caller
   */
  function zapOutWithBond(
    IVault vault,
    uint256 sharesAmount,
    address tokenOut,
    uint256 minTokenOutAmount
  )
    external
    virtual
    nonReentrant
    sphereXGuardExternal(0x811f5fd6)
    returns (uint256 tokenOutAmount, ReturnedAsset[] memory returnedAssets)
  {
    uint256 assetsOut = IVault(vault).redeem(sharesAmount, address(this), msg.sender);
    // if eth is the desiredToken, we need to convert it to the wrappedNative
    if (tokenOut == address(0)) {
      tokenOut = address(wrappedNative);
    }

    // transfer the fee
    uint256 feeAmount;

    // convert the vault's asset to the desired token
    if (vault.asset() == tokenOut) {
      tokenOutAmount = assetsOut;
    } else {
      (tokenOutAmount, returnedAssets) = swapFromAssetsWithBond(vault.asset(), tokenOut, assetsOut, address(this));
    }

    (assetsOut, feeAmount) = _transferFee(tokenOut, zapOutFee, assetsOut);
    // return the tokens
    _returnAsset(tokenOut, msg.sender);

    if (tokenOutAmount < minTokenOutAmount)
      revert InsufficientOutputAmount(tokenOut, tokenOutAmount, minTokenOutAmount);
    emit ZapOut(
      msg.sender,
      address(vault),
      tokenOut,
      tokenOutAmount,
      assetsOut,
      sharesAmount,
      feeAmount,
      returnedAssets
    );
  }
}
