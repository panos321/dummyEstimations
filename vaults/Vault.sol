// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "../localdeps/ERC20.sol";
import {ERC4626} from "../localdeps/ERC4626.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IController} from "../interfaces/IController.sol";
import {IVault} from "../interfaces/IVault.sol";
import {SphereXProtected} from "@spherex-xyz/contracts/src/SphereXProtected.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Vault
 * @notice An ERC4626-compliant vault that manages user deposits and integrates with a Controller for yield generation
 * @dev Implements the IVault interface and extends ERC4626
 */
contract Vault is SphereXProtected, ReentrancyGuard, ERC4626, IVault {
  using SafeERC20 for IERC20;
  using Address for address;

  /// @notice Maximum ratio denominator (100%)
  uint256 public constant MAX_DENOMINATOR = 10000;

  /// @notice Maximum fee that can be set (10% = 1000 basis points)
  uint16 public constant MAX_FEE = 1000;

  /// @notice The fee percentage for deposit operations in basis points (1/10000)
  uint16 public depositFee;

  /// @notice The fee percentage for withdraw operations in basis points (1/10000)
  uint16 public withdrawFee;

  /// @notice Minimum ratio of assets that can be deposited into the strategy (95%)
  uint256 public min = 9500;

  /// @notice Address with governance privileges
  address public governance;

  /// @notice Address of timelock contract for time-delayed admin actions
  address public timelock;

  /// @notice Address of controller contract that manages strategy interactions
  address public controller;

  /// @notice Address that receives the fees
  address public feeRecipient;

  /**
   * @notice Constructs a new Vault
   * @param asset The address of the underlying asset token
   * @param governanceAddress Address that will have governance privileges
   * @param timelockAddress Address of the timelock contract
   * @param controllerAddress Address of the controller contract
   */
  constructor(
    address asset,
    address governanceAddress,
    address timelockAddress,
    address controllerAddress,
    uint16 initialDepositFee,
    uint16 initialWithdrawFee
  )
    ERC4626(IERC20(asset))
    ERC20(
      string(abi.encodePacked("BeraTrax Vault ", ERC20(asset).name())),
      string(abi.encodePacked("btx", ERC20(asset).symbol()))
    )
  {
    _revertAddressZero(governanceAddress);
    _revertAddressZero(timelockAddress);
    _revertAddressZero(controllerAddress);
    governance = governanceAddress;
    timelock = timelockAddress;
    controller = controllerAddress;

    if (initialDepositFee > MAX_FEE) revert FeeTooHigh(initialDepositFee, MAX_FEE);
    if (initialWithdrawFee > MAX_FEE) revert FeeTooHigh(initialWithdrawFee, MAX_FEE);
    depositFee = initialDepositFee;
    withdrawFee = initialWithdrawFee;
  }

  // **** Modifiers **** //

  /// @notice Restricts function access to governance address
  modifier onlyGovernance() {
    _revertOnlyGovernance();
    _;
  }

  /// @notice Restricts function access to timelock address
  modifier onlyTimelock() {
    _revertOnlyTimelock();
    _;
  }

  /// @notice Restricts function access to controller address
  modifier onlyController() {
    _revertOnlyController();
    _;
  }

  // **** Internal Functions **** //

  /// @notice Reverts if the caller is not the governance address
  function _revertOnlyGovernance() internal view {
    if (msg.sender != governance) revert NotGovernance();
  }

  /// @notice Reverts if the caller is not the timelock address
  function _revertOnlyTimelock() internal view {
    if (msg.sender != timelock) revert NotTimelock();
  }

  /// @notice Reverts if the caller is not the controller address
  function _revertOnlyController() internal view {
    if (msg.sender != controller) revert NotController();
  }

  /// @notice Reverts if the address is zero
  function _revertAddressZero(address _address) internal pure {
    if (_address == address(0)) revert ZeroAddress();
  }

  /**
   * @notice Returns the number of decimals of the vault shares
   * @return uint8 Number of decimals
   */
  function decimals() public view override(ERC4626, IERC20Metadata) returns (uint8) {
    return ERC20(asset()).decimals();
  }

  /**
   * @notice Sets the minimum ratio of assets that must remain in vault
   * @param minRatio New minimum ratio (scaled by max)
   */
  function setMin(uint256 minRatio) external onlyGovernance sphereXGuardExternal(0xdbf26102) {
    if (minRatio > MAX_DENOMINATOR) revert MinGreaterThanMax();
    uint256 old = min;
    min = minRatio;
    emit MinChanged(old, minRatio);
  }

  /**
   * @notice Sets the deposit fee
   * @param newFee The new deposit fee
   */
  function setDepositFee(uint16 newFee) external onlyGovernance {
    if (newFee > MAX_FEE) revert FeeTooHigh(newFee, MAX_FEE);
    uint16 old = depositFee;
    depositFee = newFee;
    emit DepositFeeChanged(old, newFee);
  }

  /**
   * @notice Sets the withdraw fee
   * @param newFee The new withdraw fee
   */
  function setWithdrawFee(uint16 newFee) external onlyGovernance {
    if (newFee > MAX_FEE) revert FeeTooHigh(newFee, MAX_FEE);
    uint16 old = withdrawFee;
    withdrawFee = newFee;
    emit WithdrawFeeChanged(old, newFee);
  }

  /**
   * @notice Updates the governance address
   * @param governanceAddress New governance address
   */
  function setGovernance(address governanceAddress) external onlyGovernance sphereXGuardExternal(0xbbf054c1) {
    _revertAddressZero(governanceAddress);
    address old = governance;
    governance = governanceAddress;
    emit GovernanceChanged(old, governanceAddress);
  }

  /**
   * @notice Updates the timelock address
   * @param timelockAddress New timelock address
   */
  function setTimelock(address timelockAddress) external onlyTimelock sphereXGuardExternal(0x4fdebcf1) {
    _revertAddressZero(timelockAddress);
    address old = timelock;
    timelock = timelockAddress;
    emit TimelockChanged(old, timelockAddress);
  }

  /**
   * @notice Updates the controller address
   * @param controllerAddress New controller address
   */
  function setController(address controllerAddress) external onlyTimelock sphereXGuardExternal(0x431250ca) {
    _revertAddressZero(controllerAddress);
    address old = controller;
    controller = controllerAddress;
    emit ControllerChanged(old, controllerAddress);
  }

  /**
   * @notice Calculates amount of assets the vault allows to be deposited into strategy,
   * min percentage is kept in vault to keep small withdrawals cheap
   * @return uint256 Amount of assets available in vault
   */
  function available() public view returns (uint256) {
    return (IERC20(asset()).balanceOf(address(this)) * min) / MAX_DENOMINATOR;
  }

  /**
   * @notice Returns total assets managed by vault including those in strategy
   * @return uint256 Total assets
   */
  function totalAssets() public view override(ERC4626, IERC4626) returns (uint256) {
    return super.totalAssets() + IController(controller).balanceOf(asset());
  }

  /**
   * @notice Sends available assets to controller to be invested in strategy
   */
  function earn() public nonReentrant sphereXGuardPublic(0xcdf9fc19, 0xd389800f) {
    uint256 vaultAssetBalance = available();
    if (vaultAssetBalance == 0) revert NoFundsToEarn();
    IERC20(asset()).safeTransfer(controller, vaultAssetBalance);
    IController(controller).earn(asset(), vaultAssetBalance);
  }

  /**
   * @notice Allows controller to harvest other tokens from vault
   * @param token Address of token to harvest
   * @param amount Amount of tokens to harvest
   */
  function harvest(
    address token,
    uint256 amount
  ) external nonReentrant onlyController sphereXGuardExternal(0x614d0740) {
    if (token == address(asset())) revert CannotHarvestAsset();
    IERC20(token).safeTransfer(controller, amount);
  }

  /**
   * @notice Internal withdraw function that handles withdrawing from controller if needed
   * @param caller Address initiating withdrawal
   * @param receiver Address receiving assets
   * @param owner Address that owns the shares
   * @param assets Amount of assets to withdraw
   * @param shares Amount of shares to burn
   */
  function _withdraw(
    address caller,
    address receiver,
    address owner,
    uint256 assets,
    uint256 shares
  ) internal override sphereXGuardInternal(0x0532ca1f) {
    uint256 vaultBalance = IERC20(asset()).balanceOf(address(this));
    if (vaultBalance < assets) {
      uint256 withdrawFromController = assets - vaultBalance;
      IController(controller).withdraw(asset(), withdrawFromController);
      uint256 afterWithdraw = IERC20(asset()).balanceOf(address(this));
      uint256 diff = afterWithdraw - vaultBalance;
      if (diff < withdrawFromController) {
        assets = vaultBalance + diff;
      }
    }
    if (withdrawFee > 0) {
      uint256 feeAmount = (assets * withdrawFee) / MAX_DENOMINATOR;
      IERC20(asset()).safeTransfer(feeRecipient, feeAmount);
      assets -= feeAmount;
    }
    super._withdraw(caller, receiver, owner, assets, shares);
  }

  /**
   * @notice Internal deposit function that handles depositing assets with fee
   * @param caller Address initiating deposit
   * @param receiver Address receiving the shares
   * @param assets Amount of assets to deposit
   * @param shares Amount of shares minted
   */
  function _deposit(
    address caller,
    address receiver,
    uint256 assets,
    uint256 shares
  ) internal override sphereXGuardInternal(0xf84768b2) {
    if (depositFee > 0) {
      uint256 feeAmount = (assets * depositFee) / MAX_DENOMINATOR;
      IERC20(asset()).safeTransferFrom(caller, feeRecipient, feeAmount);
      assets -= feeAmount;
    }
    super._deposit(caller, receiver, assets, shares);
  }

  /**
   * @notice Deposits assets with minimum shares check
   * @param assets Amount of assets to deposit
   * @param receiver Address receiving the shares
   * @param minShares Minimum shares that must be minted
   * @return shares Amount of shares minted
   */
  function deposit(
    uint256 assets,
    address receiver,
    uint256 minShares
  ) public nonReentrant sphereXGuardPublic(0x74edf5f2, 0xbc157ac1) returns (uint256 shares) {
    shares = super.deposit(assets, receiver);
    if (shares < minShares) revert InsufficientOutputShares(shares, minShares);
  }

  /**
   * @notice Redeems shares with minimum assets check
   * @param shares Amount of shares to redeem
   * @param receiver Address receiving the assets
   * @param owner Address that owns the shares
   * @param minAssets Minimum assets that must be returned
   * @return assets Amount of assets returned
   */
  function redeem(
    uint256 shares,
    address receiver,
    address owner,
    uint256 minAssets
  ) public nonReentrant sphereXGuardPublic(0xbb53aa86, 0x9f40a7b3) returns (uint256 assets) {
    assets = super.redeem(shares, receiver, owner);
    if (assets < minAssets) revert InsufficientOutputAssets(assets, minAssets);
  }
}
