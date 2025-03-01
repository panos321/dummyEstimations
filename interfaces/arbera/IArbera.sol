// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IDecentralizedIndex is IERC20 {
  // Structs
  struct Config {
    address partner;
    bool hasTransferTax;
    bool blacklistTKNpTKNPoolV2;
  }

  struct Fees {
    uint16 buy;
    uint16 sell;
    uint16 burn;
    uint16 bond;
    uint16 debond;
    uint16 partner;
  }

  struct IndexAssetInfo {
    address token;
    uint basePriceUSDX96;
    uint weighting;
    address c1;
    uint q1;
  }

  enum IndexType {
    WEIGHTED
  }

  // Events
  event Bond(address indexed user, address token, uint amount, uint tokensMinted);
  event Debond(address indexed user, uint amount);
  event AddLiquidity(address indexed user, uint idxLPTokens, uint pairedLPTokens);
  event RemoveLiquidity(address indexed user, uint lpTokens);
  event FlashLoan(address indexed caller, address indexed recipient, address token, uint amount);
  event SetPartner(address indexed caller, address partner);
  event SetPartnerFee(address indexed caller, uint16 fee);
  event Initialize(address indexed caller, address v2Pool);

  // External Functions
  function initialize(
    string memory _name,
    string memory _symbol,
    Config memory _config,
    Fees memory _fees,
    address[] memory _tokens,
    uint[] memory _weights,
    address _pairedLpToken,
    address _lpRewardsToken,
    address _dexHandler
  ) external;

  function initializeStakingPool(address _stakingPoolToken) external;

  function bond(address _token, uint _amount, uint _amountMintMin) external;

  function debond(uint _amount, address[] memory tokens, uint8[] memory amounts) external;

  function burn(uint _amount) external;

  function addLiquidityV2(
    uint _idxLPTokens,
    uint _pairedLPTokens,
    uint _slippage,
    uint _deadline
  ) external returns (uint);

  function removeLiquidityV2(uint _lpTokens, uint _minIdxTokens, uint _minPairedLpToken, uint _deadline) external;

  function flash(address _recipient, address _token, uint _amount, bytes calldata _data) external;

  function rescueERC20(address _token) external;

  function rescueETH() external;

  function manualProcessFee(uint _slip) external;

  function processPreSwapFeesAndSwap() external;

  function setPartner(address _partner) external;

  function setPartnerFee(uint16 _fee) external;

  // View Functions
  function getInitialAmount(
    address _sourceToken,
    uint _sourceAmount,
    address _targetToken
  ) external view returns (uint);

  function partner() external view returns (address);

  function BOND_FEE() external view returns (uint16);

  function DEBOND_FEE() external view returns (uint16);

  function isAsset(address _token) external view returns (bool);

  function getAllAssets() external view returns (IndexAssetInfo[] memory);

  function FLASH_FEE_AMOUNT_DAI() external view returns (uint);

  function PAIRED_LP_TOKEN() external view returns (address);

  function indexType() external view returns (IndexType);

  function created() external view returns (uint);

  function lpRewardsToken() external view returns (address);

  function lpStakingPool() external view returns (address);

  function config() external view returns (Config memory);

  function fees() external view returns (Fees memory);

  function indexTokens(uint index) external view returns (IndexAssetInfo memory);
}

interface IIndexUtils {
  /**
   * @notice Bonds tokens to an index fund
   */
  function bond(IDecentralizedIndex _indexFund, address _token, uint _amount, uint _amountMintMin) external;

  /**
   * @notice Bonds native tokens to a weighted index fund
   */
  function bondWeightedFromNative(
    IDecentralizedIndex _indexFund,
    uint _assetIdx,
    uint _amountTokensForAssetIdx,
    uint _amountMintMin,
    uint _amountPairedLpTokenMin,
    uint _slippage,
    uint _deadline,
    bool _stakeAsWell
  ) external payable;

  /**
   * @notice Adds liquidity and stakes LP tokens
   */
  function addLPAndStake(
    IDecentralizedIndex _indexFund,
    uint _amountIdxTokens,
    address _pairedLpTokenProvided,
    uint _amtPairedLpTokenProvided,
    uint _amountPairedLpTokenMin,
    uint _slippage,
    uint _deadline
  ) external payable;

  /**
   * @notice Unstakes and removes liquidity
   */
  function unstakeAndRemoveLP(
    IDecentralizedIndex _indexFund,
    uint _amountStakedTokens,
    uint _minLPTokens,
    uint _minPairedLpToken,
    uint _deadline
  ) external;

  /**
   * @notice Claims rewards from multiple reward contracts
   */
  function claimRewardsMulti(address[] memory _rewards) external;
}

interface IStakingPoolToken is IERC20 {
  // Events
  event Stake(address indexed caller, address indexed user, uint amount);
  event Unstake(address indexed user, uint amount);

  // View Functions
  function indexFund() external view returns (address);

  function poolRewards() external view returns (address);

  function stakeUserRestriction() external view returns (address);

  function stakingToken() external view returns (address);

  function rewardsDistributor() external view returns (address);

  function farm() external view returns (address);

  // State-Changing Functions
  function initialize(
    address _owner,
    address _indexFund,
    address _poolRewards,
    address _stakeUserRestriction,
    address _rewardsDistributor
  ) external;

  function stake(address _user, uint _amount) external;

  function unstake(uint _amount) external;

  function setStakingToken(address _stakingToken) external;

  function setFarm(address _farm) external;

  function removeStakeUserRestriction() external;

  function setStakeUserRestriction(address _user) external;

  // Constants
  function KDK() external pure returns (address);

  function XKDK() external pure returns (address);
}

interface IStakingRewardsDistributor {
  event AddShares(address indexed wallet, uint amount);

  event RemoveShares(address indexed wallet, uint amount);

  event ClaimReward(address indexed wallet);

  event DistributeReward(address indexed wallet, address indexed token, uint amount);

  event DepositRewards(address indexed wallet, address indexed token, uint amount);

  function initialize(address _indexFund, address _pairedLpToken, address _tokenRewards) external;

  function setTrackingToken(address _trackingToken) external;

  function totalShares() external view returns (uint);

  function totalStakers() external view returns (uint);

  function trackingToken() external view returns (address);

  function claimReward(address wallet) external;

  function getUnpaid(address _token, address _wallet) external view returns (uint);

  function setShares(address wallet, uint amount, bool sharesRemoving) external;

  function depositRewards(address _token, uint _amount) external;
}
