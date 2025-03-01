//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title BTXStaking Interface
/// @notice Interface for BTX token staking contract
/// @dev Staking contract must implement these methods
interface IBTXStaking {
  // Errors
  // Definition of custom errors
  /// @notice Thrown when a zero address is provided
  error ZeroAddress();
  /// @notice Thrown when caller is not authorized as benevolent (harvester, governance, or strategist)
  error NotBenevolent();
  /// @notice Thrown when caller is not governance
  error NotGovernance();
  /// @notice Thrown when trying to withdraw the strategy's main asset
  error InvalidAsset();
  /// @notice Thrown when ETH transfer is not allowed
  error EthTransferNotAllowed();
  // @ontice Thrown when unstaking amount is less than staked amount or zero
  error AmountLessThanStakedAmountOrZero();
  // @notice Thrown when staking contract has no funds to distribute or migrating to new staking contract having no funds
  error InsufficientFunds();
  // @notice Thrown when migrating to new staking contract with zero staked amount
  error InsufficientBTXFunds();
  // @notice Thrown when migrating to new staking contract but mismatched amounts array against tokens array
  error InputLengthMismatch();
  // @notice Thrown when claiming rewards but no rewards to claim
  error NoPendingRewardsToClaim();
  // @notice Thrown when claiming rewards without having any stake. Only valid on emergency unstake without rewards and when voting
  error NoStakeFound();
  // @notice Thrown when trying to stake when staking has been paused/ended
  error RewardDistributionPeriodHasExpired();
  // @notice Thrown when trying to stake but reward distribution has not been set
  error RewardPerBlockIsNotSet();
  // @notice Thrown when setting new rewardToken but it is same as old rewardToken
  error SameRewardToken();
  // @notice Thrown triggers on stake, updateRewards and migrateFunds
  error ZeroInput();
  // @notice Thrown when trying to vote against the non-active proposal
  error InvalidProposal();
  // @notice Thrown when trying to double vote within the same epoch
  error AlreadyVoted();

  // Events
  // @notice Emitted when user stakes, unstakes or claims rewards
  // @param user Address of the user who triggered the staking function
  // @param amount Amount of tokens being staked or unstaked
  // @param pendingReward Amount of reward token being claimed if there is any
  // @param txType Type of transaction (stake, unstake, claim, emergency)
  event StakeOrUnstakeOrClaim(address indexed user, uint256 amount, uint256 pendingReward, TxType txType);
  // @notice Emitted when new reward period is started
  // @param numberBlocksToDistributeRewards Number of blocks to distribute rewards in this period
  // @param newRewardPerBlock New reward per block for this period
  // @param rewardToDistribute Total reward to distribute in this period
  // @param rewardExpirationBlock Block number when this reward period will expire, also useful if ending reward period early
  // @dev only use when extending the reward period with same reward amount
  event NewRewardPeriod(
    uint256 numberBlocksToDistributeRewards,
    uint256 newRewardPerBlock,
    uint256 rewardToDistribute,
    uint256 rewardExpirationBlock
  );
  // @notice Emitted when governance address is updated
  // @param oldGovernance Old governance address
  // @param newGovernance New governance address
  event GovernanceChanged(address indexed oldGovernance, address indexed newGovernance);
  // @notice Emitted when reward token is changed or initialized
  // @param oldRewardToken Old reward token address
  // @param newRewardToken New reward token address
  event RewardTokenChanged(address indexed oldRewardToken, address indexed newRewardToken);
  // @notice Emitted when migrating the staking contract to new version
  // @param _newVersion Address of the new staking contract
  // @param _tokens Array of token addresses being migrated
  // @param _amounts Array of token amounts being migrated against the tokens array
  // @dev Both arrays must be in same order length
  event FundsMigrated(address indexed _newVersion, IERC20Metadata[] _tokens, uint256[] _amounts);
  // @notice Emitted when entending the reward period without changing the reward amount
  // @param numberBlocksToDistributeRewards Number of blocks to distribute rewards in this period
  // @param rewardExpirationBlock Block number when this reward period will expire
  event PeriodEndBlockUpdate(uint256 numberBlocksToDistributeRewards, uint256 rewardExpirationBlock);

  // @notice Emitted when voting for a proposal
  // @param _proposalAddress Address of the proposal to vote for
  // @param _user Address of the user who triggered the vote
  // @param _epochId Epoch id for which the vote was triggered
  event Vote(address indexed _proposalAddress, address indexed _user, uint256 indexed _epochId);

  // Structs and Types
  // Info of each user
  struct UserInfo {
    uint256 lastUpdateRewardToken; // Timestamp of last reward token update - used to reset user reward debt
    uint256 amount; // Amount of BTX tokens staked by the user
    uint256 rewardDebt; // Reward debt, total reward paid out so far
  }

  // To determine transaction type
  enum TxType {
    STAKE,
    UNSTAKE,
    CLAIM,
    EMERGENCY
  }

  // Functions
  // @notice calculate pending rewards for a user
  // @param _user Address of the user
  // @return pending rewards to claim if any
  function calculatePendingRewards(address _user) external view returns (uint256);

  // @notice Returns the last block number when rewards were claimed
  // @return if period is ended then it will return the block number when period ended otherwise the current block number
  function lastRewardBlock() external view returns (uint256);

  // @notice introduced a new reward token for staking and reset the reward distribution
  // @param _newRewardToken Address of the new reward token
  function updateRewardToken(address _newRewardToken) external;

  // @notice new reward amount with new reward duration
  // @param _reward New reward amount to distribute
  // @param _rewardDurationInBlocks Number of blocks to distribute the reward
  // @param _newEpoch True if new epoch is being started
  function updateRewards(uint256 _reward, uint256 _rewardDurationInBlocks, bool _newEpoch) external;

  // @notice Extend the reward period without changing the reward amount
  // @param _numberBlocksToDistributeRewards Number of blocks to distribute rewards in this period
  function updateRewardEndBlock(uint256 _expireDurationInBlocks) external;

  // @notice Migrate funds to new staking contract
  // @param _newVersion Address of the new staking contract
  // @param _tokens Array of token addresses being migrated
  // @param _amounts Array of token amounts being migrated against the tokens array
  // @param _isBTXMigrate True if migrating to new staking contract
  // @dev Both arrays must be in same order length
  // @dev Can not migrate users' stake
  function migrateFunds(
    address _newVersion,
    IERC20Metadata[] calldata _tokens,
    uint256[] calldata _amounts,
    bool _isBTXMigrate
  ) external;

  // @notice Stake tokens to earn rewards also triggers the claim
  // @param _to Address of the user who is staking
  // @param _amount Amount of tokens to stake
  function stake(address _to, uint256 _amount) external;

  // @notice Unstake tokens and claim rewards
  // @param _amount Amount of tokens to unstake
  function unstake(uint256 _amount) external;

  // @notice emergencyUnstake tokens without claiming rewards
  // @dev Only use in case of emergency
  function emergencyUnstake() external;

  // @notice Claim rewards against staked amount
  function claim() external;
}
