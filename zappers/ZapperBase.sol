// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IWETH} from "../interfaces/exchange/IWETH.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";
import {ILpRouter} from "../interfaces/ILpRouter.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IZapper} from "../interfaces/IZapper.sol";
import {SphereXProtected} from "@spherex-xyz/contracts/src/SphereXProtected.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ZapperBase
 * @notice Base contract for implementing zapper functionality that allows users to deposit/withdraw
 * from vaults using any token through automated swaps
 * @dev This is an abstract contract that should be inherited by specific zapper implementations
 */
abstract contract ZapperBase is SphereXProtected, ReentrancyGuard, IZapper {
  using Address for address;
  using SafeERC20 for IERC20;
  using SafeERC20 for IVault;

  /// @notice Minimum token amount required for zap operations to prevent dust transactions
  uint16 public constant MINIMUM_AMOUNT = 1000;

  /// @notice Maximum fee that can be set (10% = 1000 basis points)
  uint16 public constant MAX_FEE = 1000;

  /// @notice Maximum fee that can be set in basis points (100% = 10000 basis points)
  uint16 public constant MAX_FEE_BPS = 10000;

  /// @notice The wrapped version of the native token (e.g., WBERA)
  IWETH public immutable wrappedNative;

  /// @notice The fee percentage for zapIn operations in basis points (1/10000)
  uint16 public zapInFee;

  /// @notice The fee percentage for zapOut operations in basis points (1/10000)
  uint16 public zapOutFee;

  /// @notice The stablecoin token contract used for price calculations and intermediate swaps
  IERC20 public stablecoin;

  /// @notice Address of the contract administrator with special privileges
  address public governance;

  /// @notice Router contract used for token swaps
  ISwapRouter public swapRouter;

  /// @notice Router contract used for add or remove Liquidity
  ILpRouter public lpRouter;

  /// @notice Address that receives the fees
  address public feeRecipient;

  /**
   * @notice Constructs the ZapperBase contract
   * @param devAddress Address of the contract administrator
   * @param wrappedNativeAddress Address of the wrapped native token (e.g. WBERA)
   * @param stablecoinAddress Address of the stablecoin token
   * @param swapRouterAddress Address of the swap router contract
   * @param lpRouterAddress Address of the lp router contract
   * @param feeRecipientAddress Address that receives the fees
   * @param initialZapInFee Initial zapIn fee percentage in basis points
   * @param initialZapOutFee Initial zapOut fee percentage in basis points
   */
  constructor(
    address devAddress,
    address wrappedNativeAddress,
    address stablecoinAddress,
    address swapRouterAddress,
    address lpRouterAddress,
    address feeRecipientAddress,
    uint16 initialZapInFee,
    uint16 initialZapOutFee
  ) {
    if (
      devAddress == address(0) ||
      wrappedNativeAddress == address(0) ||
      stablecoinAddress == address(0) ||
      swapRouterAddress == address(0) ||
      lpRouterAddress == address(0) ||
      feeRecipientAddress == address(0)
    ) revert ZeroAddress();

    governance = devAddress;
    wrappedNative = IWETH(wrappedNativeAddress);

    wrappedNative.deposit{value: 0}();
    wrappedNative.withdraw(0);

    stablecoin = IERC20(stablecoinAddress);
    swapRouter = ISwapRouter(swapRouterAddress);
    lpRouter = ILpRouter(lpRouterAddress);

    if (initialZapInFee > MAX_FEE) revert FeeTooHigh(initialZapInFee, MAX_FEE);
    if (initialZapOutFee > MAX_FEE) revert FeeTooHigh(initialZapOutFee, MAX_FEE);

    feeRecipient = feeRecipientAddress;
    zapInFee = initialZapInFee;
    zapOutFee = initialZapOutFee;
  }

  /// @notice Restricts function access to only the governance address
  modifier onlyGovernance() {
    if (msg.sender != governance) revert NotGovernance();
    _;
  }

  /**
   * @notice Updates the governance address, only callable by governance
   * @param governanceAddress New governance address
   */
  function setGovernance(address governanceAddress) external onlyGovernance {
    _revertAddressZero(governanceAddress);
    governance = governanceAddress;
    emit GovernanceChanged(governanceAddress, governance);
  }

  /**
   * @notice Updates the swap router address, only callable by governance
   * @param routerAddress New swap router address
   */
  function setSwapRouter(address routerAddress) external onlyGovernance sphereXGuardExternal(0xd473ef3c) {
    _revertAddressZero(routerAddress);
    address old = address(swapRouter);
    swapRouter = ISwapRouter(routerAddress);
    emit SwapRouterChanged(old, routerAddress);
  }

  /**
   * @notice Updates the lp router address, only callable by governance
   * @param routerAddress New lp router address
   */
  function setLpRouter(address routerAddress) external onlyGovernance sphereXGuardExternal(0x26b2eef4) {
    _revertAddressZero(routerAddress);
    address old = address(lpRouter);
    lpRouter = ILpRouter(routerAddress);
    emit LpRouterChanged(old, routerAddress);
  }

  /**
   * @notice Updates the stablecoin address, only callable by governance
   * @param stablecoinAddress New stablecoin address
   */
  function setStableCoin(address stablecoinAddress) external onlyGovernance sphereXGuardExternal(0x5b9fdae4) {
    _revertAddressZero(stablecoinAddress);
    stablecoin = IERC20(stablecoinAddress);
    emit StableCoinChanged(address(stablecoin), stablecoinAddress);
  }

  /**
   * @notice Updates the zapIn fee percentage, only callable by governance
   * @param newFee New fee percentage in basis points
   */
  function setZapInFee(uint16 newFee) external onlyGovernance {
    if (newFee > MAX_FEE) revert FeeTooHigh(newFee, MAX_FEE);
    uint16 oldFee = zapInFee;
    zapInFee = newFee;
    emit ZapInFeeChanged(oldFee, newFee);
  }

  /**
   * @notice Updates the zapOut fee percentage, only callable by governance
   * @param newFee New fee percentage in basis points
   */
  function setZapOutFee(uint16 newFee) external onlyGovernance {
    if (newFee > MAX_FEE) revert FeeTooHigh(newFee, MAX_FEE);
    uint16 oldFee = zapOutFee;
    zapOutFee = newFee;
    emit ZapOutFeeChanged(oldFee, newFee);
  }

  /**
   * @notice Updates the fee recipient address, only callable by governance
   * @param newRecipient New address to receive fees
   */
  function setFeeRecipient(address newRecipient) external onlyGovernance {
    _revertAddressZero(newRecipient);
    address oldRecipient = feeRecipient;
    feeRecipient = newRecipient;
    emit FeeRecipientChanged(oldRecipient, newRecipient);
  }

  receive() external payable {
    assert(msg.sender == address(wrappedNative));
  }

  /** Internal functions */

  function _revertAddressZero(address addressToCheck) internal pure {
    if (addressToCheck == address(0)) revert ZeroAddress();
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

  function _safeTransferFromTokens(
    address token,
    uint256 amount
  ) internal sphereXGuardInternal(0x9ffc4661) returns (uint256) {
    if (IERC20(token).allowance(msg.sender, address(this)) < amount) revert TokenNotApproved();
    uint256 balanceBefore = IERC20(token).balanceOf(address(this));
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    uint256 balanceAfter = IERC20(token).balanceOf(address(this));
    return balanceAfter - balanceBefore;
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
   * @notice Returns any remaining tokens to the caller
   * @param tokens Array of token addresses to check and return
   * @return returnedAssets Array of ReturnedAsset structs containing token addresses and amounts returned
   */
  function _returnAssets(
    address[] memory tokens
  ) internal sphereXGuardInternal(0x65afacc1) returns (ReturnedAsset[] memory returnedAssets) {
    uint256 balance;

    returnedAssets = new ReturnedAsset[](tokens.length);
    for (uint256 i = 0; i < tokens.length; i++) {
      if (tokens[i] == address(0)) continue;
      balance = IERC20(tokens[i]).balanceOf(address(this));
      returnedAssets[i] = ReturnedAsset({tokens: tokens[i], amounts: balance});
      if (balance > 0) {
        if (tokens[i] == address(wrappedNative)) {
          wrappedNative.withdraw(balance);
          (bool success, ) = msg.sender.call{value: balance}(new bytes(0));
          if (!success) revert ETHTransferFailed();
        } else {
          IERC20(tokens[i]).safeTransfer(msg.sender, balance);
        }
      }
    }
  }

  /**
   * @notice Returns any remaining tokens to the caller
   * @param token The token to return
   * @param recipient The address to return the token to
   * @return amount The amount of tokens returned
   */
  function _returnAsset(
    address token,
    address recipient
  ) internal sphereXGuardInternal(0xf45372f8) returns (uint256 amount) {
    amount = IERC20(token).balanceOf(address(this));
    _returnAssetWithAmount(token, recipient, amount);
  }

  /**
   * @notice Returns the amount of tokens to the caller, if the token is wrappedNative, it will be converted to native token
   * @param token The token to return
   * @param recipient The address to return the token to
   * @param amount The amount of tokens to return
   */
  function _returnAssetWithAmount(address token, address recipient, uint256 amount) internal {
    if (amount > 0) {
      if (token == address(wrappedNative)) {
        wrappedNative.withdraw(amount);
        (bool success, ) = recipient.call{value: amount}(new bytes(0));
        if (!success) revert ETHTransferFailed();
      } else {
        IERC20(token).safeTransfer(recipient, amount);
      }
    }
  }

  /**
   * @notice Transfers the fee to the fee recipient
   * @param token The token to transfer
   * @param fee The fee percentage in basis points
   * @param amount The amount of tokens to transfer
   * @return amount The amount of tokens after the fee is transferred
   */
  function _transferFee(address token, uint16 fee, uint256 amount) internal returns (uint256, uint256 feeAmount) {
    if (fee > 0) {
      feeAmount = (amount * fee) / MAX_FEE_BPS;
      _returnAssetWithAmount(token, feeRecipient, feeAmount);
      amount -= feeAmount;
    }
    return (amount, feeAmount);
  }

  /**
   * @notice Converts input token balance of address(this) to vault's desired token
   * @param asset The asset to convert
   * @param tokenIn The input token to convert
   * @return assetsOut Amount of converted assets
   * @return returnedAssets Array of any remaining tokens returned to caller
   */
  function swapToAssets(
    address asset,
    address tokenIn,
    uint256 tokenInAmount,
    address recipient
  ) public virtual returns (uint256 assetsOut, ReturnedAsset[] memory returnedAssets);

  /**
   * @notice Converts vault's desired token balance to output token
   * @param asset The asset to convert
   * @param tokenOut The output token to convert
   * @return tokenOutAmount Amount of converted tokens
   * @return returnedAssets Array of any remaining tokens returned to caller
   */
  function swapFromAssets(
    address asset,
    address tokenOut,
    uint256 assetsInAmount,
    address recipient
  ) public virtual returns (uint256 tokenOutAmount, ReturnedAsset[] memory returnedAssets);

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
    virtual
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
    if (vault.asset() != tokenIn) {
      (tokenInAmount, returnedAssets) = swapToAssets(vault.asset(), tokenIn, tokenInAmount, address(this));
    }

    // approve the asset to the vault
    IERC20(vault.asset()).forceApprove(address(vault), tokenInAmount);

    // deposit the asset to the vault
    shares = vault.deposit(tokenInAmount, msg.sender, minShares);
    emit ZapIn(msg.sender, address(vault), tokenIn, tokenInAmount, shares, feeAmount);
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
  function zapOut(
    IVault vault,
    uint256 sharesAmount,
    address tokenOut,
    uint256 minTokenOutAmount
  )
    external
    virtual
    nonReentrant
    sphereXGuardExternal(0xaf73b205)
    returns (uint256 tokenOutAmount, ReturnedAsset[] memory returnedAssets)
  {
    uint256 assetsOut = IVault(vault).redeem(sharesAmount, address(this), msg.sender);

    // if eth is the desiredToken, we need to convert it to the wrappedNative
    if (tokenOut == address(0)) {
      tokenOut = address(wrappedNative);
    }

    // convert the asset to the desired token if needed
    if (vault.asset() == tokenOut) {
      tokenOutAmount = assetsOut;
    } else {
      (tokenOutAmount, returnedAssets) = swapFromAssets(vault.asset(), tokenOut, assetsOut, address(this));
    }

    // transfer the fee
    uint256 feeAmount;
    (tokenOutAmount, feeAmount) = _transferFee(tokenOut, zapOutFee, tokenOutAmount);

    // return the token
    _returnAsset(tokenOut, msg.sender);

    if (tokenOutAmount < minTokenOutAmount)
      revert InsufficientOutputAmount(tokenOut, tokenOutAmount, minTokenOutAmount);
    emit ZapOut(msg.sender, address(vault), tokenOut, tokenOutAmount, sharesAmount, feeAmount);
  }
}
